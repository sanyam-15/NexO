import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';

/// The "Modo" AI module: a coaching persona the user picks once and that biases
/// the tone and recommendations of *every* AI surface in the app (analysis,
/// plans, suggestions, the assistant chat, capture and insights). Stored in
/// `app_meta` so the choice survives restarts.
enum AiCoachMode { equilibrio, ahorro, inversion, estricto, tranquilo }

extension AiCoachModeX on AiCoachMode {
  String get label {
    switch (this) {
      case AiCoachMode.equilibrio:
        return 'Equilibrio';
      case AiCoachMode.ahorro:
        return 'Ahorro';
      case AiCoachMode.inversion:
        return 'Inversión';
      case AiCoachMode.estricto:
        return 'Estricto';
      case AiCoachMode.tranquilo:
        return 'Tranquilo';
    }
  }

  String get emoji {
    switch (this) {
      case AiCoachMode.equilibrio:
        return '⚖️';
      case AiCoachMode.ahorro:
        return '🐷';
      case AiCoachMode.inversion:
        return '📈';
      case AiCoachMode.estricto:
        return '🎯';
      case AiCoachMode.tranquilo:
        return '🧘';
    }
  }

  String get description {
    switch (this) {
      case AiCoachMode.equilibrio:
        return 'Balance entre disfrutar hoy y construir futuro.';
      case AiCoachMode.ahorro:
        return 'Maximiza el ahorro y recorta gastos agresivamente.';
      case AiCoachMode.inversion:
        return 'Enfocado en hacer crecer tu dinero e invertir el excedente.';
      case AiCoachMode.estricto:
        return 'Directo y sin rodeos; te marca los excesos sin filtro.';
      case AiCoachMode.tranquilo:
        return 'Tono amable y sin presión; pasos pequeños y sostenibles.';
    }
  }

  /// Persona fragment injected into every AI system prompt. Keep it short and
  /// behavioural — it shapes voice and priorities, never the math.
  String get persona {
    switch (this) {
      case AiCoachMode.equilibrio:
        return 'Adopta un tono equilibrado y realista. Reconoce los logros y propón '
            'mejoras moderadas que no sacrifiquen la calidad de vida.';
      case AiCoachMode.ahorro:
        return 'Adopta una mentalidad de ahorro agresivo. Prioriza recortar gastos '
            'hormiga y no esenciales, y empuja a destinar cada peso libre al ahorro.';
      case AiCoachMode.inversion:
        return 'Adopta una mentalidad de crecimiento patrimonial. Una vez cubierto un '
            'fondo de emergencia, prioriza poner a trabajar el excedente (inversión, '
            'aportaciones periódicas), explicando el riesgo de forma general y sin dar '
            'recomendaciones de instrumentos específicos.';
      case AiCoachMode.estricto:
        return 'Adopta un tono firme y directo, sin rodeos. Señala los excesos con '
            'claridad y exige disciplina, pero siempre con respeto.';
      case AiCoachMode.tranquilo:
        return 'Adopta un tono cálido y sin presión. Evita alarmar; propón pasos '
            'pequeños, alcanzables y sostenibles, celebrando cada avance.';
    }
  }
}

/// Shared identity + active-persona preamble prepended to every AI module's
/// system prompt, so the whole app speaks with one (configurable) voice.
String personaPreamble(AiCoachMode mode) {
  return 'Eres el asesor financiero de Nexo para usuarios en México. Hablas en '
      'español claro, con cifras en pesos (MXN) cuando ayuden. Modo activo: '
      '"${mode.label}". ${mode.persona}';
}

class AiModeNotifier extends StateNotifier<AiCoachMode> {
  AiModeNotifier() : super(AiCoachMode.equilibrio) {
    _load();
  }

  static const _key = 'ai_coach_mode';

  void _load() {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [_key]);
    if (rows.isEmpty) return;
    final name = rows.first['value'] as String;
    state = AiCoachMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => AiCoachMode.equilibrio,
    );
  }

  void setMode(AiCoachMode mode) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)',
      [_key, mode.name],
    );
    state = mode;
  }
}

final aiModeProvider = StateNotifierProvider<AiModeNotifier, AiCoachMode>(
  (ref) => AiModeNotifier(),
);

/// The active persona preamble, recomputed whenever the mode changes.
final aiPersonaProvider = Provider<String>((ref) {
  return personaPreamble(ref.watch(aiModeProvider));
});
