import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/capture/domain/merchant_memory.dart';

void main() {
  group('normalizeMerchantKey', () {
    test('lowercases, strips accents, collapses spaces', () {
      expect(normalizeMerchantKey('OXXO'), 'oxxo');
      expect(normalizeMerchantKey('Café de la Esquina'), 'cafe de la esquina');
      expect(normalizeMerchantKey('  Uber   Eats  '), 'uber eats');
    });

    test('drops ONLY a trailing store/terminal reference run', () {
      expect(normalizeMerchantKey('OXXO 1234'), 'oxxo');
      expect(normalizeMerchantKey('Walmart #0099'), 'walmart');
    });

    test('keeps interior and leading brand digits (no cross-merchant bleed)', () {
      expect(normalizeMerchantKey('Tienda 24 Horas'), 'tienda 24 horas');
      expect(normalizeMerchantKey('99 Cents'), '99 cents');
      expect(normalizeMerchantKey('7 Eleven'), '7 eleven');
    });

    test('returns null for generic finance words (not merchants)', () {
      expect(normalizeMerchantKey('Pago'), isNull);
      expect(normalizeMerchantKey('compra'), isNull);
      expect(normalizeMerchantKey('Transferencia'), isNull);
      expect(normalizeMerchantKey('Sin categoría'), isNull);
    });

    test('returns null for too-short or empty input', () {
      expect(normalizeMerchantKey(null), isNull);
      expect(normalizeMerchantKey(''), isNull);
      expect(normalizeMerchantKey('ab'), isNull);
      expect(normalizeMerchantKey('\$\$\$'), isNull);
      expect(normalizeMerchantKey('12'), isNull);
    });

    test('keeps a real multi-word merchant', () {
      expect(normalizeMerchantKey('Rappi'), 'rappi');
      expect(normalizeMerchantKey('Mercado Libre'), 'mercado libre');
    });
  });
}
