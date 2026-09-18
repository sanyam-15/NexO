import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/capture/domain/capture_parser.dart';
import 'package:nexo/features/capture/domain/entity_registry.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

void main() {
  group('entityForPackage', () {
    test('maps known packages to entities', () {
      expect(entityForPackage('com.nu.production')?.name, 'Nu');
      expect(entityForPackage('com.nu.production')?.type, EntityType.sofipo);
      expect(entityForPackage('com.bancomer.mbanking')?.name, 'BBVA');
      expect(entityForPackage('com.bancomer.mbanking')?.type, EntityType.banco);
    });

    test('returns null for unknown and excluded packages', () {
      expect(entityForPackage('com.whatsapp'), isNull);
      expect(entityForPackage(''), isNull);
      // Mercado Libre seller app is excluded even though the brand is in the catalog.
      expect(entityForPackage('com.mercadolibre'), isNull);
      expect(entityForPackage('com.mercadopago.wallet')?.name, 'Mercado Pago');
    });
  });

  group('CaptureParser.parse', () {
    test('returns null for a non-finance package', () {
      expect(CaptureParser.parse(package: 'com.whatsapp', text: 'Hola, \$100'), isNull);
    });

    test('parses an expense with amount, direction and card last 4', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        title: 'Compra aprobada',
        text: 'Compra por \$450.00 en OXXO con tu tarjeta terminación 1234.',
      )!;
      expect(r.entity.name, 'Nu');
      expect(r.amount, 450.0);
      expect(r.direction, EntryType.expense);
      expect(r.directionExplicit, isTrue);
      expect(r.cardLast4, '1234');
      expect(r.confidence, greaterThan(0.6));
    });

    test('parses an income deposit', () {
      final r = CaptureParser.parse(
        package: 'com.bancomer.mbanking',
        text: 'Recibiste un depósito por \$1,200.50 de tu NOMINA.',
      )!;
      expect(r.amount, 1200.5);
      expect(r.direction, EntryType.income);
      expect(r.directionExplicit, isTrue);
    });

    test('thousands-grouped amount parses correctly', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Cargo por \$1,234.56 aprobado.',
      )!;
      expect(r.amount, 1234.56);
      expect(r.direction, EntryType.expense);
    });

    test('ignores the account balance and picks the movement amount', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Compra por \$85.00 en Rappi. Saldo disponible: \$3,450.00',
      )!;
      expect(r.amount, 85.0);
    });

    test('comma-decimal amount is tolerated', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Pago por \$99,90 realizado.',
      )!;
      expect(r.amount, 99.9);
    });

    test('no parseable amount yields null amount and low confidence', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Tu estado de cuenta ya está disponible.',
      )!;
      expect(r.amount, isNull);
      expect(r.hasAmount, isFalse);
      expect(r.confidence, lessThan(0.4));
    });

    test('defaults to expense (not explicit) when no keyword is present', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Movimiento en tu cuenta por \$50.00',
      )!;
      expect(r.direction, EntryType.expense);
      expect(r.directionExplicit, isFalse);
    });

    test('MXN-prefixed amount without a symbol parses', () {
      final r = CaptureParser.parse(
        package: 'mx.klar.app',
        text: 'Cargo de MXN 320.00 en Uber',
      )!;
      expect(r.amount, 320.0);
      expect(r.entity.name, 'Klar');
    });

    // ── Regression: review findings ──────────────────────────────────────
    test('amount ending a sentence (trailing period) still parses', () {
      expect(
        CaptureParser.parse(package: 'com.nu.production', text: 'Compra por \$58.00.')!.amount,
        58.0,
      );
      expect(
        CaptureParser.parse(package: 'com.nu.production', text: 'Cargo de \$1,234.56.')!.amount,
        1234.56,
      );
      expect(
        CaptureParser.parse(package: 'mx.klar.app', text: 'Cargo de MXN 320.00. Gracias')!.amount,
        320.0,
      );
    });

    test('LATAM decimal-comma format (\$1.500,75) parses correctly', () {
      expect(
        CaptureParser.parse(package: 'ar.com.bancar.uala', text: 'Compra por \$1.500,75 en Spotify')!.amount,
        1500.75,
      );
      expect(
        CaptureParser.parse(package: 'com.mercadopago.wallet', text: 'Pago de \$3.000,00 realizado')!.amount,
        3000.0,
      );
    });

    test('"pago recibido" and "pago de nomina" are income, not expense', () {
      expect(
        CaptureParser.parse(package: 'com.nu.production', text: 'Pago recibido por \$500.00 de Juan')!.direction,
        EntryType.income,
      );
      expect(
        CaptureParser.parse(package: 'com.bancomer.mbanking', text: 'Pago de nomina por \$5,000.00')!.direction,
        EntryType.income,
      );
    });

    test('a bare "pago" (a bill) stays an expense', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Pago de servicio CFE por \$320.00',
      )!;
      expect(r.direction, EntryType.expense);
      expect(r.directionExplicit, isTrue);
    });

    test('amount with a currency word suffix and no symbol parses', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Compra por 450 pesos en OXXO',
      )!;
      expect(r.amount, 450.0);
      expect(r.direction, EntryType.expense);
    });

    test('balance-only alert with words before the figure yields no amount', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Saldo disponible en tu cuenta es de \$3,000.00',
      )!;
      expect(r.amount, isNull);
    });

    test('merchant strips a trailing store/terminal reference number', () {
      final r = CaptureParser.parse(
        package: 'com.nu.production',
        text: 'Pago en OXXO 1234 por \$89.50',
      )!;
      expect(r.amount, 89.5);
      expect(r.merchant, 'OXXO');
    });
  });
}
