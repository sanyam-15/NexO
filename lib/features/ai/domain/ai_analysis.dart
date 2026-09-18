import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import 'ai_context.dart';
import 'ai_mode.dart';

typedef CategoryNote = ({String category, String note});

/// Structured financial diagnosis produced by the Análisis module.
class FinancialAnalysis {
  const FinancialAnalysis({
    required this.healthScore,
    required this.headline,
    required this.strengths,
    required this.risks,
    required this.opportunities,
    required this.categoryNotes,
  });

  final int healthScore; // 0–100
  final String headline;
  final List<String> strengths;
  final List<String> risks;
  final List<String> opportunities;
  final List<CategoryNote> categoryNotes;

  static List<String> _stringList(Object? v) {
    if (v is! List) return const [];
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  factory FinancialAnalysis.fromInput(Map<String, dynamic> input) {
    final notes = <CategoryNote>[];
    final raw = input['category_notes'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final cat = (e['category'] ?? '').toString().trim();
          final note = (e['note'] ?? '').toString().trim();
          if (cat.isNotEmpty && note.isNotEmpty) notes.add((category: cat, note: note));
        }
      }
    }
    final score = ((input['health_score'] as num?)?.round() ?? 0).clamp(0, 100);
    return FinancialAnalysis(
      healthScore: score,
      headline: (input['headline'] as String?)?.trim().isNotEmpty == true
          ? input['headline'] as String
          : 'Análisis de tus finanzas',
      strengths: _stringList(input['strengths']),
      risks: _stringList(input['risks']),
      opportunities: _stringList(input['opportunities']),
      categoryNotes: notes,
    );
  }
}

class AiAnalysisService {
  AiAnalysisService(this.client, {this.persona = ''});
  final LlmClient client;
  final String persona;

  static const _schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'health_score': {
        'type': 'integer',
        'description': 'Salud financiera global de 0 (crítica) a 100 (excelente).',
      },
      'headline': {'type': 'string', 'description': 'Diagnóstico en una frase.'},
      'strengths': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Lo que el usuario hace bien.',
      },
      'risks': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Riesgos o focos rojos a atender.',
      },
      'opportunities': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Oportunidades concretas de mejora.',
      },
      'category_notes': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'category': {'type': 'string'},
            'note': {'type': 'string'},
          },
          'required': ['category', 'note'],
        },
      },
    },
    'required': ['health_score', 'headline'],
  };

  Future<FinancialAnalysis> analyze(FinancialSnapshot snapshot) async {
    final input = await client.extractStructured(
      system: '$persona\n\n'
          'Analiza la situación financiera del usuario y devuelve un diagnóstico '
          'estructurado, concreto y accionable. Calcula health_score considerando '
          'tasa de ahorro, control de presupuestos, deuda y avance de metas. '
          'Cada punto debe ser una frase breve y útil, basada en las cifras dadas.',
      userText: snapshot.toPromptText(),
      toolName: 'diagnostico_financiero',
      toolDescription: 'Devuelve un diagnóstico financiero estructurado.',
      inputSchema: _schema,
      maxTokens: 1300,
    );
    return FinancialAnalysis.fromInput(input);
  }
}

final aiAnalysisServiceProvider = Provider<AiAnalysisService?>((ref) {
  final client = ref.watch(llmClientProvider);
  if (client == null) return null;
  return AiAnalysisService(client, persona: ref.watch(aiPersonaProvider));
});

/// Cached, auto-generating state for the Análisis module.
class AnalysisState {
  const AnalysisState({this.loading = false, this.error, this.analysis, this.signature});
  final bool loading;
  final String? error;
  final FinancialAnalysis? analysis;
  final String? signature;

  AnalysisState copyWith({
    bool? loading,
    Object? error = _sentinel,
    FinancialAnalysis? analysis,
    String? signature,
  }) {
    return AnalysisState(
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
      analysis: analysis ?? this.analysis,
      signature: signature ?? this.signature,
    );
  }

  static const _sentinel = Object();
}

class AiAnalysisController extends StateNotifier<AnalysisState> {
  AiAnalysisController(this.ref) : super(const AnalysisState());
  final Ref ref;

  /// Cache key = snapshot fingerprint + active Modo, so a data change OR a Modo
  /// change regenerates, but a plain re-open does not.
  String _key() => '${ref.read(financialSnapshotProvider).signature}|${ref.read(aiModeProvider).name}';

  /// Generates for the current snapshot+mode, reusing the cached attempt when
  /// the key is unchanged. An attempt is cached on success AND on error, so a
  /// failed call is not silently re-billed on every re-open — only a manual
  /// refresh (force) or a real data/Modo change re-calls the provider.
  Future<void> ensure({bool force = false}) async {
    final svc = ref.read(aiAnalysisServiceProvider);
    if (svc == null) return;
    final key = _key();
    if (!force && state.signature == key) return;
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await svc.analyze(ref.read(financialSnapshotProvider));
      if (!mounted) return;
      state = AnalysisState(analysis: result, signature: key);
    } on AiException catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: e.message, signature: key);
    } catch (e) {
      if (mounted) state = state.copyWith(loading: false, error: 'Algo salió mal: $e', signature: key);
    }
  }

  Future<void> refresh() => ensure(force: true);
}

final aiAnalysisControllerProvider =
    StateNotifierProvider<AiAnalysisController, AnalysisState>((ref) => AiAnalysisController(ref));
