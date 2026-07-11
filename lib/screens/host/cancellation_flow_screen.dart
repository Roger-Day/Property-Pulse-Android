import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../services/cancellation_service.dart';

enum _CancellationStep { selectReason, reviewPolicy, confirm, processing, success, failure }

enum _CancellationReason {
  propertyUnavailable,
  emergency,
  doubleBooked,
  maintenanceIssue,
  other;

  String get label {
    switch (this) {
      case _CancellationReason.propertyUnavailable:
        return 'Property unavailable';
      case _CancellationReason.emergency:
        return 'Host emergency';
      case _CancellationReason.doubleBooked:
        return 'Double booking';
      case _CancellationReason.maintenanceIssue:
        return 'Maintenance issue';
      case _CancellationReason.other:
        return 'Other';
    }
  }

  String get value {
    switch (this) {
      case _CancellationReason.propertyUnavailable:
        return 'host_property_unavailable';
      case _CancellationReason.emergency:
        return 'host_emergency';
      case _CancellationReason.doubleBooked:
        return 'host_double_booked';
      case _CancellationReason.maintenanceIssue:
        return 'host_maintenance_issue';
      case _CancellationReason.other:
        return 'other';
    }
  }
}

/// Mirrors iOS `CancellationFlowView` — multi-step booking cancellation.
class CancellationFlowScreen extends StatefulWidget {
  const CancellationFlowScreen({
    super.key,
    required this.bookingId,
    required this.propertyTitle,
    required this.guestName,
    required this.totalPrice,
    this.onDismiss,
  });

  final String bookingId;
  final String propertyTitle;
  final String guestName;
  final double totalPrice;
  final VoidCallback? onDismiss;

  @override
  State<CancellationFlowScreen> createState() =>
      _CancellationFlowScreenState();
}

class _CancellationFlowScreenState extends State<CancellationFlowScreen> {
  _CancellationStep _step = _CancellationStep.selectReason;
  _CancellationReason? _selectedReason;
  String _customReason = '';
  String? _error;

  // Hosts cancelling bookings always issue a full 100% refund.
  double get _refundPercent => 100.0;

  double get _refundAmount => widget.totalPrice * _refundPercent / 100;

  bool get _canProceed =>
      _selectedReason != null &&
      (_selectedReason != _CancellationReason.other ||
          _customReason.trim().isNotEmpty);

  Future<void> _submit() async {
    setState(() => _step = _CancellationStep.processing);
    try {
      final cancellationService = context.read<CancellationService>();
      await cancellationService.cancelBooking(
        bookingId: widget.bookingId,
        reason: _selectedReason?.value ?? 'other',
        role: 'host',
        customReason: _customReason,
      );
      if (!mounted) return;
      setState(() => _step = _CancellationStep.success);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _step = _CancellationStep.failure;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cancel Booking'),
        leading: (_step == _CancellationStep.processing ||
                _step == _CancellationStep.success)
            ? const SizedBox.shrink()
            : CloseButton(onPressed: widget.onDismiss),
        automaticallyImplyLeading: false,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _CancellationStep.selectReason:
        return _ReasonStep(
          selectedReason: _selectedReason,
          customReason: _customReason,
          onSelectReason: (r) =>
              setState(() => _selectedReason = r),
          onCustomReasonChanged: (v) =>
              setState(() => _customReason = v),
          onNext: _canProceed
              ? () => setState(
                  () => _step = _CancellationStep.reviewPolicy)
              : null,
        );
      case _CancellationStep.reviewPolicy:
        return _PolicyStep(
          propertyTitle: widget.propertyTitle,
          guestName: widget.guestName,
          totalPrice: widget.totalPrice,
          refundAmount: _refundAmount,
          refundPercent: _refundPercent,
          onBack: () =>
              setState(() => _step = _CancellationStep.selectReason),
          onConfirm: () =>
              setState(() => _step = _CancellationStep.confirm),
        );
      case _CancellationStep.confirm:
        return _ConfirmStep(
          propertyTitle: widget.propertyTitle,
          refundAmount: _refundAmount,
          onBack: () =>
              setState(() => _step = _CancellationStep.reviewPolicy),
          onSubmit: _submit,
        );
      case _CancellationStep.processing:
        return const _ProcessingStep();
      case _CancellationStep.success:
        return _SuccessStep(
            refundAmount: _refundAmount,
            onDismiss: widget.onDismiss);
      case _CancellationStep.failure:
        return _FailureStep(
            message: _error ?? 'Unknown error',
            onDismiss: widget.onDismiss);
    }
  }
}

class _ReasonStep extends StatelessWidget {
  const _ReasonStep({
    required this.selectedReason,
    required this.customReason,
    required this.onSelectReason,
    required this.onCustomReasonChanged,
    required this.onNext,
  });

  final _CancellationReason? selectedReason;
  final String customReason;
  final void Function(_CancellationReason) onSelectReason;
  final void Function(String) onCustomReasonChanged;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why are you cancelling?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06), blurRadius: 4),
              ],
            ),
            child: Column(
              children: _CancellationReason.values
                  .map((r) => _ReasonTile(
                        reason: r,
                        isSelected: selectedReason == r,
                        onTap: () => onSelectReason(r),
                      ))
                  .toList(),
            ),
          ),
          if (selectedReason == _CancellationReason.other) ...[
            const SizedBox(height: 16),
            const Text('Additional details',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                  hintText: 'Tell us more...',
                  border: OutlineInputBorder()),
              maxLines: 3,
              onChanged: onCustomReasonChanged,
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('See Cancellation Policy'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile(
      {required this.reason,
      required this.isSelected,
      required this.onTap});
  final _CancellationReason reason;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(reason.label),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : const Icon(Icons.radio_button_unchecked,
              color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _PolicyStep extends StatelessWidget {
  const _PolicyStep({
    required this.propertyTitle,
    required this.guestName,
    required this.totalPrice,
    required this.refundAmount,
    required this.refundPercent,
    required this.onBack,
    required this.onConfirm,
  });

  final String propertyTitle;
  final String guestName;
  final double totalPrice;
  final double refundAmount;
  final double refundPercent;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cancellation Policy',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _InfoCard(
            children: [
              _InfoRow(label: 'Property', value: propertyTitle),
              _InfoRow(label: 'Guest', value: guestName),
              _InfoRow(
                  label: 'Total Paid',
                  value: '\$${totalPrice.toStringAsFixed(2)}'),
              _InfoRow(
                  label: 'Refund',
                  value:
                      '\$${refundAmount.toStringAsFixed(2)} (${refundPercent.round()}%)',
                  valueColor: Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Refunds are processed within 5–7 business days.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onBack,
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.propertyTitle,
    required this.refundAmount,
    required this.onBack,
    required this.onSubmit,
  });

  final String propertyTitle;
  final double refundAmount;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confirm Cancellation',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(
            'Are you sure you want to cancel this booking for $propertyTitle? You\'ll receive a refund of \$${refundAmount.toStringAsFixed(2)}.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone.',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: onBack, child: const Text('Back')),
              ),
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
                  child: const Text('Cancel Booking'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProcessingStep extends StatelessWidget {
  const _ProcessingStep();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Processing cancellation…'),
          ],
        ),
      );
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep(
      {required this.refundAmount, required this.onDismiss});
  final double refundAmount;
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
                  color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.check, size: 44, color: Colors.green),
            ),
            const SizedBox(height: 20),
            const Text('Booking Cancelled',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Your refund of \$${refundAmount.toStringAsFixed(2)} will be processed within 5–7 business days.',
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
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Cancellation Failed',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
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

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06), blurRadius: 4),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }
}
