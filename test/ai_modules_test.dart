import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/core/ai/llm_client.dart';
import 'package:nexo/features/accounts/domain/account.dart';
import 'package:nexo/features/ai/domain/ai_analysis.dart';
import 'package:nexo/features/ai/domain/ai_context.dart';
import 'package:nexo/features/ai/domain/ai_mode.dart';
import 'package:nexo/features/ai/domain/ai_module.dart';
import 'package:nexo/features/ai/domain/ai_plans.dart';
import 'package:nexo/features/ai/domain/ai_suggestions.dart';
import 'package:nexo/features/goals/domain/goal.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

/// Records the prompts it receives and replays canned structured/text replies,
/// so the AI module mapping can be tested without a network/provider.
class FakeLlmClient implements LlmClient {
  FakeLlmClient({this.responses = const {}, this.completion = 'respuesta de prueba'});

  final Map<String, Map<String, dynamic>> responses;
  final String completion;
  String? lastSystem;
  String? lastUserText;

  @override
  String get defaultModel => 'fake';

  @override
  String get label => 'Fake';

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
    lastSystem = system;
    lastUserText = userText;
    return responses[toolName] ?? const {};
  }

  @override
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    lastSystem = system;
    lastUserText = userText;
    return completion;
  }
}

FinancialSnapshot _sampleSnapshot() {
  final now = DateTime(2026, 6, 15);
  final txns = [
    FinanceEntry(id: 'i1', title: 'Sueldo', amount: 10000, category: 'Ingresos', date: DateTime(2026, 6, 10), type: EntryType.income),
    FinanceEntry(id: 'e1', title: 'Súper', amount: 3000, category: 'Comida', date: DateTime(2026, 6, 5), type: EntryType.expense),
    FinanceEntry(id: 'e2', title: 'Uber', amount: 1000, category: 'Transporte', date: DateTime(2026, 6, 8), type: EntryType.expense),
    // Previous month (for the category delta).
    FinanceEntry(id: 'e0', title: 'Súper mayo', amount: 2000, category: 'Comida', date: DateTime(2026, 5, 10), type: EntryType.expense),
    // Unpaid + transfer should be excluded from flow.
    FinanceEntry(id: 'u1', title: 'Planeado', amount: 5000, category: 'Comida', date: DateTime(2026, 6, 9), type: EntryType.expense, paid: false),
  ];
  return buildSnapshot(
    transactions: txns,
    accounts: [],
    accountBalances: {},
    netWorth: 12345,
    budgetProgress: [],
    goals: [],
    debtNet: 0,
    upcoming: [],
    now: now,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_MX', null);
  });

  group('buildSnapshot', () {
    test('aggregates month-to-date income, expense and savings rate', () {
      final s = _sampleSnapshot();
      expect(s.income, 10000);
      expect(s.expense, 4000); // unpaid 5000 excluded
      expect(s.balance, 6000);
      expect(s.savingsRate, closeTo(0.6, 1e-9));
      expect(s.txCount, 3); // 1 income + 2 paid expenses
      expect(s.netWorth, 12345);
    });

    test('ranks top categories with previous-month deltas', () {
      final s = _sampleSnapshot();
      expect(s.topCategories.first.name, 'Comida');
      expect(s.topCategories.first.amount, 3000);
      expect(s.topCategories.first.prevAmount, 2000);
      expect(s.topCategories[1].name, 'Transporte');
      expect(s.topCategories[1].prevAmount, 0);
    });

    test('toPromptText surfaces the key figures', () {
      final text = _sampleSnapshot().toPromptText();
      expect(text, contains('Tasa de ahorro del mes: 60%'));
      expect(text, contains('Comida'));
      expect(text, contains('Patrimonio neto'));
    });

    test('signature reflects goal-progress changes (cache must not go stale)', () {
      FinancialSnapshot withGoal(double current) => buildSnapshot(
            transactions: [],
            accounts: [],
            accountBalances: {},
            netWorth: 0,
            budgetProgress: [],
            goals: [Goal(id: 'g1', name: 'Viaje', targetAmount: 10000, currentAmount: current, color: 0xFF000000, createdAt: DateTime(2026, 1, 1))],
            debtNet: 0,
            upcoming: [],
            now: DateTime(2026, 6, 15),
          );
      expect(withGoal(1000).signature, isNot(equals(withGoal(2000).signature)));
    });
  });

  group('AiCoachMode persona', () {
    test('preamble names the active mode and differs between modes', () {
      final ahorro = personaPreamble(AiCoachMode.ahorro);
      final inversion = personaPreamble(AiCoachMode.inversion);
      expect(ahorro, contains('Ahorro'));
      expect(inversion, contains('Inversión'));
      expect(ahorro, isNot(equals(inversion)));
    });
  });

  group('AiAnalysisService', () {
    test('maps structured output and injects the persona', () async {
      final fake = FakeLlmClient(responses: {
        'diagnostico_financiero': {
          'health_score': 82,
          'headline': 'Vas bien',
          'strengths': ['Ahorras', ''],
          'risks': [],
          'opportunities': ['Invierte el excedente'],
          'category_notes': [
            {'category': 'Comida', 'note': 'Gasto alto'},
          ],
        },
      });
      final svc = AiAnalysisService(fake, persona: 'PERSONA_TEST');
      final a = await svc.analyze(_sampleSnapshot());

      expect(a.healthScore, 82);
      expect(a.headline, 'Vas bien');
      expect(a.strengths, ['Ahorras']); // empties stripped
      expect(a.opportunities, ['Invierte el excedente']);
      expect(a.categoryNotes.single.category, 'Comida');
      expect(fake.lastSystem, contains('PERSONA_TEST'));
    });
  });

  group('AiPlanService', () {
    test('maps a plan and round-trips through its persisted body', () async {
      final fake = FakeLlmClient(responses: {
        'crear_plan': {
          'title': 'Plan de ahorro 90 días',
          'summary': 'Aparta poco a poco.',
          'monthly_target': 1500,
          'horizon_months': 6,
          'steps': [
            {'title': 'Automatiza', 'detail': 'Transferencia el día de pago', 'amount': 1500},
          ],
          'milestones': ['Primer mes completado'],
        },
      });
      final svc = AiPlanService(fake, persona: 'P');
      final plan = await svc.generatePlan(PlanType.ahorro, _sampleSnapshot());

      expect(plan.type, PlanType.ahorro);
      expect(plan.monthlyTarget, 1500);
      expect(plan.horizonMonths, 6);
      expect(plan.steps.single.amount, 1500);

      final restored = FinancialPlan.fromBody(
        id: plan.id,
        type: plan.type,
        title: plan.title,
        status: 'active',
        createdAt: plan.createdAt,
        body: plan.body,
      );
      expect(restored.steps.single.title, 'Automatiza');
      expect(restored.milestones.single, 'Primer mes completado');
    });
  });

  group('AiSuggestionsService', () {
    test('parses, clamps priority and sorts by it', () async {
      final fake = FakeLlmClient(responses: {
        'dar_sugerencias': {
          'suggestions': [
            {'title': 'Define una meta', 'body': '', 'priority': 9, 'action': 'goals'},
            {'title': 'Reduce el café', 'body': 'Gastas mucho', 'priority': 1, 'action': 'budgets'},
            {'title': '', 'body': 'sin título', 'priority': 2},
          ],
        },
      });
      final svc = AiSuggestionsService(fake, persona: 'P');
      final list = await svc.suggest(_sampleSnapshot());

      expect(list.length, 2); // empty-title dropped
      expect(list.first.title, 'Reduce el café'); // priority 1 first
      expect(list.first.action, SuggestionAction.budgets);
      expect(list.last.priority, 3); // 9 clamped to 3
    });
  });

  group('AI module registry', () {
    test('exposes every module kind', () {
      final ids = kAiModules.map((m) => m.id).toSet();
      expect(ids, containsAll(<String>['analysis', 'plans', 'suggestions', 'mode', 'assistant', 'capture', 'insights']));
    });
  });

  group('signature', () {
    FinancialSnapshot withBalances(Map<String, double> balances) => buildSnapshot(
          transactions: const [],
          accounts: [
            Account(id: 'a1', name: 'Efectivo', type: AccountType.cash, color: 0, createdAt: DateTime(2026)),
            Account(id: 'a2', name: 'Nu', type: AccountType.debit, color: 0, createdAt: DateTime(2026)),
          ],
          accountBalances: balances,
          netWorth: 1000,
          budgetProgress: [],
          goals: [],
          debtNet: 0,
          upcoming: [],
          now: DateTime(2026, 6, 15),
        );

    test('changes when account balances shift, even with totals unchanged', () {
      // A transfer between own accounts: income/expense/netWorth all stay the
      // same, but the prompt's account section changes — the cache must miss.
      final before = withBalances({'a1': 700, 'a2': 300});
      final after = withBalances({'a1': 500, 'a2': 500});
      expect(before.signature, isNot(after.signature));
      expect(before.signature, withBalances({'a1': 700, 'a2': 300}).signature);
    });
  });
}
