import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/dispute.dart';
import '../../services/dispute_service.dart';

/// Dispute status, evidence, and messaging thread — mirrors iOS
/// `DisputeDetailView` (evidence grid + threaded messages + admin
/// resolve/assign panel), all backed by the same `disputes` Cloud Functions
/// as [DisputeFlowScreen].
class DisputeDetailScreen extends StatefulWidget {
  const DisputeDetailScreen({
    super.key,
    required this.disputeId,
    this.isAdmin = false,
  });

  final String disputeId;
  final bool isAdmin;

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  final _messageCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  bool _sending = false;
  bool _uploadingEvidence = false;
  bool _internalNote = false;
  String? _actionError;

  static final _dateFmt = DateFormat.yMMMd().add_jm();

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<DisputeService>().sendMessage(
            disputeId: widget.disputeId,
            text: text,
            isInternal: widget.isAdmin && _internalNote,
          );
      _messageCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not send message: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addEvidence() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingEvidence = true);
    try {
      await context.read<DisputeService>().uploadEvidence(
            disputeId: widget.disputeId,
            file: File(picked.path),
            type: EvidenceType.photo,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Evidence upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingEvidence = false);
    }
  }

  Future<void> _assignToMe() async {
    setState(() => _actionError = null);
    try {
      await context.read<DisputeService>().assignDispute(
            disputeId: widget.disputeId,
            adminId: _currentUserId,
          );
    } catch (e) {
      if (mounted) setState(() => _actionError = 'Could not assign: $e');
    }
  }

  Future<void> _openResolveDialog(Dispute dispute) async {
    final result = await showModalBottomSheet<_ResolutionInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ResolveDisputeSheet(dispute: dispute),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<DisputeService>().resolveDispute(
            disputeId: widget.disputeId,
            resolution: result.resolution,
            refundAmountCents: result.refundAmountCents,
            adminNote: result.adminNote,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Dispute resolved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not resolve: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispute')),
      body: StreamBuilder<Dispute>(
        stream: context.read<DisputeService>().watchDispute(widget.disputeId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final dispute = snap.data!;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatusCard(dispute: dispute),
                    const SizedBox(height: 16),
                    _EvidenceSection(
                      evidence: dispute.evidence,
                      uploading: _uploadingEvidence,
                      onAdd: dispute.isResolved ? null : _addEvidence,
                    ),
                    const SizedBox(height: 16),
                    Text('Messages',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    StreamBuilder<List<DisputeMessage>>(
                      stream: context
                          .read<DisputeService>()
                          .watchMessages(widget.disputeId),
                      builder: (context, msgSnap) {
                        final messages = msgSnap.data ?? const [];
                        if (messages.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('No messages yet.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          );
                        }
                        return Column(
                          children: messages
                              .map((m) => _MessageBubble(
                                    message: m,
                                    isMine: m.senderId == _currentUserId,
                                    dateFmt: _dateFmt,
                                  ))
                              .toList(),
                        );
                      },
                    ),
                    if (widget.isAdmin) ...[
                      const SizedBox(height: 24),
                      _AdminActionPanel(
                        dispute: dispute,
                        error: _actionError,
                        onAssignToMe: dispute.assignedAdminId == null
                            ? _assignToMe
                            : null,
                        onResolve: dispute.isResolved
                            ? null
                            : () => _openResolveDialog(dispute),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (!dispute.isResolved) _composer(),
            ],
          );
        },
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isAdmin)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Internal note', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: _internalNote,
                    onChanged: (v) => setState(() => _internalNote = v),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  tooltip: 'Send message',
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.dispute});
  final Dispute dispute;

  Color get _statusColor {
    switch (dispute.status) {
      case DisputeStatus.open:
        return Colors.blue;
      case DisputeStatus.underReview:
      case DisputeStatus.escalated:
        return Colors.orange;
      case DisputeStatus.resolved:
      case DisputeStatus.closed:
        return Colors.green;
      case DisputeStatus.awaitingGuest:
      case DisputeStatus.awaitingHost:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dispute.status.displayTitle,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: _statusColor),
                ),
              ),
              const Spacer(),
              Text('Ref: ${dispute.id.length >= 8 ? dispute.id.substring(0, 8).toUpperCase() : dispute.id.toUpperCase()}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          Text(dispute.description,
              style: Theme.of(context).textTheme.bodyMedium),
          if (dispute.isResolved) ...[
            const Divider(height: 24),
            Text(dispute.resolution!.displayTitle,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (dispute.refundAmountCents != null && dispute.refundAmountCents! > 0)
              Text(
                'Refund: \$${(dispute.refundAmountCents! / 100).toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            if (dispute.resolvedNote != null && dispute.resolvedNote!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(dispute.resolvedNote!,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({
    required this.evidence,
    required this.uploading,
    required this.onAdd,
  });

  final List<EvidenceItem> evidence;
  final bool uploading;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Evidence',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: uploading ? null : onAdd,
              icon: uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        if (evidence.isEmpty)
          const Text('No evidence attached yet.',
              style: TextStyle(color: AppColors.textSecondary))
        else
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: evidence.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final item = evidence[i];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.type == EvidenceType.photo ||
                          item.type == EvidenceType.screenshot
                      ? Image.network(
                          item.url,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fileTile(),
                        )
                      : _fileTile(),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _fileTile() => Container(
        width: 88,
        height: 88,
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.insert_drive_file_outlined),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.dateFmt,
  });

  final DisputeMessage message;
  final bool isMine;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    if (message.isInternalNote) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: Colors.amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Internal note: ${message.text}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.primary.withOpacity(0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
            if (message.timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(dateFmt.format(message.timestamp!),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminActionPanel extends StatelessWidget {
  const _AdminActionPanel({
    required this.dispute,
    required this.error,
    required this.onAssignToMe,
    required this.onResolve,
  });

  final Dispute dispute;
  final String? error;
  final VoidCallback? onAssignToMe;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Admin actions',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            dispute.assignedAdminId == null
                ? 'Unassigned'
                : 'Assigned to ${dispute.assignedAdminId}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (onAssignToMe != null)
                OutlinedButton(
                  onPressed: onAssignToMe,
                  child: const Text('Assign to me'),
                ),
              if (onAssignToMe != null && onResolve != null)
                const SizedBox(width: 8),
              if (onResolve != null)
                FilledButton(
                  onPressed: onResolve,
                  child: const Text('Resolve dispute'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolutionInput {
  const _ResolutionInput(this.resolution, this.refundAmountCents, this.adminNote);
  final DisputeResolution resolution;
  final int? refundAmountCents;
  final String adminNote;
}

class _ResolveDisputeSheet extends StatefulWidget {
  const _ResolveDisputeSheet({required this.dispute});
  final Dispute dispute;

  @override
  State<_ResolveDisputeSheet> createState() => _ResolveDisputeSheetState();
}

class _ResolveDisputeSheetState extends State<_ResolveDisputeSheet> {
  DisputeResolution _resolution = DisputeResolution.fullRefundToGuest;
  final _refundCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _refundCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Resolve Dispute',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<DisputeResolution>(
              initialValue: _resolution,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Resolution',
                border: OutlineInputBorder(),
              ),
              items: DisputeResolution.values
                  .map((r) => DropdownMenuItem(
                      value: r, child: Text(r.displayTitle, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _resolution = v);
              },
            ),
            if (_resolution.requiresRefundAmount) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _refundCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Refund amount (USD)',
                  border: OutlineInputBorder(),
                  prefixText: r'$',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Admin note',
                border: OutlineInputBorder(),
                hintText: 'Reasoning for this decision…',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final dollars = double.tryParse(_refundCtrl.text.trim());
                  final refundCents = _resolution.requiresRefundAmount && dollars != null
                      ? (dollars * 100).round()
                      : null;
                  Navigator.of(context).pop(
                    _ResolutionInput(_resolution, refundCents, _noteCtrl.text.trim()),
                  );
                },
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Submit Resolution'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
