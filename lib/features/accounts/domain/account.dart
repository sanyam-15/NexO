import 'package:flutter/material.dart';

enum AccountType { cash, debit, credit, savings, investment, other }

extension AccountTypeX on AccountType {
  String get label {
    switch (this) {
      case AccountType.cash:
        return 'Efectivo';
      case AccountType.debit:
        return 'Débito';
      case AccountType.credit:
        return 'Crédito';
      case AccountType.savings:
        return 'Ahorros';
      case AccountType.investment:
        return 'Inversión';
      case AccountType.other:
        return 'Otra';
    }
  }

  IconData get icon {
    switch (this) {
      case AccountType.cash:
        return Icons.payments_outlined;
      case AccountType.debit:
        return Icons.account_balance_wallet_outlined;
      case AccountType.credit:
        return Icons.credit_card_outlined;
      case AccountType.savings:
        return Icons.savings_outlined;
      case AccountType.investment:
        return Icons.trending_up_rounded;
      case AccountType.other:
        return Icons.account_balance_outlined;
    }
  }

  String get storageKey => name;

  static AccountType fromKey(String? key) {
    return AccountType.values.firstWhere(
      (t) => t.name == key,
      orElse: () => AccountType.other,
    );
  }
}

class Account {
  Account({
    required this.id,
    required this.name,
    required this.type,
    this.currency = 'MXN',
    required this.color,
    this.icon = '💳',
    this.startingBalance = 0,
    this.includeInNetWorth = true,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currency;

  /// ARGB color value.
  final int color;

  /// Emoji glyph shown as the account avatar.
  final String icon;
  final double startingBalance;
  final bool includeInNetWorth;
  final bool archived;
  final int sortOrder;
  final DateTime createdAt;

  Color get colorValue => Color(color);

  Account copyWith({
    String? name,
    AccountType? type,
    String? currency,
    int? color,
    String? icon,
    double? startingBalance,
    bool? includeInNetWorth,
    bool? archived,
    int? sortOrder,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      startingBalance: startingBalance ?? this.startingBalance,
      includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
      archived: archived ?? this.archived,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }
}
