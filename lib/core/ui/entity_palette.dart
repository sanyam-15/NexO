import 'package:flutter/material.dart';

/// Shared color + emoji palette for user-customizable entities
/// (accounts, categories, budgets, goals).
class EntityPalette {
  EntityPalette._();

  static const colors = <int>[
    0xFFEF5350, // red
    0xFFEC407A, // pink
    0xFFAB47BC, // purple
    0xFF7E57C2, // deep purple
    0xFF5C6BC0, // indigo
    0xFF42A5F5, // blue
    0xFF29B6F6, // light blue
    0xFF26C6DA, // cyan
    0xFF26A69A, // teal
    0xFF66BB6A, // green
    0xFF9CCC65, // light green
    0xFFD4E157, // lime
    0xFFFFCA28, // amber
    0xFFFFA726, // orange
    0xFFFF7043, // deep orange
    0xFF8D6E63, // brown
    0xFF78909C, // blue grey
  ];

  static const accountEmojis = <String>[
    '💵', '💳', '🪙', '🏦', '💰', '📈', '🐷', '💼', '🪪', '🤑',
  ];

  static const categoryEmojis = <String>[
    '🍔', '🍕', '☕', '🛒', '🚗', '⛽', '🚌', '🏠', '💡', '📱',
    '🎮', '🎬', '🎵', '👕', '💊', '🏥', '🎓', '✈️', '🎁', '🐶',
    '💪', '🧾', '💸', '💼', '🍺', '🧒', '🛠️', '🌱', '📚', '🏷️',
  ];

  static const goalEmojis = <String>[
    '🎯', '🏖️', '🚗', '🏡', '💍', '🎓', '💻', '📱', '✈️', '🛡️',
  ];

  static int colorFor(int seed) => colors[seed.abs() % colors.length];
}

/// A compact horizontal swatch picker.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({super.key, required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EntityPalette.colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = EntityPalette.colors[i];
          final isSel = c == selected;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: isSel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
            ),
          );
        },
      ),
    );
  }
}

/// A compact horizontal emoji picker.
class EmojiPicker extends StatelessWidget {
  const EmojiPicker({super.key, required this.emojis, required this.selected, required this.onSelect});

  final List<String> emojis;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: emojis.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = emojis[i];
          final isSel = e == selected;
          return GestureDetector(
            onTap: () => onSelect(e),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSel
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(e, style: const TextStyle(fontSize: 22)),
            ),
          );
        },
      ),
    );
  }
}
