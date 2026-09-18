import 'dart:math';

final _rnd = Random();

/// Generates a sortable-ish unique id: millisecond timestamp + random suffix.
/// Good enough for local primary keys without pulling in a uuid dependency.
String newId([String prefix = '']) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = _rnd.nextInt(1 << 32).toRadixString(36);
  final core = '$ts$rand';
  return prefix.isEmpty ? core : '${prefix}_$core';
}
