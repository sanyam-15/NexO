import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Thrown when the remote OCR endpoint fails or returns an unusable response.
class RemoteOcrException implements Exception {
  RemoteOcrException(this.message);
  final String message;
  @override
  String toString() => 'RemoteOcrException: $message';
}

/// Calls a **Mistral-OCR-compatible** endpoint (`POST {baseUrl}/ocr`) to turn a
/// document/image into markdown text, which is then handed to the AI text
/// extractor. Works with Mistral's cloud API and any self-hosted server that
/// speaks the same contract (e.g. a Mistral OCR 4 container, or a thin wrapper
/// in front of dots.ocr / Marker). The response is parsed leniently: page
/// markdown is preferred, with `text`/`content`/`markdown` fallbacks.
class RemoteOcrClient {
  const RemoteOcrClient({http.Client? httpClient}) : _client = httpClient;

  /// Optional injected client (for tests). When null a one-shot [http.Client] is
  /// created and closed per request.
  final http.Client? _client;

  Future<String> recognize({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/ocr');
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw RemoteOcrException('Endpoint OCR inválido: debe ser una URL http(s).');
    }
    final dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final isPdf = mimeType.contains('pdf');
    final document = isPdf
        ? {'type': 'document_url', 'document_url': dataUri}
        : {'type': 'image_url', 'image_url': dataUri};

    // Scale the timeout with payload size (~20s/MB, min 120s) so large scanned
    // statements on slow links don't time out prematurely.
    final timeoutSecs = (bytes.length / (1024 * 1024)).ceil() * 20;

    final client = _client ?? http.Client();
    final http.Response res;
    try {
      res = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': model.trim().isEmpty ? 'mistral-ocr-latest' : model.trim(),
              'document': document,
              'include_image_base64': false,
            }),
          )
          .timeout(Duration(seconds: timeoutSecs < 120 ? 120 : timeoutSecs));
    } catch (e) {
      throw RemoteOcrException('No se pudo contactar el endpoint OCR: $e');
    } finally {
      if (_client == null) client.close();
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final where = res.statusCode >= 500
          ? 'Servidor OCR no disponible'
          : 'OCR remoto rechazó la solicitud';
      throw RemoteOcrException('$where (${res.statusCode}): ${_trim(res.body)}');
    }

    // Decode bytes as UTF-8 explicitly: http.Response.body falls back to latin1
    // when the server omits charset=utf-8, which mangles accented Spanish text.
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // Some servers return plain text/markdown directly.
      if (body.trim().isEmpty) throw RemoteOcrException('Respuesta OCR vacía.');
      return body;
    }
    return _extractText(decoded);
  }

  /// Pulls markdown/text out of common OCR response shapes. Throws when the
  /// response has no usable (non-whitespace) text so empty results surface as a
  /// failure instead of a silent success.
  String _extractText(Object? decoded) {
    if (decoded is String) {
      if (decoded.trim().isEmpty) throw RemoteOcrException('Respuesta OCR vacía.');
      return decoded;
    }
    if (decoded is Map) {
      final pages = decoded['pages'];
      if (pages is List && pages.isNotEmpty) {
        final buf = StringBuffer();
        for (final pg in pages) {
          if (pg is Map) {
            final t = pg['markdown'] ?? pg['text'] ?? pg['content'];
            if (t is String && t.trim().isNotEmpty) buf.writeln(t);
          } else if (pg is String && pg.trim().isNotEmpty) {
            buf.writeln(pg);
          }
        }
        if (buf.isNotEmpty) return buf.toString();
        throw RemoteOcrException('El endpoint devolvió páginas sin texto reconocible.');
      }
      final direct = decoded['markdown'] ?? decoded['text'] ?? decoded['content'];
      if (direct is String && direct.trim().isNotEmpty) return direct;
    }
    throw RemoteOcrException('Respuesta OCR sin texto reconocible.');
  }

  static String _trim(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

final remoteOcrClientProvider = Provider<RemoteOcrClient>((ref) => const RemoteOcrClient());
