import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import 'llm_client.dart';
import 'on_device_models.dart';

/// Download/lifecycle helpers for on-device Gemma models, wrapping
/// flutter_gemma's modern API. Initialization is lazy: nothing touches the
/// native plugin until the user actually uses an on-device model, so users who
/// stick to cloud providers pay no startup cost.
class OnDeviceGemma {
  OnDeviceGemma._();

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await FlutterGemma.initialize();
    _initialized = true;
  }

  static Future<bool> isInstalled(String modelId) async {
    await ensureInitialized();
    return FlutterGemma.isModelInstalled(modelId);
  }

  static Future<List<String>> installed() async {
    await ensureInitialized();
    return FlutterGemma.listInstalledModels();
  }

  /// Downloads [model] (with an optional Hugging Face [token] for gated models),
  /// reporting progress 0–100. Idempotent: an already-installed model just gets
  /// re-activated. Pass a [cancelToken] to allow aborting.
  static Future<void> download(
    OnDeviceModel model, {
    String? token,
    required void Function(int percent) onProgress,
    CancelToken? cancelToken,
  }) async {
    await ensureInitialized();
    final tok = (token == null || token.trim().isEmpty) ? null : token.trim();
    // foreground: true keeps a multi-GB download alive through backgrounding/doze.
    // install() is idempotent and resumes from the partial (flutter_gemma keys the
    // download by a deterministic taskId), so re-calling this continues, not restarts.
    var builder = FlutterGemma.installModel(modelType: model.modelType, fileType: model.fileType)
        .fromNetwork(model.url, token: tok, foreground: true)
        .withProgress(onProgress);
    if (cancelToken != null) builder = builder.withCancelToken(cancelToken);
    await builder.install();
  }

  static Future<void> remove(String modelId) async {
    await ensureInitialized();
    await FlutterGemma.uninstallModel(modelId);
  }

  /// Path where a sideloaded model file is expected — the app's external files
  /// dir, e.g. `/sdcard/Android/data/<pkg>/files/<modelId>`. Reliable mobile
  /// downloads are fragile, so the file can instead be `adb push`ed here (or
  /// copied by the user) and imported without any in-app download.
  static Future<String?> localModelPath(String modelId) async {
    final dir = await getExternalStorageDirectory();
    return dir == null ? null : '${dir.path}/$modelId';
  }

  static Future<bool> hasLocalFile(String modelId) async {
    final path = await localModelPath(modelId);
    return path != null && File(path).existsSync();
  }

  /// Registers a sideloaded model from its file. flutter_gemma references the
  /// file in place (no re-download, no extra copy), then sets it active.
  static Future<void> importFromFile(OnDeviceModel model) async {
    await ensureInitialized();
    final path = await localModelPath(model.id);
    if (path == null || !File(path).existsSync()) {
      throw AiException('No se encontró el archivo del modelo en el dispositivo.');
    }
    await FlutterGemma.installModel(modelType: model.modelType, fileType: model.fileType)
        .fromFile(path)
        .install();
  }
}

/// [LlmClient] backed by a Gemma model running on the device via MediaPipe.
///
/// Gemma has no native forced-tool-use, so structured output is obtained by
/// prompting the model for a bare JSON object and parsing it loosely. The
/// loaded model is cached across calls because loading weights is expensive.
class OnDeviceGemmaClient implements LlmClient {
  // maxTokens is the model's TOTAL sequence budget (input + output) at load
  // time. The richer Planning prompts (persona + full financial snapshot + the
  // embedded JSON schema for structured output) run ~1.2k input tokens, so the
  // old 1024 budget overflowed ("Input token ids are too long"). Gemma 4
  // supports a far larger context; 4096 leaves comfortable room for input and
  // the generated JSON while staying modest on memory.
  OnDeviceGemmaClient({required this.modelId, this.maxTokens = 4096});

  final String modelId;
  final int maxTokens;

  @override
  String get defaultModel => modelId;

  @override
  String get label => 'Gemma on-device';

  static InferenceModel? _model;
  static String? _loadedId;

  // A single on-device model can only run one inference session at a time, so
  // concurrent calls (e.g. Planning auto-generating Análisis + Sugerencias at
  // once) must be serialized — otherwise the second errors with "Failed to start
  // streaming". This chained future is a lightweight mutex around [_run].
  static Future<void> _inferenceLock = Future<void>.value();

  Future<InferenceModel> _ensureModel() async {
    await OnDeviceGemma.ensureInitialized();
    if (!await FlutterGemma.isModelInstalled(modelId)) {
      throw AiException('El modelo on-device no está descargado. Ve a Ajustes → IA y descárgalo.');
    }
    if (_model != null && _loadedId == modelId) return _model!;

    await _model?.close();
    _model = null;
    _loadedId = null;

    // Re-activate the installed spec (needed after an app restart). install() is
    // idempotent — it skips the download/registration and just sets the active
    // model. Crucially, re-activate from the SAME source the model was installed
    // with: a sideloaded file (fromFile) must not be re-pointed at the network,
    // or its active spec would reference a file that isn't there.
    final spec = onDeviceModelById(modelId);
    if (spec != null) {
      final builder = FlutterGemma.installModel(modelType: spec.modelType, fileType: spec.fileType);
      final localPath = await OnDeviceGemma.localModelPath(modelId);
      if (localPath != null && File(localPath).existsSync()) {
        await builder.fromFile(localPath).install();
      } else {
        await builder.fromNetwork(spec.url).install();
      }
    }

    // Carga el modelo con soporte de imagen si el spec es multimodal (Gemma 4),
    // para poder escanear recibos como fallback de visión.
    final supportsVision = spec?.supportsVision ?? false;
    final model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      supportImage: supportsVision,
      maxNumImages: supportsVision ? 1 : null,
    );
    _model = model;
    _loadedId = modelId;
    return model;
  }

  Future<String> _run(String prompt, {List<AiImage> images = const []}) async {
    // Serialize: wait for any in-flight inference to finish before starting,
    // and let the next caller wait for this one — one session at a time.
    final prior = _inferenceLock;
    final gate = Completer<void>();
    _inferenceLock = gate.future;
    await prior;
    try {
      final model = await _ensureModel();
      final session = await model.createSession(
        enableVisionModality: images.isNotEmpty ? true : null,
      );
      try {
        if (images.isNotEmpty) {
          // Gemma 4 multimodal: una imagen (recibo) + el prompt con el schema.
          await session.addQueryChunk(Message.withImage(
            text: prompt,
            imageBytes: base64Decode(images.first.base64Data),
            isUser: true,
          ));
        } else {
          await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        }
        return await session.getResponse();
      } finally {
        await session.close();
      }
    } finally {
      gate.complete();
    }
  }

  @override
  Future<Map<String, dynamic>> extractStructured({
    required String system,
    required String userText,
    required String toolName,
    required String toolDescription,
    required Map<String, dynamic> inputSchema,
    List<AiImage> images = const [],
    String? model,
    int maxTokens = 1024,
  }) async {
    final visionCapable = onDeviceModelById(modelId)?.supportsVision ?? false;
    if (images.isNotEmpty && !visionCapable) {
      throw AiException(
        'Este modelo on-device no soporta imágenes. Descarga un Gemma 4 (multimodal) para escanear recibos.',
      );
    }
    final prompt = '$system\n\n'
        'Tarea: $toolDescription\n'
        'Responde ÚNICAMENTE con un objeto JSON válido que cumpla este JSON Schema. '
        'Sin texto adicional, sin explicaciones, sin markdown ni comillas de código:\n'
        '${jsonEncode(inputSchema)}\n\n'
        'Entrada del usuario:\n$userText';
    final raw = await _run(prompt, images: images);
    final parsed = parseJsonObjectLoose(raw);
    if (parsed == null) {
      throw AiException('El modelo on-device no devolvió un JSON válido. Prueba un modelo más grande.');
    }
    return parsed;
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    final text = (await _run('$system\n\n$userText')).trim();
    if (text.isEmpty) throw AiException('Respuesta vacía del modelo on-device.');
    return text;
  }
}
