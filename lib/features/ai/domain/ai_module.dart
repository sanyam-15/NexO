import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The AI capabilities Nexo exposes. Used to render the AI hub and settings as
/// a uniform list — "todo como módulos".
enum AiModuleKind { analysis, plans, suggestions, mode, assistant, capture, insights }

class AiModuleDescriptor {
  const AiModuleDescriptor({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.routeName,
  });

  final String id;
  final AiModuleKind kind;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Route to open this module. Null when it opens differently (e.g. a sheet).
  final String? routeName;
}

const List<AiModuleDescriptor> kAiModules = [
  AiModuleDescriptor(
    id: 'analysis',
    kind: AiModuleKind.analysis,
    title: 'Análisis',
    subtitle: 'Diagnóstico de tu salud financiera',
    icon: Icons.monitor_heart_rounded,
    routeName: 'planning',
  ),
  AiModuleDescriptor(
    id: 'plans',
    kind: AiModuleKind.plans,
    title: 'Planes',
    subtitle: 'Ahorro, deudas y presupuesto con IA',
    icon: Icons.flag_rounded,
    routeName: 'planning',
  ),
  AiModuleDescriptor(
    id: 'suggestions',
    kind: AiModuleKind.suggestions,
    title: 'Sugerencias',
    subtitle: 'Recomendaciones según tus datos',
    icon: Icons.lightbulb_rounded,
    routeName: 'planning',
  ),
  AiModuleDescriptor(
    id: 'mode',
    kind: AiModuleKind.mode,
    title: 'Modo',
    subtitle: 'Personalidad y tono del asesor',
    icon: Icons.tune_rounded,
    routeName: 'planning',
  ),
  AiModuleDescriptor(
    id: 'assistant',
    kind: AiModuleKind.assistant,
    title: 'Asistente',
    subtitle: 'Chatea con tu asesor financiero',
    icon: Icons.forum_rounded,
    routeName: 'ai-assistant',
  ),
  AiModuleDescriptor(
    id: 'capture',
    kind: AiModuleKind.capture,
    title: 'Captura con IA',
    subtitle: 'Texto natural o foto de recibo',
    icon: Icons.auto_awesome_rounded,
    routeName: null,
  ),
  AiModuleDescriptor(
    id: 'insights',
    kind: AiModuleKind.insights,
    title: 'Insights',
    subtitle: 'Observaciones rápidas del mes',
    icon: Icons.tips_and_updates_rounded,
    routeName: 'ai-insights',
  ),
];

final aiModulesProvider = Provider<List<AiModuleDescriptor>>((ref) => kAiModules);
