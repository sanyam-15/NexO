import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexo/features/documents/domain/remote_ocr_client.dart';

void main() {
  group('RemoteOcrClient.recognize', () {
    test('rejects a non-http(s) endpoint before any network call', () async {
      var called = false;
      final client = RemoteOcrClient(
        httpClient: MockClient((req) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        client.recognize(
          baseUrl: 'ftp://example.com',
          apiKey: 'k',
          model: 'mistral-ocr-latest',
          bytes: const [1, 2, 3],
          mimeType: 'image/png',
        ),
        throwsA(predicate((e) => e is RemoteOcrException && e.message.contains('URL http(s)'))),
      );
      expect(called, isFalse);
    });

    test('surfaces a 4xx rejection error', () async {
      final client = RemoteOcrClient(
        httpClient: MockClient((req) async => http.Response('bad request', 422)),
      );
      await expectLater(
        client.recognize(
          baseUrl: 'https://api.example.com',
          apiKey: 'k',
          model: 'm',
          bytes: const [1, 2, 3],
          mimeType: 'image/png',
        ),
        throwsA(predicate((e) =>
            e is RemoteOcrException && e.message.contains('rechazó') && e.message.contains('422'))),
      );
    });

    test('surfaces a 5xx unavailable error', () async {
      final client = RemoteOcrClient(
        httpClient: MockClient((req) async => http.Response('boom', 503)),
      );
      await expectLater(
        client.recognize(
          baseUrl: 'https://api.example.com',
          apiKey: 'k',
          model: 'm',
          bytes: const [1, 2, 3],
          mimeType: 'image/png',
        ),
        throwsA(predicate((e) =>
            e is RemoteOcrException && e.message.contains('no disponible') && e.message.contains('503'))),
      );
    });

    test('rejects an empty/whitespace OCR result', () async {
      final client = RemoteOcrClient(
        httpClient: MockClient((req) async => http.Response(
              jsonEncode({
                'pages': [
                  {'markdown': '   '},
                ],
              }),
              200,
            )),
      );
      await expectLater(
        client.recognize(
          baseUrl: 'https://api.example.com',
          apiKey: 'k',
          model: 'm',
          bytes: const [1, 2, 3],
          mimeType: 'image/png',
        ),
        throwsA(isA<RemoteOcrException>()),
      );
    });

    test('decodes accented Spanish markdown as UTF-8 (no mojibake)', () async {
      // Server returns UTF-8 bytes with NO charset in Content-Type, exactly the
      // case where http.Response.body would otherwise fall back to latin1.
      final payload = jsonEncode({
        'pages': [
          {'markdown': 'Café México — €1.234,56 pagados en señal ñ'},
        ],
      });
      final client = RemoteOcrClient(
        httpClient: MockClient((req) async => http.Response.bytes(
              utf8.encode(payload),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );
      final out = await client.recognize(
        baseUrl: 'https://api.example.com',
        apiKey: 'k',
        model: 'm',
        bytes: const [1, 2, 3],
        mimeType: 'application/pdf',
      );
      expect(out.contains('Café México'), isTrue);
      expect(out.contains('€1.234,56'), isTrue);
      expect(out.contains('señal ñ'), isTrue);
      // No replacement characters from a botched decode.
      expect(out.contains('�'), isFalse);
    });
  });
}
