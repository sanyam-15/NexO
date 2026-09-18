import '../../../core/ai/llm_client.dart';
import '../../../core/ai/on_device_gemma_client.dart';
import '../../../core/ai/on_device_models.dart';
import '../../transactions/domain/transaction.dart';

/// A structured draft produced by the AI from natural language or a receipt.
/// Names (category/account) are resolved against the user's catalog by the UI.
class ParsedTransaction {
  ParsedTransaction({
    required this.amount,
    required this.type,
    required this.title,
    this.categoryName,
    this.accountName,
    this.currency = 'MXN',
    this.date,
    this.note,
    this.confidence,
  });

  final double amount;
  final EntryType type;
  final String title;
  final String? categoryName;
  final String? accountName;
  final String currency;
  final DateTime? date;
  final String? note;
  final double? confidence;
}

/// AI label for an auto-captured movement: a clean title and a category. The
/// amount/direction are NOT here — they are parsed deterministically.
class CaptureSuggestion {
  CaptureSuggestion({required this.title, this.category});
  final String title;
  final String? category;
}

class AiServices {
  AiServices(this.client, {this.persona = ''});
  final LlmClient client;

  /// Active coaching-mode persona, prepended to prompts that benefit from tone
  /// (so Captura e Insights also speak in the user's chosen "Modo").
  final String persona;

  String _sys(String base) => persona.trim().isEmpty ? base : '$persona\n\n$base';

  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static const _txSchema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'amount': {'type': 'number', 'description': 'Monto positivo'},
      'type': {
        'type': 'string',
        'enum': ['expense', 'income'],
      },
      'title': {'type': 'string', 'description': 'Concepto corto'},
      'category': {'type': 'string', 'description': 'Nombre de categoría de la lista provista'},
      'account': {'type': 'string', 'description': 'Nombre de cuenta de la lista provista'},
      'currency': {
        'type': 'string',
        'enum': ['MXN', 'USD', 'EUR'],
      },
      'date_iso': {'type': 'string', 'description': 'Fecha ISO 8601 (YYYY-MM-DD)'},
      'note': {'type': 'string'},
    },
    'required': ['amount', 'type', 'title'],
  };

  /// Schema for extracting MANY movements at once (a statement / a CSV / a
  /// multi-line paste). Each item is a [_txSchema] transaction.
  static const _txListSchema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'transactions': {
        'type': 'array',
        'description': 'Lista de TODOS los movimientos detectados, uno por fila.',
        'items': _txSchema,
      },
    },
    'required': ['transactions'],
  };

  ParsedTransaction _fromInput(Map<String, dynamic> input) {
    final a = input['amount'];
    final amount = a is num
        ? a.toDouble()
        : double.tryParse(a?.toString().replaceAll(RegExp(r'[^0-9.\-]'), '') ?? '') ?? 0;
    final type = input['type']?.toString() == 'income' ? EntryType.income : EntryType.expense;
    DateTime? date;
    final dIso = input['date_iso']?.toString();
    if (dIso != null) date = DateTime.tryParse(dIso);
    final title = input['title']?.toString().trim();
    return ParsedTransaction(
      amount: amount.abs(),
      type: type,
      title: title != null && title.isNotEmpty ? title : 'Movimiento',
      categoryName: input['category']?.toString().trim(),
      accountName: input['account']?.toString().trim(),
      currency: input['currency']?.toString() ?? 'MXN',
      date: date,
      note: input['note']?.toString().trim(),
    );
  }

  List<ParsedTransaction> _listFromInput(Map<String, dynamic> input) {
    final raw = (input['transactions'] as List?) ?? const [];
    final out = <ParsedTransaction>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        final p = _fromInput(item.cast<String, dynamic>());
        if (p.amount > 0) out.add(p);
      } catch (_) {
        // Skip a single malformed row; keep the other parsed movements.
      }
    }
    return out;
  }

  /// Parses free text like "café 45 ayer con débito" into a draft transaction.
  Future<ParsedTransaction> parseNaturalLanguage(
    String text, {
    required List<String> categories,
    required List<String> accounts,
  }) async {
    final input = await client.extractStructured(
      system: _sys(
          'Eres un asistente de finanzas para usuarios en México. Conviertes texto en lenguaje natural '
          'en un movimiento financiero estructurado. La fecha de hoy es ${_today()}; resuelve fechas '
          'relativas como "ayer" o "el lunes" a una fecha ISO. La moneda por defecto es MXN. '
          'Elige category y account SOLO de estas listas cuando apliquen.\n'
          'Categorías: ${categories.join(", ")}\n'
          'Cuentas: ${accounts.join(", ")}'),
      userText: text,
      toolName: 'registrar_movimiento',
      toolDescription: 'Registra un movimiento financiero estructurado a partir del texto del usuario.',
      inputSchema: _txSchema,
    );
    return _fromInput(input);
  }

  /// Classifies an already-detected bank/fintech notification into a clean
  /// title + category. The amount and direction were parsed deterministically
  /// (never by the model), so this only labels the movement. Reuses the active
  /// provider — which can be the on-device Gemma, so AutoCapture needs no second
  /// local model.
  Future<CaptureSuggestion> categorizeCapture({
    required String rawText,
    String? merchant,
    required EntryType direction,
    required List<String> categories,
  }) async {
    if (categories.isEmpty) {
      return CaptureSuggestion(title: merchant?.trim().isNotEmpty == true ? merchant!.trim() : 'Movimiento');
    }
    final dir = direction == EntryType.income ? 'ingreso' : 'gasto';
    final input = await client.extractStructured(
      system: _sys(
          'Clasificas un movimiento bancario YA detectado a partir del texto de una notificación de '
          'banco o fintech en México. El monto y el tipo ($dir) ya están determinados; NO los cambies '
          'ni inventes cifras. Devuelve un título corto y legible (el comercio o concepto) y la categoría '
          'MÁS adecuada de la lista.\n'
          'Categorías: ${categories.join(", ")}'),
      userText: merchant != null && merchant.trim().isNotEmpty
          ? 'Comercio detectado: "$merchant".\nTexto de la notificación: "$rawText"'
          : 'Texto de la notificación: "$rawText"',
      toolName: 'clasificar_captura',
      toolDescription: 'Devuelve un título corto y la categoría de un movimiento bancario detectado.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string', 'description': 'Comercio o concepto corto'},
          'category': {
            'type': 'string',
            'enum': categories,
          },
        },
        'required': ['title'],
      },
      maxTokens: 256,
    );
    final title = (input['title'] as String?)?.trim();
    final category = (input['category'] as String?)?.trim();
    return CaptureSuggestion(
      title: title?.isNotEmpty == true ? title! : (merchant?.trim().isNotEmpty == true ? merchant!.trim() : 'Movimiento'),
      category: category?.isNotEmpty == true ? category : null,
    );
  }

  /// Suggests the best category name for a transaction title.
  Future<String?> suggestCategory(String title, {required List<String> categories}) async {
    if (categories.isEmpty) return null;
    final input = await client.extractStructured(
      system: 'Clasificas movimientos de gasto en una de las categorías dadas. Responde con la más adecuada.',
      userText: 'Concepto: "$title".\nCategorías disponibles: ${categories.join(", ")}.',
      toolName: 'clasificar',
      toolDescription: 'Elige la categoría más adecuada para el concepto.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'enum': categories,
          },
          'confidence': {'type': 'number'},
        },
        'required': ['category'],
      },
      maxTokens: 256,
    );
    return input['category'] as String?;
  }

  /// Parses a receipt photo into a draft transaction (vision).
  Future<ParsedTransaction> parseReceipt(
    AiImage image, {
    required List<String> categories,
  }) async {
    Future<Map<String, dynamic>> extract(LlmClient c) => c.extractStructured(
          system:
              'Extraes los datos de un ticket/recibo de compra. Devuelve el total pagado como amount, '
              'el comercio como title, la fecha si aparece, y la categoría más probable de la lista. '
              'La fecha de hoy es ${_today()}. Categorías: ${categories.join(", ")}',
          userText: 'Extrae el movimiento de este recibo.',
          images: [image],
          toolName: 'extraer_recibo',
          toolDescription: 'Extrae el total, comercio, fecha y categoría de un recibo.',
          inputSchema: _txSchema,
          maxTokens: 1024,
        );

    Map<String, dynamic> input;
    try {
      input = await extract(client);
    } on AiException {
      // El proveedor activo no pudo con la imagen (p. ej. el bridge sin Codex).
      // Fallback: Gemma 4 on-device si hay un modelo con visión descargado.
      final gemma = await _gemmaVisionFallback();
      if (gemma == null) rethrow;
      input = await extract(gemma);
    }
    final parsed = _fromInput(input);
    return ParsedTransaction(
      amount: parsed.amount,
      type: EntryType.expense,
      title: parsed.title,
      categoryName: parsed.categoryName,
      accountName: parsed.accountName,
      currency: parsed.currency,
      date: parsed.date,
      note: parsed.note,
    );
  }

  static String get _statementSystemBase =>
      'Extraes TODOS los movimientos de un estado de cuenta o lista de transacciones '
      'bancarias de México. Devuelve un elemento por cada movimiento (cada fila/renglón). '
      'NO inventes montos ni movimientos: usa solo lo que aparece. Cada cargo, compra, '
      'retiro o pago es type=expense; cada abono, depósito, SPEI recibido o devolución es '
      'type=income. amount SIEMPRE positivo. La fecha de hoy es ${_today()}; convierte '
      'fechas como "15 ENE" o "15/01" al ISO (YYYY-MM-DD) con el año correcto. Moneda por '
      'defecto MXN. No incluyas saldos, totales ni subtotales como movimientos.';

  /// Extracts every movement from a statement given as plain text (a CSV-less
  /// paste, or text extracted from a PDF). Returns one draft per row.
  Future<List<ParsedTransaction>> parseStatementText(
    String text, {
    required List<String> categories,
    required List<String> accounts,
  }) async {
    if (text.trim().isEmpty) return const [];
    final input = await client.extractStructured(
      system: _sys('$_statementSystemBase\n'
          'Elige category y account SOLO de estas listas cuando apliquen.\n'
          'Categorías: ${categories.join(", ")}\n'
          'Cuentas: ${accounts.join(", ")}'),
      userText: text,
      toolName: 'extraer_movimientos',
      toolDescription: 'Extrae la lista completa de movimientos del estado de cuenta.',
      inputSchema: _txListSchema,
      maxTokens: 4096,
    );
    return _listFromInput(input);
  }

  /// Extracts every movement visible in the given statement page images (one
  /// rasterized PDF page or a photo). Falls back to on-device Gemma vision when
  /// the active provider can't handle images, mirroring [parseReceipt].
  Future<List<ParsedTransaction>> parseStatementImages(
    List<AiImage> images, {
    required List<String> categories,
    required List<String> accounts,
  }) async {
    if (images.isEmpty) return const [];
    Future<Map<String, dynamic>> extract(LlmClient c) => c.extractStructured(
          system: _sys('$_statementSystemBase\n'
              'Lee la(s) imagen(es) de un estado de cuenta y extrae cada movimiento. '
              'Elige category y account SOLO de estas listas cuando apliquen.\n'
              'Categorías: ${categories.join(", ")}\n'
              'Cuentas: ${accounts.join(", ")}'),
          userText: 'Extrae todos los movimientos visibles en estas imágenes.',
          images: images,
          toolName: 'extraer_movimientos',
          toolDescription: 'Extrae la lista completa de movimientos visibles.',
          inputSchema: _txListSchema,
          maxTokens: 4096,
        );

    Map<String, dynamic> input;
    try {
      input = await extract(client);
    } on AiException {
      final gemma = await _gemmaVisionFallback();
      if (gemma == null) rethrow;
      input = await extract(gemma);
    }
    return _listFromInput(input);
  }

  /// On-device Gemma client for a downloaded vision-capable model (Gemma 4),
  /// or null if none is installed — used as the receipt fallback when the
  /// active provider can't do images (e.g. the bridge without a Codex token).
  Future<OnDeviceGemmaClient?> _gemmaVisionFallback() async {
    if (client is OnDeviceGemmaClient) return null; // ya es on-device
    try {
      final installed = await OnDeviceGemma.installed();
      for (final m in kOnDeviceModels) {
        if (m.supportsVision && installed.contains(m.id)) {
          return OnDeviceGemmaClient(modelId: m.id);
        }
      }
    } catch (_) {/* sin Gemma instalado → sin fallback */}
    return null;
  }

  /// Generates short, actionable spending insights from a textual summary.
  Future<List<String>> generateInsights(String summary) async {
    final input = await client.extractStructured(
      system: _sys(
          'Eres un coach financiero para usuarios en México. A partir del resumen de gastos, das de 2 a 4 '
          'observaciones breves, concretas y accionables en español, cada una de una frase. Sé directo y útil, '
          'sin relleno. Usa cifras del resumen cuando ayuden.'),
      userText: summary,
      toolName: 'dar_observaciones',
      toolDescription: 'Devuelve una lista de observaciones financieras breves.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'insights': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['insights'],
      },
      maxTokens: 700,
    );
    final list = (input['insights'] as List?) ?? const [];
    return list.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
  }
}
