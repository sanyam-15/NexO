import '../../transactions/domain/transaction.dart';
import 'entity_registry.dart';

/// Deterministic result of parsing a bank/fintech notification. The money and
/// direction are NEVER produced by a model — only by these regex rules — so a
/// captured movement can never be hallucinated. The merchant→category step is
/// the only part left to the AI layer.
class ParsedCapture {
  const ParsedCapture({
    required this.entity,
    this.amount,
    this.direction = EntryType.expense,
    this.directionExplicit = false,
    this.cardLast4,
    this.merchant,
    required this.confidence,
  });

  final CaptureEntity entity;

  /// Positive amount, or null when no money token could be parsed.
  final double? amount;

  /// Inferred sign. Defaults to expense (most bank alerts are charges) but
  /// [directionExplicit] tells whether a keyword actually decided it.
  final EntryType direction;
  final bool directionExplicit;

  final String? cardLast4;

  /// Best-effort merchant snippet pulled deterministically (e.g. text after
  /// "en "); the AI refines this into title + category.
  final String? merchant;

  /// 0–1 heuristic. High enough → auto-write candidate; low → review queue.
  final double confidence;

  bool get hasAmount => amount != null && amount! > 0;
}

/// Pure, dependency-free parser for Mexican bank/fintech notification text.
class CaptureParser {
  const CaptureParser._();

  // ── Direction keywords (accent-insensitive, matched on a normalized string) ─
  // Strong income signals.
  static const _incomeWords = [
    'deposito',
    'depositaron',
    'te depositaron',
    'abono',
    'recibiste',
    'recibio',
    'recibido',
    'recibida',
    'transferencia recibida',
    'spei recibido',
    'pago recibido',
    'devolucion',
    'reembolso',
    'te enviaron',
    'nomina',
    'ingreso',
  ];

  // Strong, unambiguous expense signals.
  static const _expenseWords = [
    'compra',
    'cargo',
    'pagaste',
    'gastaste',
    'retiro',
    'retiraste',
    'disposicion',
    'dispusiste',
    'debito',
    'enviaste',
    'transferencia enviada',
    'spei enviado',
    'domiciliacion',
  ];

  // Ambiguous: "pago" alone usually means a bill you paid, but "pago recibido"
  // is income — so it is only used as a weak fallback after the strong lists.
  static const _weakExpenseWords = ['pago'];

  /// Parses a notification into a [ParsedCapture], or null if [package] is not a
  /// known/allowed finance entity.
  static ParsedCapture? parse({
    required String package,
    String? title,
    String? text,
  }) {
    final entity = entityForPackage(package);
    if (entity == null) return null;

    final raw = [title, text].where((s) => s != null && s.trim().isNotEmpty).join('. ');
    final norm = _normalize(raw);

    final amount = _parseAmount(raw);
    final (direction, explicit) = _parseDirection(norm);
    final last4 = _parseCardLast4(raw);
    final merchant = _parseMerchant(raw);

    var confidence = amount != null ? 0.45 : 0.1;
    if (explicit) confidence += 0.3;
    if (last4 != null) confidence += 0.1;
    if (merchant != null) confidence += 0.1;
    if (confidence > 1) confidence = 1;

    return ParsedCapture(
      entity: entity,
      amount: amount,
      direction: direction,
      directionExplicit: explicit,
      cardLast4: last4,
      merchant: merchant,
      confidence: confidence,
    );
  }

  /// Lowercases and strips Spanish accents so keyword matching is robust to the
  /// inconsistent accenting in real notifications.
  static String _normalize(String s) {
    var out = s.toLowerCase();
    const map = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  static (EntryType, bool) _parseDirection(String norm) {
    final inc = _firstHit(norm, _incomeWords);
    final exp = _firstHit(norm, _expenseWords);
    // Both strong signals present → the earlier one wins (e.g. "Compra ... abono").
    if (inc != null && exp != null) {
      return inc <= exp ? (EntryType.income, true) : (EntryType.expense, true);
    }
    if (inc != null) return (EntryType.income, true); // income, no strong expense
    if (exp != null) return (EntryType.expense, true); // strong expense
    // Neither strong: a bare "pago" means a bill paid (expense).
    if (_firstHit(norm, _weakExpenseWords) != null) return (EntryType.expense, true);
    return (EntryType.expense, false); // default, not explicit
  }

  static int? _firstHit(String haystack, List<String> needles) {
    int? best;
    for (final n in needles) {
      final i = haystack.indexOf(n);
      if (i >= 0 && (best == null || i < best)) best = i;
    }
    return best;
  }

  // Symbol-anchored money: "$1,234.56", "MXN 1234", "MX$ 99.00". The group is
  // anchored to END on a digit so a trailing sentence period can't be captured.
  static final _symbolMoney = RegExp(
    r'(?:\$|mxn|mx\$)\s*([0-9][0-9.,]*[0-9]|[0-9])',
    caseSensitive: false,
  );

  // Currency-suffixed money: "450 pesos", "320 MXN", "1,200 MN".
  static final _suffixMoney = RegExp(
    r'([0-9][0-9.,]*[0-9]|[0-9])\s*(?:pesos|mxn|mn)\b',
    caseSensitive: false,
  );

  // Money-looking bare numbers: thousands-grouped or 2-decimal (last resort).
  static final _bareMoney = RegExp(
    r'(?<![0-9.,])(\d{1,3}(?:,\d{3})+(?:\.\d{2})?|\d+\.\d{2})(?![0-9])',
  );

  /// Extracts the transaction amount, preferring symbol/currency-anchored tokens
  /// and skipping anything that reads as an account balance. Returns null if no
  /// usable amount is found.
  static double? _parseAmount(String raw) {
    final lower = raw.toLowerCase();
    final anchored = <(int, String)>[];
    for (final m in _symbolMoney.allMatches(raw)) {
      anchored.add((m.start, m.group(1)!));
    }
    for (final m in _suffixMoney.allMatches(raw)) {
      anchored.add((m.start, m.group(1)!));
    }
    final pool = anchored.isNotEmpty
        ? anchored
        : [for (final m in _bareMoney.allMatches(raw)) (m.start, m.group(1)!)];
    if (pool.isEmpty) return null;

    // Drop amounts that read as an account balance, not the movement itself.
    // A wide window catches "saldo disponible en tu cuenta es de $X".
    bool isBalance(int idx) {
      final from = (idx - 40).clamp(0, lower.length);
      final ctx = lower.substring(from, idx.clamp(0, lower.length));
      return ctx.contains('saldo') || ctx.contains('disponible');
    }

    // If every money token reads as a balance, this is a balance-only alert —
    // return null so it routes to review without inventing a movement amount.
    final nonBalance = pool.where((c) => !isBalance(c.$1)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    for (final c in nonBalance) {
      final v = _normalizeAmount(c.$2);
      if (v != null) return v;
    }
    return null;
  }

  /// Parses a money string, auto-detecting the decimal separator by the position
  /// of the LAST separator (so both "$1,234.56" and the LATAM "$1.234,56" work).
  static double? _normalizeAmount(String s) {
    var t = s.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
    t = t.replaceAll(RegExp(r'[.,]+$'), ''); // strip trailing separators (sentence period)
    if (t.isEmpty) return null;

    final lastDot = t.lastIndexOf('.');
    final lastComma = t.lastIndexOf(',');

    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        // Comma is the decimal (e.g. "1.234,56" → 1234.56).
        t = t.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // Dot is the decimal (e.g. "1,234.56" → 1234.56).
        t = t.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      final parts = t.split(',');
      if (parts.length == 2 && parts.last.length == 2) {
        t = '${parts.first}.${parts.last}'; // decimal comma "99,90"
      } else {
        t = t.replaceAll(',', ''); // thousands "1,500"
      }
    } else if (lastDot >= 0) {
      final parts = t.split('.');
      if (parts.length > 2) {
        t = t.replaceAll('.', ''); // multiple dots = thousands grouping
      } else if (parts.length == 2 && parts.last.length == 3) {
        t = t.replaceAll('.', ''); // "1.500" with no decimals = thousands → 1500
      }
      // else single dot with 1–2 decimals → keep as the decimal point.
    }

    final v = double.tryParse(t);
    if (v == null || v <= 0) return null;
    return v;
  }

  // "terminación 1234", "**** 1234", "tarjeta ...1234", "que termina en 1234".
  static final _cardLast4 = RegExp(
    r'(?:termina(?:ci[oó]n|da)?\s*(?:en)?|final(?:iza)?\s*(?:en)?|\*{2,}\s*|x{2,}\s*|\.{2,}\s*)\s*(\d{4})\b',
    caseSensitive: false,
  );

  static String? _parseCardLast4(String raw) {
    final m = _cardLast4.firstMatch(raw);
    return m?.group(1);
  }

  // Merchant after "en " up to a separator. Best-effort only.
  static final _merchant = RegExp(
    r'\ben\s+([A-Z0-9][\w&.\- ]{2,30}?)(?:\.|,|\s+por\s|\s+con\s|\s+el\s|$)',
    caseSensitive: false,
  );

  /// Public best-effort merchant extraction from a notification's title+text
  /// (e.g. "OXXO"), used to key the learned merchant→category memory.
  static String? extractMerchant({String? title, String? text}) {
    final raw = [title, text].where((s) => s != null && s.trim().isNotEmpty).join('. ');
    if (raw.isEmpty) return null;
    return _parseMerchant(raw);
  }

  static String? _parseMerchant(String raw) {
    var s = _merchant.firstMatch(raw)?.group(1)?.trim();
    if (s == null || s.isEmpty) return null;
    // Drop a trailing store/terminal reference number ("OXXO 1234" → "OXXO").
    s = s.replaceAll(RegExp(r'\s+\d{2,}$'), '').trim();
    if (s.isEmpty) return null;
    // Avoid catching connector words that follow "en".
    const stop = {'tu', 'su', 'la', 'el', 'una', 'un', 'linea', 'proceso'};
    if (stop.contains(s.toLowerCase())) return null;
    return s;
  }
}
