import '../../../core/util/ids.dart';
import 'transaction.dart';

/// How the Quick Add sheet captures a movement.
enum QuickAddMode {
  /// The classic manual form (fields rendered per the layout config).
  manual,

  /// A natural-language / photo input parsed by the AI.
  ai,

  /// AI input on top that pre-fills the manual fields below.
  hybrid,
}

/// Which engine parses uploaded documents.
enum DocumentEngine { configuredProvider, onDevice, askEachTime }

/// How a PDF/image document is turned into text before the AI structures it.
/// [onDeviceOcr] runs Google ML Kit on the phone (local, free) then sends the
/// recognized text to the configured AI; [aiVision] sends the page images
/// straight to the AI vision model (needs a vision-capable provider);
/// [remoteOcr] calls a Mistral-OCR-compatible endpoint (cloud or self-hosted
/// SOTA model) that returns markdown, then sends that to the configured AI.
enum DocumentOcr { onDeviceOcr, aiVision, remoteOcr }

/// A field that can appear in the Quick Add / Batch Add forms.
enum CaptureField { type, amount, title, category, account, currency, date, note, paid }

extension QuickAddModeName on QuickAddMode {
  String get label => switch (this) {
        QuickAddMode.manual => 'Manual',
        QuickAddMode.ai => 'IA',
        QuickAddMode.hybrid => 'Híbrido',
      };
  static QuickAddMode from(String? v) {
    for (final m in QuickAddMode.values) {
      if (m.name == v) return m;
    }
    return QuickAddMode.manual;
  }
}

extension DocumentEngineName on DocumentEngine {
  String get label => switch (this) {
        DocumentEngine.configuredProvider => 'Proveedor configurado',
        DocumentEngine.onDevice => 'Solo en el dispositivo',
        DocumentEngine.askEachTime => 'Preguntar cada vez',
      };
  static DocumentEngine from(String? v) {
    for (final e in DocumentEngine.values) {
      if (e.name == v) return e;
    }
    return DocumentEngine.configuredProvider;
  }
}

extension DocumentOcrName on DocumentOcr {
  String get label => switch (this) {
        DocumentOcr.onDeviceOcr => 'En dispositivo',
        DocumentOcr.aiVision => 'Visión IA',
        DocumentOcr.remoteOcr => 'OCR remoto',
      };
  static DocumentOcr from(String? v) {
    for (final o in DocumentOcr.values) {
      if (o.name == v) return o;
    }
    return DocumentOcr.onDeviceOcr;
  }
}

extension CaptureFieldName on CaptureField {
  String get label => switch (this) {
        CaptureField.type => 'Tipo (gasto/ingreso)',
        CaptureField.amount => 'Monto',
        CaptureField.title => 'Concepto',
        CaptureField.category => 'Categoría',
        CaptureField.account => 'Cuenta',
        CaptureField.currency => 'Moneda',
        CaptureField.date => 'Fecha',
        CaptureField.note => 'Nota',
        CaptureField.paid => 'Pagado / planeado',
      };
  static CaptureField? from(String? v) {
    for (final f in CaptureField.values) {
      if (f.name == v) return f;
    }
    return null;
  }
}

/// A single field's placement: which field and whether it is shown.
class FieldConfig {
  const FieldConfig(this.field, {this.visible = true});
  final CaptureField field;
  final bool visible;

  FieldConfig copyWith({bool? visible}) => FieldConfig(field, visible: visible ?? this.visible);

  Map<String, dynamic> toJson() => {'field': field.name, 'visible': visible};
  static FieldConfig? fromJson(Map<String, dynamic> j) {
    final f = CaptureFieldName.from(j['field'] as String?);
    if (f == null) return null;
    return FieldConfig(f, visible: (j['visible'] as bool?) ?? true);
  }
}

/// Reconstructs an ordered, COMPLETE field list from a saved list: keeps the
/// saved order/visibility and appends any newly added [CaptureField]s (hidden)
/// so the config survives app updates that introduce new fields.
List<FieldConfig> _normalizeFields(List<FieldConfig> saved) {
  final present = {for (final f in saved) f.field};
  final out = <FieldConfig>[...saved];
  for (final f in CaptureField.values) {
    if (!present.contains(f)) out.add(FieldConfig(f, visible: false));
  }
  return out;
}

/// Full capture configuration: Quick Add mode + field layout, Batch Add columns,
/// default values, and the document parsing engine.
class CaptureLayoutConfig {
  CaptureLayoutConfig({
    required this.quickAddMode,
    required this.quickAddFields,
    required this.batchAddFields,
    this.defaultType = EntryType.expense,
    this.defaultCategoryName,
    this.defaultAccountName,
    this.defaultCurrency = 'MXN',
    this.documentEngine = DocumentEngine.configuredProvider,
    this.documentOcr = DocumentOcr.onDeviceOcr,
    this.ocrEndpoint = '',
    this.ocrApiKey = '',
    this.ocrModel = 'mistral-ocr-latest',
  });

  final QuickAddMode quickAddMode;
  final List<FieldConfig> quickAddFields;
  final List<FieldConfig> batchAddFields;
  final EntryType defaultType;
  final String? defaultCategoryName;
  final String? defaultAccountName;
  final String defaultCurrency;
  final DocumentEngine documentEngine;
  final DocumentOcr documentOcr;

  /// Remote OCR (Mistral-OCR-compatible) endpoint base URL, e.g.
  /// `https://api.mistral.ai/v1` or a self-hosted `http://host:port/v1`.
  final String ocrEndpoint;
  final String ocrApiKey;
  final String ocrModel;

  bool get remoteOcrConfigured =>
      documentOcr == DocumentOcr.remoteOcr && ocrEndpoint.trim().isNotEmpty;

  bool isVisible(CaptureField f) =>
      quickAddFields.any((c) => c.field == f && c.visible);

  /// Quick Add fields in display order, visible only.
  List<CaptureField> get visibleQuickFields =>
      [for (final c in quickAddFields) if (c.visible) c.field];

  List<CaptureField> get visibleBatchFields =>
      [for (final c in batchAddFields) if (c.visible) c.field];

  CaptureLayoutConfig copyWith({
    QuickAddMode? quickAddMode,
    List<FieldConfig>? quickAddFields,
    List<FieldConfig>? batchAddFields,
    EntryType? defaultType,
    String? defaultCategoryName,
    bool clearDefaultCategory = false,
    String? defaultAccountName,
    bool clearDefaultAccount = false,
    String? defaultCurrency,
    DocumentEngine? documentEngine,
    DocumentOcr? documentOcr,
    String? ocrEndpoint,
    String? ocrApiKey,
    String? ocrModel,
  }) {
    return CaptureLayoutConfig(
      quickAddMode: quickAddMode ?? this.quickAddMode,
      quickAddFields: quickAddFields ?? this.quickAddFields,
      batchAddFields: batchAddFields ?? this.batchAddFields,
      defaultType: defaultType ?? this.defaultType,
      defaultCategoryName: clearDefaultCategory ? null : (defaultCategoryName ?? this.defaultCategoryName),
      defaultAccountName: clearDefaultAccount ? null : (defaultAccountName ?? this.defaultAccountName),
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      documentEngine: documentEngine ?? this.documentEngine,
      documentOcr: documentOcr ?? this.documentOcr,
      ocrEndpoint: ocrEndpoint ?? this.ocrEndpoint,
      ocrApiKey: ocrApiKey ?? this.ocrApiKey,
      ocrModel: ocrModel ?? this.ocrModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'quickAddMode': quickAddMode.name,
        'quickAddFields': [for (final f in quickAddFields) f.toJson()],
        'batchAddFields': [for (final f in batchAddFields) f.toJson()],
        'defaultType': defaultType.name,
        'defaultCategoryName': defaultCategoryName,
        'defaultAccountName': defaultAccountName,
        'defaultCurrency': defaultCurrency,
        'documentEngine': documentEngine.name,
        'documentOcr': documentOcr.name,
        'ocrEndpoint': ocrEndpoint,
        'ocrApiKey': ocrApiKey,
        'ocrModel': ocrModel,
      };

  static List<FieldConfig> _fieldsFromJson(Object? raw, List<FieldConfig> fallback) {
    if (raw is! List) return fallback;
    final parsed = <FieldConfig>[];
    for (final item in raw) {
      if (item is Map) {
        final fc = FieldConfig.fromJson(item.cast<String, dynamic>());
        if (fc != null) parsed.add(fc);
      }
    }
    if (parsed.isEmpty) return fallback;
    return _normalizeFields(parsed);
  }

  static CaptureLayoutConfig fromJson(Map<String, dynamic> j) {
    final d = defaults;
    return CaptureLayoutConfig(
      quickAddMode: QuickAddModeName.from(j['quickAddMode'] as String?),
      quickAddFields: _fieldsFromJson(j['quickAddFields'], d.quickAddFields),
      batchAddFields: _fieldsFromJson(j['batchAddFields'], d.batchAddFields),
      defaultType: (j['defaultType'] as String?) == 'income' ? EntryType.income : EntryType.expense,
      defaultCategoryName: j['defaultCategoryName'] as String?,
      defaultAccountName: j['defaultAccountName'] as String?,
      defaultCurrency: (j['defaultCurrency'] as String?) ?? 'MXN',
      documentEngine: DocumentEngineName.from(j['documentEngine'] as String?),
      documentOcr: DocumentOcrName.from(j['documentOcr'] as String?),
      ocrEndpoint: (j['ocrEndpoint'] as String?) ?? '',
      ocrApiKey: (j['ocrApiKey'] as String?) ?? '',
      ocrModel: (j['ocrModel'] as String?) ?? 'mistral-ocr-latest',
    );
  }

  /// Reproduces today's Quick Add exactly (type, amount, title, category,
  /// account, currency visible; date/note/paid hidden), so existing users see
  /// no change until they opt in.
  static CaptureLayoutConfig get defaults => CaptureLayoutConfig(
        quickAddMode: QuickAddMode.manual,
        quickAddFields: const [
          FieldConfig(CaptureField.type),
          FieldConfig(CaptureField.amount),
          FieldConfig(CaptureField.title),
          FieldConfig(CaptureField.category),
          FieldConfig(CaptureField.account),
          FieldConfig(CaptureField.currency),
          FieldConfig(CaptureField.date, visible: false),
          FieldConfig(CaptureField.note, visible: false),
          FieldConfig(CaptureField.paid, visible: false),
        ],
        batchAddFields: const [
          FieldConfig(CaptureField.date),
          FieldConfig(CaptureField.title),
          FieldConfig(CaptureField.amount),
          FieldConfig(CaptureField.type),
          FieldConfig(CaptureField.category),
          FieldConfig(CaptureField.account, visible: false),
          FieldConfig(CaptureField.currency, visible: false),
          FieldConfig(CaptureField.note, visible: false),
          FieldConfig(CaptureField.paid, visible: false),
        ],
      );
}

/// A named saved layout the user can switch between.
class CaptureTemplate {
  CaptureTemplate({required this.id, required this.name, required this.config});
  final String id;
  final String name;
  final CaptureLayoutConfig config;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'config': config.toJson()};
  static CaptureTemplate fromJson(Map<String, dynamic> j) => CaptureTemplate(
        id: (j['id'] as String?) ?? newId('tpl'),
        name: (j['name'] as String?) ?? 'Plantilla',
        config: CaptureLayoutConfig.fromJson((j['config'] as Map).cast<String, dynamic>()),
      );
}
