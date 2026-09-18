import 'package:flutter/material.dart';

enum CategoryType { expense, income, both }

extension CategoryTypeX on CategoryType {
  String get label {
    switch (this) {
      case CategoryType.expense:
        return 'Gasto';
      case CategoryType.income:
        return 'Ingreso';
      case CategoryType.both:
        return 'Ambos';
    }
  }

  static CategoryType fromKey(String? key) {
    return CategoryType.values.firstWhere(
      (t) => t.name == key,
      orElse: () => CategoryType.expense,
    );
  }
}

class Category {
  Category({
    required this.id,
    required this.name,
    this.emoji = '🏷️',
    required this.color,
    this.type = CategoryType.expense,
    this.parentId,
    this.sortOrder = 0,
    this.archived = false,
  });

  final String id;
  final String name;
  final String emoji;
  final int color;
  final CategoryType type;

  /// When set, this is a subcategory of [parentId] (Cashew parity).
  final String? parentId;
  final int sortOrder;
  final bool archived;

  bool get isSubcategory => parentId != null;
  Color get colorValue => Color(color);

  Category copyWith({
    String? name,
    String? emoji,
    int? color,
    CategoryType? type,
    String? parentId,
    bool clearParent = false,
    int? sortOrder,
    bool? archived,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      color: color ?? this.color,
      type: type ?? this.type,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }
}
