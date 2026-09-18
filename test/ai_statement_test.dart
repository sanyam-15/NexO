import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/ai/llm_client.dart';
import 'package:nexo/features/ai/domain/ai_services.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

/// Returns a canned structured response, capturing the last schema it saw.
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(this.response);
  final Map<String, dynamic> response;
  Map<String, dynamic>? lastSchema;
  List<AiImage>? lastImages;

  @override
  String get defaultModel => 'fake';
  @override
  String get label => 'fake';

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
    lastSchema = inputSchema;
    lastImages = images;
    return response;
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async =>
      '';
}

void main() {
  group('AiServices.parseStatementText', () {
    test('maps a transactions list and drops non-positive amounts', () async {
      final fake = _FakeLlmClient({
        'transactions': [
          {'amount': 120.5, 'type': 'expense', 'title': 'Tacos', 'category': 'Comida'},
          {'amount': 3500, 'type': 'income', 'title': 'Sueldo'},
          {'amount': 0, 'type': 'expense', 'title': 'Saldo'}, // dropped
        ],
      });
      final svc = AiServices(fake);
      final out = await svc.parseStatementText('texto', categories: ['Comida'], accounts: ['Débito']);
      expect(out.length, 2);
      expect(out[0].title, 'Tacos');
      expect(out[0].type, EntryType.expense);
      expect(out[0].categoryName, 'Comida');
      expect(out[1].type, EntryType.income);
      // The schema asked for an array of transactions.
      expect(fake.lastSchema?['properties'], contains('transactions'));
    });

    test('returns empty on blank input without calling the model', () async {
      final fake = _FakeLlmClient({'transactions': []});
      final svc = AiServices(fake);
      final out = await svc.parseStatementText('   ', categories: [], accounts: []);
      expect(out, isEmpty);
      expect(fake.lastSchema, isNull); // never called
    });
  });

  group('AiServices.parseStatementImages', () {
    test('forwards images and maps results', () async {
      final fake = _FakeLlmClient({
        'transactions': [
          {'amount': 50, 'type': 'expense', 'title': 'OXXO'},
        ],
      });
      final svc = AiServices(fake);
      final out = await svc.parseStatementImages(
        [AiImage(base64Data: 'abc', mediaType: 'image/png')],
        categories: const [],
        accounts: const [],
      );
      expect(out.single.title, 'OXXO');
      expect(fake.lastImages?.length, 1);
    });
  });
}
