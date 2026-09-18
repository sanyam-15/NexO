import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/llm_client.dart';
import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';
import 'ai_context.dart';
import 'ai_mode.dart';

/// Kinds of plan the Planes module can generate.
enum PlanType { ahorro, deuda, presupuesto, general }

extension PlanTypeX on PlanType {
  String get label {
    switch (this) {
      case PlanType.ahorro:
        return 'Plan de ahorro';
      case PlanType.deuda:
        return 'Pago de deudas';
      case PlanType.presupuesto:
        return 'Presupuesto mensual';
      case PlanType.general:
        return 'Plan integral';
    }
  }

  String get emoji {
    switch (this) {
      case PlanType.ahorro:
        return '🐷';
      case PlanType.deuda:
        return '💳';
      case PlanType.presupuesto:
        return '📊';
      case PlanType.general:
        return '🧭';
    }
  }

  IconData get icon {
    switch (this) {
      case PlanType.ahorro:
        return Icons.savings_rounded;
      case PlanType.deuda:
        return Icons.credit_card_rounded;
      case PlanType.presupuesto:
        return Icons.pie_chart_rounded;
      case PlanType.general:
        return Icons.explore_rounded;
    }
  }

  String get promptHint {
    switch (this) {
      case PlanType.ahorro:
        return 'Diseña un plan de ahorro realista para los próximos meses, con un '
            'aporte mensual sugerido y de dónde recortar para lograrlo.';
      case PlanType.deuda:
        return 'Diseña un plan para liquidar las deudas pendientes lo antes posible, '
            'eligiendo entre método avalancha (mayor tasa primero) o bola de nieve '
            '(saldo menor primero) y justificando brevemente la elección.';
      case PlanType.presupuesto:
        return 'Diseña un presupuesto mensual por categorías basado en los ingresos y '
            'patrones de gasto del usuario (estilo 50/30/20 ajustado a su realidad).';
      case PlanType.general:
        return 'Diseña un plan financiero integral con prioridades: fondo de emergencia, '
            'control de deuda, ahorro y crecimiento, en pasos ordenados.';
    }
  }

  static PlanType fromName(String? name) =>
      PlanType.values.firstWhere((t) => t.name == name, orElse: () => PlanType.general);
}

class PlanStep {
  const PlanStep({required this.title, required this.detail, this.amount});
  final String title;
  final String detail;
  final double? amount;

  Map<String, dynamic> toJson() => {'title': title, 'detail': detail, if (amount != null) 'amount': amount};

  factory PlanStep.fromJson(Map<String, dynamic> j) => PlanStep(
        title: (j['title'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble(),
      );
}

/// A persisted, AI-generated financial plan.
class FinancialPlan {
  const FinancialPlan({
    required this.id,
    required this.type,
    required this.title,
    required this.summary,
    required this.steps,
    this.milestones = const [],
    this.monthlyTarget,
    this.horizonMonths,
    required this.createdAt,
    this.status = 'active',
  });

  final String id;
  final PlanType type;
  final String title;
  final String summary;
  final List<PlanStep> steps;
  final List<String> milestones;
  final double? monthlyTarget;
  final int? horizonMonths;
  final DateTime createdAt;
  final String status;

  /// JSON stored in the `body` column (everything not in its own column).
  Map<String, dynamic> get body => {
        'summary': summary,
        'steps': steps.map((s) => s.toJson()).toList(),
        'milestones': milestones,
        if (monthlyTarget != null) 'monthlyTarget': monthlyTarget,
        if (horizonMonths != null) 'horizonMonths': horizonMonths,
      };

  factory FinancialPlan.fromBody({
    required String id,
    required PlanType type,
    required String title,
    required String status,
    required DateTime createdAt,
    required Map<String, dynamic> body,
  }) {
    final stepsRaw = body['steps'];
    final steps = <PlanStep>[
      if (stepsRaw is List)
        for (final s in stepsRaw)
          if (s is Map) PlanStep.fromJson(Map<String, dynamic>.from(s)),
    ];
    final ms = body['milestones'];
    return FinancialPlan(
      id: id,
      type: type,
      title: title,
      summary: (body['summary'] ?? '').toString(),
      steps: steps,
      milestones: ms is List ? ms.map((e) => e.toString()).toList() : const [],
      monthlyTarget: (body['monthlyTarget'] as num?)?.toDouble(),
      horizonMonths: (body['horizonMonths'] as num?)?.toInt(),
      createdAt: createdAt,
      status: status,
    );
  }

  /// Builds a fresh plan from the model's structured output.
  factory FinancialPlan.fromInput(Map<String, dynamic> input, {required PlanType type}) {
    final stepsRaw = input['steps'];
    final steps = <PlanStep>[
      if (stepsRaw is List)
        for (final s in stepsRaw)
          if (s is Map)
            PlanStep(
              title: (s['title'] ?? '').toString().trim(),
              detail: (s['detail'] ?? '').toString().trim(),
              amount: (s['amount'] as num?)?.toDouble(),
            ),
    ]..removeWhere((s) => s.title.isEmpty);
    final ms = input['milestones'];
    return FinancialPlan(
      id: newId('plan'),
      type: type,
      title: (input['title'] as String?)?.trim().isNotEmpty == true
          ? input['title'] as String
          : type.label,
      summary: (input['summary'] ?? '').toString().trim(),
      steps: steps,
      milestones: ms is List ? ms.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : const [],
      monthlyTarget: (input['monthly_target'] as num?)?.toDouble(),
      horizonMonths: (input['horizon_months'] as num?)?.toInt(),
      createdAt: DateTime.now(),
    );
  }
}

class AiPlanService {
  AiPlanService(this.client, {this.persona = ''});
  final LlmClient client;
  final String persona;

  static const _schema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Título corto del plan.'},
      'summary': {'type': 'string', 'description': 'Resumen del plan en 1-2 frases.'},
      'monthly_target': {'type': 'number', 'description': 'Monto mensual sugerido en MXN, si aplica.'},
      'horizon_months': {'type': 'integer', 'description': 'Horizonte del plan en meses, si aplica.'},
      'steps': {
        'type': 'array',
        'description': 'Pasos accionables en orden.',
        'items': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'detail': {'type': 'string'},
            'amount': {'type': 'number', 'description': 'Monto asociado al paso, si aplica.'},
          },
          'required': ['title', 'detail'],
        },
      },
      'milestones': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Hitos para medir el avance.',
      },
    },
    'required': ['title', 'summary', 'steps'],
  };

  Future<FinancialPlan> generatePlan(
    PlanType type,
    FinancialSnapshot snapshot, {
    String? focus,
  }) async {
    final input = await client.extractStructured(
      system: '$persona\n\n'
          '${type.promptHint} Usa SOLO las cifras del resumen del usuario; no inventes '
          'datos. Los pasos deben ser concretos y medibles. Devuelve montos en MXN.',
      userText: [
        snapshot.toPromptText(),
        if (focus != null && focus.trim().isNotEmpty) '\nEnfoque pedido por el usuario: $focus',
      ].join('\n'),
      toolName: 'crear_plan',
      toolDescription: 'Devuelve un plan financiero estructurado y accionable.',
      inputSchema: _schema,
      maxTokens: 1500,
    );
    return FinancialPlan.fromInput(input, type: type);
  }
}

final aiPlanServiceProvider = Provider<AiPlanService?>((ref) {
  final client = ref.watch(llmClientProvider);
  if (client == null) return null;
  return AiPlanService(client, persona: ref.watch(aiPersonaProvider));
});

/// Stores the generated plans in the `ai_plans` table.
class AiPlansNotifier extends StateNotifier<List<FinancialPlan>> {
  AiPlansNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select(
      'SELECT id, type, title, body, status, created_at FROM ai_plans ORDER BY created_at DESC',
    );
    state = rows.map((r) {
      Map<String, dynamic> body;
      try {
        body = jsonDecode(r['body'] as String) as Map<String, dynamic>;
      } catch (_) {
        body = const {};
      }
      return FinancialPlan.fromBody(
        id: r['id'] as String,
        type: PlanTypeX.fromName(r['type'] as String?),
        title: r['title'] as String,
        status: (r['status'] as String?) ?? 'active',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        body: body,
      );
    }).toList();
  }

  void save(FinancialPlan plan) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO ai_plans (id, type, title, body, status, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      [
        plan.id,
        plan.type.name,
        plan.title,
        jsonEncode(plan.body),
        plan.status,
        plan.createdAt.toIso8601String(),
      ],
    );
    load();
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM ai_plans WHERE id = ?', [id]);
    load();
  }
}

final aiPlansProvider = StateNotifierProvider<AiPlansNotifier, List<FinancialPlan>>(
  (ref) => AiPlansNotifier(),
);
