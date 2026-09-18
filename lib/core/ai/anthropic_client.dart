import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_client.dart';

// Re-export the shared AI types so existing `import 'anthropic_client.dart'`
// sites keep compiling after the multi-provider refactor.
export 'llm_client.dart' show AiException, AiImage;

/// Raw-HTTP client for the Anthropic Messages API.
///
/// Dart has no official Anthropic SDK, so this talks to `POST /v1/messages`
/// directly. Structured output is obtained via forced tool use: we declare a
/// single tool with the desired JSON Schema and set tool_choice to that tool,
/// then read the validated `input` object back from the tool_use block.
class AnthropicClient implements LlmClient {
  AnthropicClient({
    required this.apiKey,
    this.defaultModel = 'claude-haiku-4-5',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  @override
  final String defaultModel;
  final http.Client _http;

  @override
  String get label => 'Anthropic';

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

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
    final content = <Map<String, dynamic>>[
      for (final img in images)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': img.mediaType, 'data': img.base64Data},
        },
      {'type': 'text', 'text': userText},
    ];

    final body = {
      'model': model ?? defaultModel,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'tools': [
        {'name': toolName, 'description': toolDescription, 'input_schema': inputSchema},
      ],
      'tool_choice': {'type': 'tool', 'name': toolName},
    };

    final json = await _post(body);

    final blocks = (json['content'] as List?) ?? const [];
    for (final block in blocks) {
      if (block is Map && block['type'] == 'tool_use' && block['name'] == toolName) {
        final input = block['input'];
        if (input is Map<String, dynamic>) return input;
        if (input is Map) return Map<String, dynamic>.from(input);
      }
    }
    throw AiException('La respuesta no incluyó datos estructurados.');
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    final body = {
      'model': model ?? defaultModel,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': userText},
      ],
    };
    final json = await _post(body);
    final blocks = (json['content'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is Map && block['type'] == 'text') buffer.write(block['text']);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw AiException('Respuesta vacía del modelo.');
    return text;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _version,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 40));
    } catch (e) {
      throw AiException('No se pudo conectar con la IA: $e');
    }

    if (res.statusCode == 401) throw AiException('API key inválida (401).');
    if (res.statusCode == 429) throw AiException('Límite de uso alcanzado (429). Intenta más tarde.');
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final err = jsonDecode(res.body);
        detail = (err['error']?['message'] ?? detail).toString();
      } catch (_) {}
      throw AiException('Error de IA (${res.statusCode}): $detail');
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw AiException('Respuesta ilegible de la IA.');
    }
  }
}
