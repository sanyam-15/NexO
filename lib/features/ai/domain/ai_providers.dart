import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/util/ids.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../categories/domain/categories_provider.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import 'ai_mode.dart';
import 'ai_services.dart';

final aiServicesProvider = Provider<AiServices?>((ref) {
  final client = ref.watch(llmClientProvider);
  if (client == null) return null;
  return AiServices(client, persona: ref.watch(aiPersonaProvider));
});

/// Lower-cases and strips Spanish diacritics so accent-dropped model output
/// (e.g. 'educacion') still matches accented catalog names (e.g. 'Educación').
String _foldName(String s) {
  const map = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  final lower = s.toLowerCase().trim();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString();
}

/// Matches category/account NAMES against the user's catalog
/// (case- and accent-insensitive). Returns the matched objects, or null when
/// no match. Shared by [entryFromParsed] and the documents extraction pipeline.
({Category? category, Account? account}) resolveCatalog(
  String? categoryName,
  String? accountName, {
  required List<Category> categories,
  required List<Account> accounts,
}) {
  Category? cat;
  if (categoryName != null) {
    final target = _foldName(categoryName);
    for (final c in categories) {
      if (_foldName(c.name) == target) {
        cat = c;
        break;
      }
    }
  }
  Account? acc;
  if (accountName != null) {
    final target = _foldName(accountName);
    for (final a in accounts) {
      if (_foldName(a.name) == target) {
        acc = a;
        break;
      }
    }
  }
  return (category: cat, account: acc);
}

/// Resolves a parsed AI draft into a persistable [FinanceEntry], matching
/// category/account names against the user's catalog (case-insensitive) and
/// stamping the currency conversion rate at entry time.
FinanceEntry entryFromParsed(
  ParsedTransaction p, {
  required List<Category> categories,
  required List<Account> accounts,
}) {
  final resolved = resolveCatalog(
    p.categoryName,
    p.accountName,
    categories: categories,
    accounts: accounts,
  );
  final cat = resolved.category;
  final acc = resolved.account;

  return FinanceEntry(
    id: newId('tx'),
    title: p.title,
    amount: p.amount,
    category: cat?.name ?? p.categoryName ?? 'Sin categoría',
    categoryId: cat?.id,
    date: p.date ?? DateTime.now(),
    type: p.type,
    account: acc?.name ?? p.accountName ?? 'Efectivo',
    accountId: acc?.id,
    currency: p.currency,
    note: p.note,
    exchangeRate: effectiveMxnRate(p.currency),
    createdAt: DateTime.now(),
  );
}

/// Convenience aggregate of the catalogs the AI flows need.
final aiCatalogProvider = Provider((ref) {
  return (
    categories: ref.watch(activeCategoriesProvider),
    accounts: ref.watch(activeAccountsProvider),
  );
});
