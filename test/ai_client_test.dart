import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexo/core/ai/ai_config.dart';
import 'package:nexo/core/ai/ai_provider_catalog.dart';
import 'package:nexo/core/ai/anthropic_client.dart';
import 'package:nexo/core/ai/llm_client.dart';
import 'package:nexo/core/ai/on_device_gemma_client.dart';
import 'package:nexo/core/ai/openai_compatible_client.dart';

void main() {
  group('OpenAiCompatibleClient.extractStructured', () {
    test('shapes a function-calling request and parses tool arguments', () async {
      late http.Request captured;
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test',
        defaultModel: 'gpt-4o-mini',
        label: 'Example',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'reg',
                          'arguments': '{"amount": 45, "type": "expense", "title": "Café"}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final out = await client.extractStructured(
        system: 'sys',
        userText: 'café 45',
        toolName: 'reg',
        toolDescription: 'desc',
        inputSchema: const {'type': 'object'},
      );

      expect(out['amount'], 45);
      expect(out['type'], 'expense');
      expect(out['title'], 'Café');

      // Endpoint, auth header and OpenAI-style body.
      expect(captured.url.toString(), 'https://api.example.com/v1/chat/completions');
      expect(captured.headers['authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      expect(body['tool_choice'], {
        'type': 'function',
        'function': {'name': 'reg'},
      });
      expect((body['tools'] as List).first['function']['name'], 'reg');
      final messages = body['messages'] as List;
      expect(messages.first, {'role': 'system', 'content': 'sys'});
      expect(messages.last, {'role': 'user', 'content': 'café 45'});
    });

    test('trims trailing slashes from the base URL', () async {
      late Uri url;
      final client = OpenAiCompatibleClient(
        baseUrl: 'http://localhost:11434/v1/',
        apiKey: '',
        defaultModel: 'gemma3',
        httpClient: MockClient((req) async {
          url = req.url;
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': '{"ok": true}'}}
              ]
            }),
            200,
          );
        }),
      );
      await client.extractStructured(
        system: 's',
        userText: 'u',
        toolName: 't',
        toolDescription: 'd',
        inputSchema: const {},
      );
      expect(url.toString(), 'http://localhost:11434/v1/chat/completions');
    });

    test('omits the auth header when the key is empty (local server)', () async {
      late http.Request captured;
      final client = OpenAiCompatibleClient(
        baseUrl: 'http://localhost:11434/v1',
        apiKey: '',
        defaultModel: 'gemma3',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': '{"ok": true}'}}
              ]
            }),
            200,
          );
        }),
      );
      final out = await client.extractStructured(
        system: 's',
        userText: 'u',
        toolName: 't',
        toolDescription: 'd',
        inputSchema: const {},
      );
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(out['ok'], true);
    });

    test('falls back to JSON in message content when no tool_calls', () async {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://x/v1',
        apiKey: 'k',
        defaultModel: 'm',
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'Aquí tienes:\n```json\n{"amount": 10}\n```'}
                }
              ]
            }),
            200,
          );
        }),
      );
      final out = await client.extractStructured(
        system: 's',
        userText: 'u',
        toolName: 't',
        toolDescription: 'd',
        inputSchema: const {},
      );
      expect(out['amount'], 10);
    });

    test('encodes images as image_url data URIs', () async {
      late Map<String, dynamic> body;
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://x/v1',
        apiKey: 'k',
        defaultModel: 'm',
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {'function': {'name': 't', 'arguments': '{}'}}
                    ]
                  }
                }
              ]
            }),
            200,
          );
        }),
      );
      await client.extractStructured(
        system: 's',
        userText: 'recibo',
        toolName: 't',
        toolDescription: 'd',
        inputSchema: const {},
        images: [AiImage(base64Data: 'QUJD', mediaType: 'image/png')],
      );
      final content = (body['messages'] as List).last['content'] as List;
      expect(content.first, {'type': 'text', 'text': 'recibo'});
      expect(content.last['type'], 'image_url');
      expect(content.last['image_url']['url'], 'data:image/png;base64,QUJD');
    });

    test('uses max_completion_tokens for OpenAI reasoning models, max_tokens otherwise', () async {
      Future<String> tokenKeyFor(String model) async {
        late String key;
        final client = OpenAiCompatibleClient(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'k',
          defaultModel: model,
          httpClient: MockClient((req) async {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            key = body.containsKey('max_completion_tokens') ? 'max_completion_tokens' : 'max_tokens';
            return http.Response(
              jsonEncode({
                'choices': [
                  {'message': {'content': '{"ok": true}'}}
                ]
              }),
              200,
            );
          }),
        );
        await client.complete(system: 's', userText: 'u');
        return key;
      }

      expect(await tokenKeyFor('gpt-4o-mini'), 'max_tokens');
      expect(await tokenKeyFor('o4-mini'), 'max_completion_tokens');
      expect(await tokenKeyFor('gpt-5'), 'max_completion_tokens');
      // OpenRouter-style "provider/model" prefix is stripped before matching.
      expect(await tokenKeyFor('openai/o3-mini'), 'max_completion_tokens');
    });

    test('surfaces unparseable tool-call arguments instead of a generic error', () async {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://x/v1',
        apiKey: 'k',
        defaultModel: 'm',
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {'function': {'name': 't', 'arguments': '{"amount": 45, "ti'}}
                    ]
                  }
                }
              ]
            }),
            200,
          );
        }),
      );
      await expectLater(
        client.extractStructured(
          system: 's',
          userText: 'u',
          toolName: 't',
          toolDescription: 'd',
          inputSchema: const {},
        ),
        throwsA(predicate((e) => e is AiException && e.message.contains('truncada'))),
      );
    });

    test('maps 401 to a friendly AiException', () async {
      final client = OpenAiCompatibleClient(
        baseUrl: 'https://x/v1',
        apiKey: 'bad',
        defaultModel: 'm',
        httpClient: MockClient((req) async => http.Response('nope', 401)),
      );
      expect(
        () => client.complete(system: 's', userText: 'u'),
        throwsA(isA<AiException>()),
      );
    });
  });

  group('AnthropicClient', () {
    test('parses tool_use input from a Messages response', () async {
      final client = AnthropicClient(
        apiKey: 'sk-ant',
        defaultModel: 'claude-haiku-4-5',
        httpClient: MockClient((req) async {
          expect(req.headers['x-api-key'], 'sk-ant');
          return http.Response(
            jsonEncode({
              'content': [
                {'type': 'tool_use', 'name': 'reg', 'input': {'amount': 99}}
              ]
            }),
            200,
          );
        }),
      );
      final out = await client.extractStructured(
        system: 's',
        userText: 'u',
        toolName: 'reg',
        toolDescription: 'd',
        inputSchema: const {},
      );
      expect(out['amount'], 99);
    });
  });

  group('AiProviderProfile / catalog', () {
    test('every preset builds a profile and a client', () {
      for (final preset in kAiProviderPresets) {
        final p = preset.toProfile().copyWith(apiKey: 'k', model: 'm', baseUrl: 'https://x/v1');
        final client = clientForProfile(p);
        expect(client, isA<LlmClient>());
        switch (preset.kind) {
          case AiProviderKind.anthropic:
            expect(client, isA<AnthropicClient>());
          case AiProviderKind.openai:
            expect(client, isA<OpenAiCompatibleClient>());
          case AiProviderKind.onDevice:
            expect(client, isA<OnDeviceGemmaClient>());
        }
      }
    });

    test('isConfigured requires a key only when the provider needs one', () {
      final ollama = presetById('ollama').toProfile().copyWith(model: 'gemma3');
      expect(ollama.requiresKey, isFalse);
      expect(ollama.isConfigured, isTrue); // local, no key needed

      final openai = presetById('openai').toProfile().copyWith(model: 'gpt-4o-mini');
      expect(openai.isConfigured, isFalse); // missing key
      expect(openai.copyWith(apiKey: 'sk').isConfigured, isTrue);
    });

    test('profile JSON round-trips', () {
      final p = presetById('groq').toProfile().copyWith(apiKey: 'k', model: 'llama-3.3-70b-versatile');
      final back = AiProviderProfile.fromJson(p.toJson());
      expect(back.id, 'groq');
      expect(back.kind, AiProviderKind.openai);
      expect(back.apiKey, 'k');
      expect(back.model, 'llama-3.3-70b-versatile');
      expect(back.requiresKey, isTrue);
    });
  });
}
