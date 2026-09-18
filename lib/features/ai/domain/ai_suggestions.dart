import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import '../../../core/util/ids.dart';
import 'ai_context.dart';
import 'ai_mode.dart';

/// Where a suggestion can take the user. Maps to a router route + an icon so the
/// model only has to pick from a fixed, safe set (no free-form navigation).
enum SuggestionAction { budgets, goals, debts, accounts, transactions, recurring, categories, planning, none }

extension SuggestionActionX on SuggestionAction {
  String? get routeName {
    switch (this) {
      case SuggestionAction.budgets:
        return 'budgets';
      case SuggestionAction.goals:
        return 'goals';
      case SuggestionAction.debts:
        return 'debts';
      case SuggestionAction.accounts:
        return 'accounts';
      case SuggestionAction.transactions:
        return 'transactions';
      case SuggestionAction.recurring:
        return 'recurring';
      case SuggestionAction.categories:
        return 'categories';
      case SuggestionAction.planning:
        return 'planning';
      case SuggestionAction.none:
        return null;
    }
  }

  IconData get icon {
    switch (this) {
      case SuggestionAction.budgets:
        return Icons.account_balance_rounded;
      case SuggestionAction.goals:
        return Icons.savings_rounded;
      case SuggestionAction.debts:
        return Icons.handshake_rounded;
      case SuggestionAction.accounts:
        return Icons.account_balance_wallet_rounded;
      case SuggestionAction.transactions:
        return Icons.receipt_long_rounded;
      case SuggestionAction.recurring:
        return Icons.event_repeat_rounded;
      case SuggestionAction.categories:
        return Icons.category_rounded;
      case SuggestionAction.planning:
        return Icons.insights_rounded;
      case SuggestionAction.none:
        return Icons.lightbulb_outline_rounded;
    }
  }

  static SuggestionAction fromName(String? name) =>
      SuggestionAction.values.firstWhere((a) => a.name == name, orElse: () => SuggestionAction.none);
}

class AiSuggestion {
  const AiSuggestion({
    required this.id,
    required this.title,
    required this.body,
    this.priority = 2,
    this.action = SuggestionAction.none,
  });

  final String id;
  final String title;
  final String body;
  final int priority; // 1 = alta, 3 = baja
  final SuggestionAction action;
}

class AiSuggestionsService {
  AiSuggestionsService(this.client, {this.persona = ''});
  final LlmClient client;
  final String persona;

  static const _schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'suggestions': {
        'type': 'array',
        'description': 'De 3 a 5 sugerencias breves y accionables.',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Sugerencia en pocas palabras.'},
            'body': {'type': 'string', 'description': 'Una frase con el porqué/cómo.'},
            'priority': {'type': 'integer', 'description': '1 alta, 2 media, 3 baja.'},
            'action': {
              'type': 'string',
              'enum': ['budgets', 'goals', 'debts', 'accounts', 'transactions', 'recurring', 'categories', 'planning', 'none'],
              'description': 'A qué sección de la app llevar al usuario.',
            },
          },
          'required': ['title', 'body'],
        },
      },
    },
    'required': ['suggestions'],
  };

  Future<List<AiSuggestion>> suggest(FinancialSnapshot snapshot, {String? context}) async {
    final input = await client.extractStructured(
      system: '$persona\n\n'
          'A partir del resumen financiero, da de 3 a 5 sugerencias breves, concretas '
          'y accionables, ordenadas por prioridad. Usa cifras del resumen cuando ayuden. '
          'Para cada una elige la acción (sección de la app) más útil de la lista.',
      userText: [
        snapshot.toPromptText(),
        if (context != null && context.trim().isNotEmpty) '\nContexto: $context',
      ].join('\n'),
      toolName: 'dar_sugerencias',
      toolDescription: 'Devuelve sugerencias financieras accionables.',
      inputSchema: _schema,
      maxTokens: 900,
    );
    final raw = input['suggestions'];
    if (raw is! List) return const [];
    final out = <AiSuggestion>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final title = (e['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(AiSuggestion(
        id: newId('sug'),
        title: title,
        body: (e['body'] ?? '').toString().trim(),
        priority: ((e['priority'] as num?)?.toInt() ?? 2).clamp(1, 3),
        action: SuggestionActionX.fromName(e['action'] as String?),
      ));
    }
    out.sort((a, b) => a.priority.compareTo(b.priority));
    return out;
  }
}

final aiSuggestionsServiceProvider = Provider<AiSuggestionsService?>((ref) {
  final client = ref.watch(llmClientProvider);
  if (client == null) return null;
  return AiSuggestionsService(client, persona: ref.watch(aiPersonaProvider));
});

class SuggestionsState {
  const SuggestionsState({this.loading = false, this.error, this.suggestions, this.signature});
  final bool loading;
  final String? error;
  final List<AiSuggestion>? suggestions;
  final String? signature;

  SuggestionsState copyWith({
    bool? loading,
    Object? error = _sentinel,
    List<AiSuggestion>? suggestions,
    String? signature,
  }) {
    return SuggestionsState(
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
      suggestions: suggestions ?? this.suggestions,
      signature: signature ?? this.signature,
    );
  }

  static const _sentinel = Object();
}

class AiSuggestionsController extends StateNotifier<SuggestionsState> {
  AiSuggestionsController(this.ref) : super(const SuggestionsState());
  final Ref ref;

  /// Cache key = snapshot fingerprint + active Modo. An attempt is cached on
  /// success AND error, so a failed call is not silently re-billed on every
  /// re-open — only a manual refresh (force) or a real data/Modo change re-calls.
  String _key() => '${ref.read(financialSnapshotProvider).signature}|${ref.read(aiModeProvider).name}';

  Future<void> ensure({bool force = false}) async {
    final svc = ref.read(aiSuggestionsServiceProvider);
    if (svc == null) return;
    final key = _key();
    if (!force && state.signature == key) return;
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await svc.suggest(ref.read(financialSnapshotProvider));
      if (!mounted) return;
      state = SuggestionsState(suggestions: result, signature: key);
    } on AiException catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e.message, signature: key);
    } catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: 'Algo salió mal: $e', signature: key);
    }
  }

  Future<void> refresh() => ensure(force: true);
}

final aiSuggestionsControllerProvider =
    StateNotifierProvider<AiSuggestionsController, SuggestionsState>((ref) => AiSuggestionsController(ref));
