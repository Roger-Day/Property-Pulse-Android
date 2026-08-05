import 'package:flutter/material.dart';

/// Pulse Finder (Phase 3) — refinement suggestion chips shown under a
/// result set. Tapping one is just a shortcut for typing the same text —
/// it goes through the exact same `sendMessage` refinement path as manually
/// typed text (deterministic rule first, existing AI search as fallback).
class PulseFinderQuickReplies extends StatelessWidget {
  const PulseFinderQuickReplies({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  static const List<String> suggestions = [
    'Show cheaper options',
    'Only properties with pools',
    'Show newer homes',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: suggestions.map((s) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(s),
              onPressed: () => onSelected(s),
            ),
          );
        }).toList(),
      ),
    );
  }
}
