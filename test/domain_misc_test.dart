import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/util/ids.dart';
import 'package:nexo/features/accounts/domain/account.dart';
import 'package:nexo/features/categories/domain/category.dart';

void main() {
  group('newId', () {
    test('generates unique ids', () {
      final ids = {for (var i = 0; i < 2000; i++) newId('tx')};
      expect(ids.length, 2000);
    });

    test('applies the prefix', () {
      expect(newId('acc').startsWith('acc_'), isTrue);
      expect(newId().contains('_'), isFalse);
    });
  });

  group('AccountTypeX.fromKey', () {
    test('round-trips known keys', () {
      for (final t in AccountType.values) {
        expect(AccountTypeX.fromKey(t.name), t);
      }
    });
    test('falls back to other for unknown', () {
      expect(AccountTypeX.fromKey('nope'), AccountType.other);
      expect(AccountTypeX.fromKey(null), AccountType.other);
    });
  });

  group('CategoryTypeX.fromKey', () {
    test('round-trips known keys', () {
      for (final t in CategoryType.values) {
        expect(CategoryTypeX.fromKey(t.name), t);
      }
    });
    test('falls back to expense for unknown', () {
      expect(CategoryTypeX.fromKey('nope'), CategoryType.expense);
    });
  });

  test('Category.copyWith can clear the parent', () {
    final c = Category(id: 'c', name: 'Sub', color: 0, parentId: 'p');
    expect(c.isSubcategory, isTrue);
    expect(c.copyWith(clearParent: true).isSubcategory, isFalse);
  });
}
