import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

enum _DisputeStep { selectReason, describe, review, processing, success, failure }

enum _DisputeReason {
  propertyNotAsDescribed,
  hostCancelled,
  safetyIssue,
  checkInProblems,
  overcharge,
  refundNotReceived,
  other;

  String get label {
    switch (this) {
      case _DisputeReason.propertyNotAsDescribed:
        return 'Property not as described';
      case _DisputeReason.hostCancelled:
        return 'Host cancelled last minute';
      case _DisputeReason.safetyIssue:
        return 'Safety or health issue';
      case _DisputeReason.checkInProblems:
        return 'Check-in problems';
      case _DisputeReason.overcharge:
        return 'Overcharged / incorrect amount';
      case _DisputeReason.refundNotReceived:
        return 'Refund not received';
      case _DisputeReason.other:
        return 'Other issue';
    }
  }
}

/// Mirrors iOS `DisputeFlowView` — multi-step dispute filing for bookings.
class DisputeFlowScreen extends StatefulWidget {
  const DisputeFlowScreen({
    super.key,
    required this.bookingId,
    required this.propertyTitle,
    required this.reporterUserId,
    this.onDismiss,
  });

  final String bookingId;
  final String propertyTitle;
  final String reporterUserId;
  final VoidCallback? onDismiss;

  @override
  State<DisputeFlowScreen> createState() => _DisputeFlowScreenState();
}

class _DisputeFlowScreenState extends State<DisputeFlowScreen> {
  _DisputeStep _step = _DisputeStep.selectReason;
  _DisputeReason? _selectedReason;
  final _descriptionCtrl = TextEditingController();
  String? _disputeId;
  String? _error;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  bool get _canProceedFromReason => _selectedReason != null;
  bool get _canProceedFromDescribe =>
      _descriptionCtrl.text.trim().length >= 20;

  Future<void> _submit() async {
    setState(() => _step = _DisputeStep.processing);
    try {
      final ref = await FirebaseFirestore.instance
          .collection('disputes')
          .add({
        'bookingId': widget.bookingId,
        'propertyTitle': widget.propertyTitle,
        'reporterUserId': widget.reporterUserId,
        'reason': _selectedReason?.name,
        'description': _descriptionCtrl.text.trim(),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _disputeId = ref.id;
        _step = _DisputeStep.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _DisputeStep.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('File a Dispute'),
        leading: (_step == _DisputeStep.processing ||
                _step == _DisputeStep.success)
            ? const SizedBox.shrink()
            : CloseButton(onPressed: widget.onDismiss),
        automaticallyImplyLeading: false,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _DisputeStep.selectReason:
        return _ReasonStep(
          selectedReason: _selectedReason,
          onSelect: (r) => setState(() => _selectedReason = r),
          onNext: _canProceedFromReason
              ? () =>
                  setState(() => _step = _DisputeStep.describe)
              : null,
        );
      case _DisputeStep.describe:
        return _DescribeStep(
          controller: _descriptionCtrl,
          reason: _selectedReason,
          onBack: () =>
              setState(() => _step = _DisputeStep.selectReason),
          onNext: _canProceedFromDescribe
              ? () => setState(() => _step = _DisputeStep.review)
              : null,
          onChanged: (_) => setState(() {}),
        );
      case _DisputeStep.review:
        return _ReviewStep(
          propertyTitle: widget.propertyTitle,
          reason: _selectedReason,
          description: _descriptionCtrl.text.trim(),
          onBack: () =>
              setState(() => _step = _DisputeStep.describe),
          onSubmit: _submit,
        );
      case _DisputeStep.processing:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Submitting dispute…'),
            ],
          ),
        );
      case _DisputeStep.success:
        return _SuccessStep(
            disputeId: _disputeId ?? '',
            onDismiss: widget.onDismiss);
      case _DisputeStep.failure:
        return _FailureStep(
            message: _error ?? 'Unknown error',
            onDismiss: widget.onDismiss);
    }
  }
}

// ─── Step widgets ─────────────────────────────────────────────────────────────

class _ReasonStep extends StatelessWidget {
  const _ReasonStep({
    required this.selectedReason,
    required this.onSelect,
    required this.onNext,
  });
  final _DisputeReason? selectedReason;
  final void Function(_DisputeReason) onSelect;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text("What's the issue?",
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Select the reason that best describes your situation.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: ListView(
            children: _DisputeReason.values
                .map((r) => ListTile(
                      title: Text(r.label),
                      trailing: selectedReason == r
                          ? const Icon(Icons.check_circle,
                              color: AppColors.primary)
                          : const Icon(Icons.radio_button_unchecked,
                              color: AppColors.textSecondary),
                      onTap: () => onSelect(r),
                    ))
                .toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Continue'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DescribeStep extends StatelessWidget {
  const _DescribeStep({
    required this.controller,
    required this.reason,
    required this.onBack,
    required this.onNext,
    required this.onChanged,
  });
  final TextEditingController controller;
  final _DisputeReason? reason;
  final VoidCallback onBack;
  final VoidCallback? onNext;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(reason!.label,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          const SizedBox(height: 16),
          const Text('Describe the issue',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Provide as much detail as possible (minimum 20 characters).',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Describe what happened…',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
              onChanged: onChanged,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Back'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Review'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.propertyTitle,
    required this.reason,
    required this.description,
    required this.onBack,
    required this.onSubmit,
  });
  final String propertyTitle;
  final _DisputeReason? reason;
  final String description;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review Dispute',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _ReviewCard(
              label: 'Property', value: propertyTitle),
          const SizedBox(height: 8),
          _ReviewCard(
              label: 'Reason',
              value: reason?.label ?? '—'),
          const SizedBox(height: 8),
          _ReviewCard(label: 'Description', value: description),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.blue.withOpacity(0.2)),
            ),
            child: const Text(
              'Our team will review your dispute and respond within 2 business days.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Back'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Submit Dispute'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05), blurRadius: 3)
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep(
      {required this.disputeId, required this.onDismiss});
  final String disputeId;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                  color: Color(0xFFE3F2FD), shape: BoxShape.circle),
              child: const Icon(Icons.gavel, size: 40, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text('Dispute Filed',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Reference: ${disputeId.substring(0, 8).toUpperCase()}',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Our team will review your dispute and contact you within 2 business days.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailureStep extends StatelessWidget {
  const _FailureStep(
      {required this.message, required this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Submission Failed',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDismiss?.call();
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
