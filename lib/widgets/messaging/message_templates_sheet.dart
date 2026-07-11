import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/message_template.dart';

/// Bottom sheet listing iOS-parity templates; returns selected body text via [onSelected].
Future<void> showMessageTemplatesSheet(
  BuildContext context, {
  required void Function(String text) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Message templates',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a template to insert it into your message.',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.45,
                child: ListView.separated(
                  itemCount: MessageTemplate.templates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = MessageTemplate.templates[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        t.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        onSelected(t.content);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
