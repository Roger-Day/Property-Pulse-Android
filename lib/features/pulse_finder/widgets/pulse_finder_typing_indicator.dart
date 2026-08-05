import 'package:flutter/material.dart';

/// Pulse Finder (Phase 3) — the "assistant is composing a reply" indicator,
/// shown in the message list while `PulseFinderConversationController.
/// isWaitingForReply` is true.
class PulseFinderTypingIndicator extends StatefulWidget {
  const PulseFinderTypingIndicator({super.key});

  @override
  State<PulseFinderTypingIndicator> createState() => _PulseFinderTypingIndicatorState();
}

class _PulseFinderTypingIndicatorState extends State<PulseFinderTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Pulse Finder is typing',
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_controller.value - i * 0.2) % 1.0;
                  final opacity = (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2)).clamp(0.3, 1.0);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: opacity,
                      child: CircleAvatar(radius: 4, backgroundColor: color),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ),
    );
  }
}
