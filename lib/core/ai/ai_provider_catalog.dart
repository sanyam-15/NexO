/// Catalog of AI providers Nexo can connect to, plus the serializable profile
/// the user configures for each one.
///
/// Two transport kinds cover everything: Anthropic's native Messages API, and
/// the OpenAI-compatible Chat Completions API used by every other provider —
/// cloud (OpenAI, Groq, OpenRouter, DeepSeek, Mistral, xAI, Together, Gemini)
/// and local (Ollama, LM Studio). "Local AI like Gemma" is simply a local
/// OpenAI-compatible server pointed at a Gemma/Llama model — no extra deps.
library;

enum AiProviderKind { anthropic, openai, onDevice }

AiProviderKind _kindFromName(String? name) {
  switch (name) {
    case 'anthropic':
      return AiProviderKind.anthropic;
    case 'onDevice':
      return AiProviderKind.onDevice;
    default:
      return AiProviderKind.openai;
  }
}

/// A static provider definition with sensible defaults.
class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.kind,
    required this.label,
    required this.defaultModel,
    this.defaultBaseUrl = '',
    this.modelSuggestions = const [],
    this.requiresKey = true,
    this.baseUrlEditable = false,
    this.isLocal = false,
    this.note,
    this.keysUrl,
  });

  final String id;
  final AiProviderKind kind;
  final String label;
  final String defaultModel;
  final String defaultBaseUrl;
  final List<String> modelSuggestions;

  /// Whether the endpoint needs an API key (local servers usually don't).
  final bool requiresKey;

  /// Whether the user may edit the base URL (custom / local servers).
  final bool baseUrlEditable;

  /// Runs on the user's own machine/network (privacy: data stays local).
  final bool isLocal;

  /// Optional helper text shown under the provider in settings.
  final String? note;

  /// Where to get an API key, if applicable.
  final String? keysUrl;

  AiProviderProfile toProfile() => AiProviderProfile(
        id: id,
        kind: kind,
        label: label,
        baseUrl: defaultBaseUrl,
        model: defaultModel,
        apiKey: '',
        requiresKey: requiresKey,
        baseUrlEditable: baseUrlEditable,
        isLocal: isLocal,
      );
}

/// The user's saved settings for one provider (persisted as JSON).
class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.kind,
    required this.label,
    required this.model,
    this.baseUrl = '',
    this.apiKey = '',
    this.requiresKey = true,
    this.baseUrlEditable = false,
    this.isLocal = false,
  });

  final String id;
  final AiProviderKind kind;
  final String label;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool requiresKey;
  final bool baseUrlEditable;
  final bool isLocal;

  /// Configured enough to make a call: has a model, an endpoint where needed,
  /// and a key where required.
  bool get isConfigured {
    if (model.trim().isEmpty) return false;
    if (kind == AiProviderKind.openai && baseUrl.trim().isEmpty) return false;
    if (requiresKey && apiKey.trim().isEmpty) return false;
    return true;
  }

  AiProviderProfile copyWith({String? baseUrl, String? apiKey, String? model}) {
    return AiProviderProfile(
      id: id,
      kind: kind,
      label: label,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      requiresKey: requiresKey,
      baseUrlEditable: baseUrlEditable,
      isLocal: isLocal,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'requiresKey': requiresKey,
        'baseUrlEditable': baseUrlEditable,
        'isLocal': isLocal,
      };

  factory AiProviderProfile.fromJson(Map<String, dynamic> j) =>
      AiProviderProfile(
        id: (j['id'] ?? '').toString(),
        kind: _kindFromName(j['kind'] as String?),
        label: (j['label'] ?? '').toString(),
        baseUrl: (j['baseUrl'] ?? '').toString(),
        apiKey: (j['apiKey'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
        requiresKey: j['requiresKey'] as bool? ?? true,
        baseUrlEditable: j['baseUrlEditable'] as bool? ?? false,
        isLocal: j['isLocal'] as bool? ?? false,
      );
}

/// All providers offered out of the box.
const List<AiProviderPreset> kAiProviderPresets = [
  AiProviderPreset(
    id: 'anthropic',
    kind: AiProviderKind.anthropic,
    label: 'Anthropic (Claude)',
    defaultModel: 'claude-haiku-4-5',
    modelSuggestions: [
      'claude-haiku-4-5',
      'claude-sonnet-4-6',
      'claude-opus-4-8'
    ],
    keysUrl: 'https://console.anthropic.com/settings/keys',
  ),
  AiProviderPreset(
    id: 'openai',
    kind: AiProviderKind.openai,
    label: 'OpenAI',
    defaultBaseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    modelSuggestions: ['gpt-4o-mini', 'gpt-4o', 'o4-mini'],
    keysUrl: 'https://platform.openai.com/api-keys',
  ),
  AiProviderPreset(
    id: 'gemini',
    kind: AiProviderKind.openai,
    label: 'Google Gemini / Gemma',
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.0-flash',
    modelSuggestions: [
      'gemini-2.0-flash',
      'gemini-1.5-flash',
      'gemma-3-27b-it'
    ],
    note:
        'Endpoint compatible con OpenAI de Google. Incluye modelos Gemma en la nube.',
    keysUrl: 'https://aistudio.google.com/apikey',
  ),
  AiProviderPreset(
    id: 'groq',
    kind: AiProviderKind.openai,
    label: 'Groq',
    defaultBaseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama-3.3-70b-versatile',
    modelSuggestions: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
    keysUrl: 'https://console.groq.com/keys',
  ),
  AiProviderPreset(
    id: 'openrouter',
    kind: AiProviderKind.openai,
    label: 'OpenRouter',
    defaultBaseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-4o-mini',
    modelSuggestions: [
      'openai/gpt-4o-mini',
      'google/gemma-3-27b-it',
      'anthropic/claude-3.5-haiku'
    ],
    note: 'Un solo key, cientos de modelos de muchos proveedores.',
    keysUrl: 'https://openrouter.ai/keys',
  ),
  AiProviderPreset(
    id: 'deepseek',
    kind: AiProviderKind.openai,
    label: 'DeepSeek',
    defaultBaseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    modelSuggestions: ['deepseek-chat', 'deepseek-reasoner'],
    keysUrl: 'https://platform.deepseek.com/api_keys',
  ),
  AiProviderPreset(
    id: 'mistral',
    kind: AiProviderKind.openai,
    label: 'Mistral',
    defaultBaseUrl: 'https://api.mistral.ai/v1',
    defaultModel: 'mistral-small-latest',
    modelSuggestions: [
      'mistral-small-latest',
      'mistral-large-latest',
      'pixtral-12b-latest'
    ],
    keysUrl: 'https://console.mistral.ai/api-keys',
  ),
  AiProviderPreset(
    id: 'xai',
    kind: AiProviderKind.openai,
    label: 'xAI (Grok)',
    defaultBaseUrl: 'https://api.x.ai/v1',
    defaultModel: 'grok-2-latest',
    modelSuggestions: ['grok-2-latest', 'grok-2-vision-latest'],
    keysUrl: 'https://console.x.ai',
  ),
  AiProviderPreset(
    id: 'together',
    kind: AiProviderKind.openai,
    label: 'Together AI',
    defaultBaseUrl: 'https://api.together.xyz/v1',
    defaultModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    modelSuggestions: [
      'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      'google/gemma-2-27b-it'
    ],
    keysUrl: 'https://api.together.ai/settings/api-keys',
  ),
  AiProviderPreset(
    id: 'ollama',
    kind: AiProviderKind.openai,
    label: 'Ollama (local)',
    defaultBaseUrl: 'http://localhost:11434/v1',
    defaultModel: 'gemma3',
    modelSuggestions: ['gemma3', 'llama3.2', 'qwen2.5', 'mistral'],
    requiresKey: false,
    baseUrlEditable: true,
    isLocal: true,
    note:
        'IA local en tu equipo. Emulador Android: usa http://10.0.2.2:11434/v1. '
        'Teléfono físico (misma Wi-Fi): la IP de tu PC, p. ej. http://192.168.1.10:11434/v1. '
        'Arranca Ollama accesible con OLLAMA_HOST=0.0.0.0.',
  ),
  AiProviderPreset(
    id: 'lmstudio',
    kind: AiProviderKind.openai,
    label: 'LM Studio (local)',
    defaultBaseUrl: 'http://localhost:1234/v1',
    defaultModel: 'local-model',
    requiresKey: false,
    baseUrlEditable: true,
    isLocal: true,
    note:
        'Servidor local de LM Studio. Emulador Android: http://10.0.2.2:1234/v1. '
        'Teléfono físico (misma Wi-Fi): la IP de tu PC. Activa "Serve on local network" en LM Studio.',
  ),
  AiProviderPreset(
    id: 'cli_bridge',
    kind: AiProviderKind.openai,
    label: 'Claude Code / Codex (bridge local)',
    defaultBaseUrl: 'http://127.0.0.1:8787/v1',
    defaultModel: 'claude-opus-4-8',
    modelSuggestions: [
      'claude-opus-4-8',
      'claude-sonnet-4-6',
      'gpt-5-codex',
      'gpt-5',
      'o4-mini'
    ],
    requiresKey: false,
    baseUrlEditable: true,
    isLocal: true,
    note:
        'Usa tus SUSCRIPCIONES de Claude Code y Codex vía un bridge local en Termux '
        '(ver tools/nexo-ai-bridge). El modelo decide el backend: claude-* → Claude Code; '
        'gpt-*/o*/codex → Codex. Uso personal: consume tu cupo de la suscripción y no '
        'comparte credenciales. Pon un BRIDGE_TOKEN y úsalo como API key para más seguridad.',
  ),
  AiProviderPreset(
    id: 'gemma_device',
    kind: AiProviderKind.onDevice,
    label: 'Gemma on-device (offline)',
    defaultModel: '',
    requiresKey: false,
    isLocal: true,
    note:
        'Descarga un modelo Gemma 4 y córrelo DENTRO del teléfono, sin internet y '
        'SIN token. La descarga es grande (2–4 GB), única vez. Gestiona la descarga abajo.',
  ),
  AiProviderPreset(
    id: 'custom',
    kind: AiProviderKind.openai,
    label: 'Personalizado (OpenAI-compatible)',
    defaultBaseUrl: '',
    defaultModel: '',
    requiresKey: false,
    baseUrlEditable: true,
    note:
        'Cualquier endpoint compatible con OpenAI: pega la URL base (con /v1) y el modelo.',
  ),
];

AiProviderPreset presetById(String id) => kAiProviderPresets
    .firstWhere((p) => p.id == id, orElse: () => kAiProviderPresets.first);
