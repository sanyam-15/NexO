import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/transactions/domain/capture_layout.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

void main() {
  group('CaptureLayoutConfig.defaults', () {
    test('reproduces the classic Quick Add (type/amount/title/category/account/currency visible)', () {
      final d = CaptureLayoutConfig.defaults;
      expect(d.quickAddMode, QuickAddMode.manual);
      expect(d.visibleQuickFields, [
        CaptureField.type,
        CaptureField.amount,
        CaptureField.title,
        CaptureField.category,
        CaptureField.account,
        CaptureField.currency,
      ]);
      expect(d.isVisible(CaptureField.note), isFalse);
      expect(d.isVisible(CaptureField.date), isFalse);
    });
  });

  group('CaptureLayoutConfig JSON', () {
    test('round-trips', () {
      final cfg = CaptureLayoutConfig.defaults.copyWith(
        quickAddMode: QuickAddMode.hybrid,
        defaultType: EntryType.income,
        defaultCategoryName: 'Ingresos',
        defaultCurrency: 'USD',
        documentEngine: DocumentEngine.onDevice,
      );
      final back = CaptureLayoutConfig.fromJson(cfg.toJson());
      expect(back.quickAddMode, QuickAddMode.hybrid);
      expect(back.defaultType, EntryType.income);
      expect(back.defaultCategoryName, 'Ingresos');
      expect(back.defaultCurrency, 'USD');
      expect(back.documentEngine, DocumentEngine.onDevice);
      expect(back.visibleQuickFields, cfg.visibleQuickFields);
    });

    test('round-trips the remote OCR endpoint settings', () {
      final cfg = CaptureLayoutConfig.defaults.copyWith(
        documentOcr: DocumentOcr.remoteOcr,
        ocrEndpoint: 'https://api.mistral.ai/v1',
        ocrApiKey: 'sk-test',
        ocrModel: 'mistral-ocr-latest',
      );
      final back = CaptureLayoutConfig.fromJson(cfg.toJson());
      expect(back.documentOcr, DocumentOcr.remoteOcr);
      expect(back.ocrEndpoint, 'https://api.mistral.ai/v1');
      expect(back.ocrApiKey, 'sk-test');
      expect(back.ocrModel, 'mistral-ocr-latest');
      expect(back.remoteOcrConfigured, isTrue);
    });

    test('defaults: documentOcr onDeviceOcr, ocrModel mistral-ocr-latest, not configured', () {
      final d = CaptureLayoutConfig.defaults;
      expect(d.documentOcr, DocumentOcr.onDeviceOcr);
      expect(d.ocrModel, 'mistral-ocr-latest');
      expect(d.remoteOcrConfigured, isFalse);
    });

    test('normalizes a partial saved field list by appending missing fields (hidden)', () {
      final json = {
        'quickAddMode': 'manual',
        'quickAddFields': [
          {'field': 'amount', 'visible': true},
          {'field': 'title', 'visible': true},
        ],
      };
      final cfg = CaptureLayoutConfig.fromJson(json);
      // All CaptureField values must be present after normalization.
      expect(cfg.quickAddFields.length, CaptureField.values.length);
      // The two saved ones keep order + visibility at the front.
      expect(cfg.quickAddFields[0].field, CaptureField.amount);
      expect(cfg.quickAddFields[1].field, CaptureField.title);
      // A field not in the saved list is appended hidden.
      expect(cfg.isVisible(CaptureField.currency), isFalse);
    });

    test('falls back to defaults on an empty/garbage field list', () {
      final cfg = CaptureLayoutConfig.fromJson({'quickAddFields': 'nope'});
      expect(cfg.visibleQuickFields, CaptureLayoutConfig.defaults.visibleQuickFields);
    });
  });

  group('CaptureTemplate JSON', () {
    test('round-trips with its config', () {
      final t = CaptureTemplate(
        id: 't1',
        name: 'Detallado',
        config: CaptureLayoutConfig.defaults.copyWith(quickAddMode: QuickAddMode.ai),
      );
      final back = CaptureTemplate.fromJson(t.toJson());
      expect(back.id, 't1');
      expect(back.name, 'Detallado');
      expect(back.config.quickAddMode, QuickAddMode.ai);
    });
  });
}
