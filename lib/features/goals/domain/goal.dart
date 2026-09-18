import 'package:flutter/material.dart';

class Goal {
  Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currentAmount = 0,
    required this.color,
    this.emoji = '🎯',
    this.deadline,
    required this.createdAt,
    this.archived = false,
  });

  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final int color;
  final String emoji;
  final DateTime? deadline;
  final DateTime createdAt;
  final bool archived;

  Color get colorValue => Color(color);
  double get remaining => (targetAmount - currentAmount).clamp(0, double.infinity);
  double get ratio => targetAmount <= 0 ? 0 : (currentAmount / targetAmount).clamp(0, 1);
  bool get isComplete => currentAmount >= targetAmount && targetAmount > 0;

  int? get daysLeft {
    if (deadline == null) return null;
    return deadline!.difference(DateTime.now()).inDays;
  }

  /// Suggested monthly contribution to hit the goal by its deadline.
  double? get suggestedMonthly {
    final d = daysLeft;
    if (d == null || d <= 0) return null;
    final months = (d / 30).ceil();
    return months <= 0 ? null : remaining / months;
  }

  Goal copyWith({
    String? name,
    double? targetAmount,
    double? currentAmount,
    int? color,
    String? emoji,
    DateTime? deadline,
    bool clearDeadline = false,
    bool? archived,
  }) {
    return Goal(
      id: id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      color: color ?? this.color,
      emoji: emoji ?? this.emoji,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      createdAt: createdAt,
      archived: archived ?? this.archived,
    );
  }
}
