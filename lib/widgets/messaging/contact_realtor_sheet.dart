import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../services/messaging_service.dart';
import 'message_templates_sheet.dart';

/// Quick compose before opening the full thread (iOS `ContactRealtorView`).
class ContactRealtorSheet extends StatefulWidget {
  const ContactRealtorSheet({
    super.key,
    required this.property,
    this.initialDraft,
  });

  final PropertyModel property;
  /// Prefills the composer — iOS quick-inquiry templates.
  final String? initialDraft;

  @override
  State<ContactRealtorSheet> createState() => _ContactRealtorSheetState();
}

class _ContactRealtorSheetState extends State<ContactRealtorSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  PropertyModel get property => widget.property;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDraft?.trim();
    if (d != null && d.isNotEmpty) {
      _controller.text = d;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.user == null) return;

    setState(() => _sending = true);
    try {
      final repo = context.read<PropertyRepository>();
      final uid = auth.user!.uid;
      final threadId = await repo.ensureConversationForProperty(
        currentUserId: uid,
        property: property,
      );
      await MessagingService.sendTextMessage(
        db: FirebaseFirestore.instance,
        threadId: threadId,
        senderId: uid,
        text: text,
      );
      if (!mounted) return;
      // go() replaces the entire navigation stack back to the shell, so both
      // the sheet AND the NewMessageScreen (if open) are dismissed correctly.
      context.go('/messages/thread/$threadId');
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = switch (e.message) {
        'no_host' => 'This listing has no linked host account yet.',
        'self_message' => 'This is your listing.',
        _ => e.message,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _applyTemplate(String content) {
    final cur = _controller.text;
    if (cur.trim().isEmpty) {
      _controller.text = content;
    } else {
      _controller.text = '$cur\n\n$content';
    }
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final price = NumberFormat.simpleCurrency(name: property.currencyCode)
        .format(property.price);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Contact host',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: property.heroImageUrl != null &&
                          property.heroImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: property.heroImageUrl!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          imageBuilder: (ctx, provider) => Semantics(
                            label: 'Property thumbnail',
                            child: Image(image: provider, fit: BoxFit.cover),
                          ),
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: AppColors.surfaceVariant,
                          child: const Icon(Icons.home_work_outlined),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        price,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (property.locationLine.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          property.locationLine,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Write your message…',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _sending
                      ? null
                      : () => showMessageTemplatesSheet(
                            context,
                            onSelected: _applyTemplate,
                          ),
                  icon: const Icon(Icons.article_outlined, size: 20),
                  label: const Text('Templates'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _sending ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
