import 'package:flutter/material.dart';

class Label {
  Label({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final int color;

  Color get colorValue => Color(color);

  Label copyWith({String? name, int? color}) =>
      Label(id: id, name: name ?? this.name, color: color ?? this.color);
}
