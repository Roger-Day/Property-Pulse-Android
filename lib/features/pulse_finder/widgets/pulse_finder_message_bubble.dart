import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../models/pulse_finder_message.dart';

/// Pulse Finder (Phase 3) — a single chat bubble.
///
/// Renders a light markdown subset (`**bold**` spans and `-`/`•` bullet
/// lines) without pulling in a markdown package — AI replies here are short
/// conversational text, not rich documents, so a small hand-rolled parser
/// covers what actually shows up without adding a dependency.
class PulseFinderMessageBubble extends StatelessWidget {
  const PulseFinderMessageBubble({super.key, required this.message});

  final PulseFinderMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == PulseFinderRole.user;
    final theme = Theme.of(context);
    final bubbleColor = isUser
        ? AppColors.primary
        : (message.isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest);
    final textColor = isUser ? Colors.white : theme.colorScheme.onSurface;

    return Semantics(
      label: '${isUser ? 'You' : 'Pulse Finder'} said',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseFinderMarkdownText(
                text: message.text,
                style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimestamp(message.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: textColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTimestamp(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _PulseFinderMarkdownText extends StatelessWidget {
  const _PulseFinderMarkdownText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        final trimmed = line.trimLeft();
        final isBullet = trimmed.startsWith('- ') || trimmed.startsWith('• ');
        final content = isBullet ? trimmed.substring(2) : line;
        final richText = Text.rich(_parseBold(content, style));
        if (!isBullet) return Padding(padding: const EdgeInsets.only(top: 1), child: richText);
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: style),
              Expanded(child: richText),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Splits on `**bold**` spans, everything else rendered plain.
  TextSpan _parseBold(String line, TextStyle? baseStyle) {
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    final spans = <TextSpan>[];
    var last = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(text: line.substring(last, match.start), style: baseStyle));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: baseStyle?.copyWith(fontWeight: FontWeight.w700),
      ));
      last = match.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(text: line.substring(last), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }
}
