import 'package:intl/intl.dart';

const supportedCurrencies = ['MXN', 'USD', 'EUR'];

/// Static fallback rates (MXN per 1 unit). Used until live rates are fetched.
const mxnPerCurrency = {
  'MXN': 1.0,
  'USD': 17.0,
  'EUR': 18.5,
};

/// Live MXN-per-unit rates, populated by the FX service when available.
/// Mutable global so the pure conversion helpers can prefer fresh rates.
final Map<String, double> liveMxnPerCurrency = <String, double>{};

/// Best available rate for [currency]: live first, then the static fallback.
double effectiveMxnRate(String currency) {
  if (currency == 'MXN') return 1.0;
  return liveMxnPerCurrency[currency] ?? mxnPerCurrency[currency] ?? 1.0;
}

/// Rounds a monetary value to 2 decimals (banker-free, half-up). Applied at
/// write time so stored amounts don't accumulate binary floating-point drift.
double roundMoney(double value) => (value * 100).round() / 100;

const _symbols = {
  'MXN': r'$',
  'USD': r'US$',
  'EUR': '€',
};

double toMxn(double amount, String currency) {
  return amount * effectiveMxnRate(currency);
}

/// Convert using a rate captured at entry time when available, so historical
/// totals stay stable as live rates drift. Falls back to the static table.
double toMxnWithRate(double amount, String currency, double? storedRate) {
  if (storedRate != null && storedRate > 0) return amount * storedRate;
  return toMxn(amount, currency);
}

String currencySymbol(String currency) => _symbols[currency] ?? '\$';

/// Compact money formatting used across the new feature screens.
String formatMoney(num amount, {String currency = 'MXN', bool withSymbol = true, int decimals = 2}) {
  final f = NumberFormat.currency(
    locale: 'es_MX',
    symbol: withSymbol ? currencySymbol(currency) : '',
    decimalDigits: decimals,
  );
  return f.format(amount).trim();
}

/// Whole-peso variant for dense UI (e.g. budget bars).
String formatMoneyShort(num amount, {String currency = 'MXN'}) {
  return formatMoney(amount, currency: currency, decimals: 0);
}
