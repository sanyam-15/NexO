/// Provider-agnostic contract for the AI layer.
///
/// Nexo can talk to several backends (Anthropic's native Messages API, any
/// OpenAI-compatible `/chat/completions` endpoint — OpenAI, Groq, OpenRouter,
/// DeepSeek, Mistral, xAI, Gemini's compat layer, or a local Ollama/LM Studio
/// server — or a Gemma model running fully on-device). They all expose the same
/// two capabilities the app needs, so the feature code depends on this
/// interface instead of a concrete client.
library;

import 'dart:convert';

/// Thrown when an AI call fails or returns an unusable response.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => 'AiException: $message';
}

/// An image to attach to a vision request (e.g. a receipt photo).
class AiImage {
  AiImage({required this.base64Data, this.mediaType = 'image/jpeg'});
  final String base64Data;
  final String mediaType;

  /// Data URI form used by OpenAI-compatible `image_url` content blocks.
  String get dataUri => 'data:$mediaType;base64,$base64Data';
}

/// Common interface implemented by every AI backend.
abstract class LlmClient {
  /// The model used when a call does not specify one.
  String get defaultModel;

  /// A short human label for the active backend (shown in errors/diagnostics).
  String get label;

  /// Forces the model to return a JSON object matching [inputSchema].
  ///
  /// Anthropic does this via forced tool use; OpenAI-compatible backends via
  /// function calling. Optional [images] enable vision (receipt scanning).
  Future<Map<String, dynamic>> extractStructured({
    required String system,
    required String userText,
    required String toolName,
    required String toolDescription,
    required Map<String, dynamic> inputSchema,
    List<AiImage> images = const [],
    String? model,
    int maxTokens = 1024,
  });

  /// Plain text completion (free-form output).
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  });
}

/// Best-effort extraction of a JSON object from a model's text reply. Handles a
/// clean object, ```json fenced blocks, and prose surrounding the object.
/// Shared by the OpenAI-compatible content fallback and the on-device client
/// (which has no native structured-output mode and must prompt for JSON).
Map<String, dynamic>? parseJsonObjectLoose(Object? value) {
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
