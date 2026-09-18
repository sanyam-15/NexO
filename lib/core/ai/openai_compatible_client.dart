import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

/// Client for any OpenAI-compatible Chat Completions endpoint.
///
/// Covers OpenAI, Groq, OpenRouter, DeepSeek, Mistral, xAI (Grok), Together,
/// Google's Gemini compat layer (incl. Gemma models), and local servers such
/// as Ollama (`http://host:11434/v1`) or LM Studio (`http://host:1234/v1`).
///
/// Structured output uses function calling (`tools` + `tool_choice`). Smaller
/// local models sometimes ignore `tool_choice` and answer with JSON in the
/// message body instead, so we fall back to parsing the content as JSON.
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient({
    required this.baseUrl,
    required this.apiKey,
    required this.defaultModel,
    this.label = 'OpenAI-compatible',
    this.isLocal = false,
    this.extraHeaders = const {},
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Base URL including the version segment, e.g. `https://api.openai.com/v1`.
  final String baseUrl;

  /// Bearer token. May be empty for local servers that require no auth.
  final String apiKey;

  @override
  final String defaultModel;

  @override
  final String label;

  /// Whether this points at a local server (Ollama/LM Studio). Local models can
  /// be slow to cold-load, so they get a longer request timeout.
  final bool isLocal;

  /// Provider-specific headers (e.g. OpenRouter attribution). Optional.
  final Map<String, String> extraHeaders;

  final http.Client _http;

  Duration get _timeout => isLocal ? const Duration(seconds: 180) : const Duration(seconds: 60);

  Uri get _endpoint {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/chat/completions');
  }

  /// OpenAI's reasoning models (o1/o3/o4, gpt-5) reject `max_tokens` and require
  /// `max_completion_tokens`. Pick the right key from the model id (after
  /// stripping any `provider/` prefix used by gateways like OpenRouter).
  static const _reasoningPrefixes = ['o1', 'o3', 'o4', 'gpt-5'];

  String _tokenParam(String model) {
    final id = (model.contains('/') ? model.split('/').last : model).toLowerCase();
    final isReasoning = _reasoningPrefixes.any(id.startsWith);
    return isReasoning ? 'max_completion_tokens' : 'max_tokens';
  }

  List<Map<String, dynamic>> _messages(String system, String userText, List<AiImage> images) {
    final Object userContent = images.isEmpty
        ? userText
        : <Map<String, dynamic>>[
            {'type': 'text', 'text': userText},
            for (final img in images)
              {
                'type': 'image_url',
                'image_url': {'url': img.dataUri},
              },
          ];
    return [
      if (system.trim().isNotEmpty) {'role': 'system', 'content': system},
      {'role': 'user', 'content': userContent},
    ];
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
    final m = model ?? defaultModel;
    final body = {
      'model': m,
      _tokenParam(m): maxTokens,
      'messages': _messages(system, userText, images),
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': toolName,
            'description': toolDescription,
            'parameters': inputSchema,
          },
        },
      ],
      'tool_choice': {
        'type': 'function',
        'function': {'name': toolName},
      },
    };

    final json = await _post(body);
    final message = _firstMessage(json);

    // Primary path: a forced function call with JSON arguments.
    final toolCalls = message?['tool_calls'];
    if (toolCalls is List && toolCalls.isNotEmpty) {
      final fn = (toolCalls.first as Map)['function'];
      final args = fn is Map ? fn['arguments'] : null;
      final parsed = _asJsonObject(args);
      if (parsed != null) return parsed;
      // Arguments present but unparseable (often a truncated response) — surface
      // it instead of masking it behind the generic "no structured data" error.
      if (args is String && args.trim().isNotEmpty) {
        final snippet = args.length > 200 ? '${args.substring(0, 200)}…' : args;
        throw AiException('Argumentos de la función ilegibles (¿respuesta truncada?): $snippet');
      }
    }

    // Fallback: model emitted JSON directly in the message content.
    final parsed = _asJsonObject(message?['content']);
    if (parsed != null) return parsed;

    throw AiException('La respuesta no incluyó datos estructurados.');
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    final m = model ?? defaultModel;
    final body = {
      'model': m,
      _tokenParam(m): maxTokens,
      'messages': _messages(system, userText, const []),
    };
    final json = await _post(body);
    final content = _firstMessage(json)?['content'];
    final text = (content is String ? content : content?.toString() ?? '').trim();
    if (text.isEmpty) throw AiException('Respuesta vacía del modelo.');
    return text;
  }

  Map<String, dynamic>? _firstMessage(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final msg = (choices.first as Map)['message'];
      if (msg is Map) return Map<String, dynamic>.from(msg);
    }
    return null;
  }

  /// Coerces a value into a JSON object: accepts an actual Map, or a string
  /// containing JSON (optionally wrapped in ```json fences). Tries the whole
  /// (de-fenced) string first, then falls back to the first `{`…last `}` span.
  Map<String, dynamic>? _asJsonObject(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is! String) return null;
    var s = value.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceFirst(RegExp(r'\s*```$'), '').trim();
    }
    final whole = _tryDecodeObject(s);
    if (whole != null) return whole;
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return _tryDecodeObject(s.substring(start, end + 1));
  }

  Map<String, dynamic>? _tryDecodeObject(String s) {
    try {
      final decoded = jsonDecode(s);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    http.Response res;
    try {
      res = await _http
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              if (apiKey.trim().isNotEmpty) 'authorization': 'Bearer ${apiKey.trim()}',
              ...extraHeaders,
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw AiException(isLocal
          ? 'El modelo local tardó demasiado en responder. Si es la primera consulta puede estar cargando el modelo; intenta de nuevo.'
          : 'La IA tardó demasiado en responder (timeout).');
    } catch (e) {
      throw AiException('No se pudo conectar con $label: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw AiException('API key inválida o sin permiso (${res.statusCode}).');
    }
    if (res.statusCode == 404) {
      throw AiException('Endpoint o modelo no encontrado (404). Revisa la URL base y el modelo.');
    }
    if (res.statusCode == 429) {
      throw AiException('Límite de uso alcanzado (429). Intenta más tarde.');
    }
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final err = jsonDecode(res.body);
        detail = (err['error']?['message'] ??
                err['error']?['code'] ??
                err['message'] ??
                err['detail'] ??
                err['error'] ??
                detail)
            .toString();
      } catch (_) {}
      throw AiException('Error de IA (${res.statusCode}): $detail');
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw AiException('Respuesta ilegible de $label.');
    }
  }
}
