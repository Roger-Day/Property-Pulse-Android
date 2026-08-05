import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../services/stripe_service.dart';

enum _SpaceType {
  entirePlace('entire_place', 'Entire place',
      'Guests have the whole place to themselves', Icons.house_rounded),
  privateRoom('private_room', 'Private room',
      "Guests have their own room; common areas are shared", Icons.bed_rounded),
  sharedRoom('shared_room', 'Shared room', 'Guests sleep in a shared space',
      Icons.people_alt_rounded);

  const _SpaceType(this.value, this.title, this.subtitle, this.icon);
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
}

enum _BookingStyle {
  instant('instant_book', 'Instant Book',
      'Guests can book immediately — requires identity verification',
      Icons.bolt_rounded),
  request('request_to_book', 'Request to Book',
      'You approve every reservation before it\'s confirmed',
      Icons.verified_user_rounded);

  const _BookingStyle(this.value, this.title, this.subtitle, this.icon);
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// 5-step guided onboarding for users who choose the Airbnb Host role —
/// mirrors iOS `AirbnbHostOnboardingView`. State is persisted to Firestore
/// under `users/{uid}.airbnbOnboarding` as each step completes, same as iOS.
class AirbnbHostOnboardingScreen extends StatefulWidget {
  const AirbnbHostOnboardingScreen({super.key});

  @override
  State<AirbnbHostOnboardingScreen> createState() =>
      _AirbnbHostOnboardingScreenState();
}

class _AirbnbHostOnboardingScreenState
    extends State<AirbnbHostOnboardingScreen> {
  static const _totalSteps = 5;
  static const _rose = Color(0xFFED3D45);

  int _step = 0;
  bool _saving = false;
  String? _error;

  _SpaceType _spaceType = _SpaceType.entirePlace;
  double _monthlyIncomeGoal = 1000;
  int _daysAvailablePerWeek = 7;
  int _minNights = 1;
  final _checkInCtrl = TextEditingController(text: '15:00');
  final _checkOutCtrl = TextEditingController(text: '11:00');
  _BookingStyle _bookingStyle = _BookingStyle.request;

  bool _loadingStripe = true;
  bool _stripeConnected = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadStripeStatus();
  }

  @override
  void dispose() {
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    super.dispose();
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return _monthlyIncomeGoal > 0;
      case 2:
        return _daysAvailablePerWeek > 0;
      case 3:
        return true;
      case 4:
        return true; // Stripe can be connected later — never hard-blocks.
      default:
        return false;
    }
  }

  Future<void> _loadStripeStatus() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loadingStripe = false);
      return;
    }
    try {
      final status =
          await context.read<StripeService>().syncStripeConnectStatus(uid);
      if (!mounted) return;
      setState(() {
        _stripeConnected = status.payoutsEnabled && status.chargesEnabled;
        _loadingStripe = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStripe = false);
    }
  }

  Future<void> _connectStripe() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final url =
          await context.read<StripeService>().createStripeAccountLink(uid);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open Stripe onboarding.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _saveCurrentStep() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'airbnbOnboarding': {
          'lastCompletedStep': _step,
          'spaceType': _spaceType.value,
          'daysAvailablePerWeek': _daysAvailablePerWeek,
          'defaultCheckIn': _checkInCtrl.text.trim(),
          'defaultCheckOut': _checkOutCtrl.text.trim(),
          'minNights': _minNights,
          'bookingStyle': _bookingStyle.value,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save progress: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finish() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'airbnbOnboarding': {
          'isComplete': true,
          'completedAt': FieldValue.serverTimestamp(),
          'spaceType': _spaceType.value,
          'daysAvailablePerWeek': _daysAvailablePerWeek,
          'defaultCheckIn': _checkInCtrl.text.trim(),
          'defaultCheckOut': _checkOutCtrl.text.trim(),
          'minNights': _minNights,
          'bookingStyle': _bookingStyle.value,
        },
        'airbnbHostInfo': {
          'stripeConnectStatus': _stripeConnected ? 'active' : 'not_connected',
          'joinedAsHostDate': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not complete onboarding: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _advance() {
    if (_step == _totalSteps - 1) {
      _finish();
      return;
    }
    _saveCurrentStep();
    setState(() => _step += 1);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _error == null) return;
        final message = _error!;
        setState(() => _error = null);
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Host Setup')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(
              value: (_step + 1) / _totalSteps,
              color: _rose,
              backgroundColor: _rose.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Step ${_step + 1} of $_totalSteps',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildStep(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: OutlinedButton(
                        onPressed: _saving ? null : _back,
                        child: const Text('Back'),
                      ),
                    ),
                  Expanded(
                    child: FilledButton(
                      onPressed: !_canProceed || _saving ? null : _advance,
                      style: FilledButton.styleFrom(
                        backgroundColor: _rose,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_step == _totalSteps - 1 ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _spaceTypeStep();
      case 1:
        return _incomeGoalStep();
      case 2:
        return _calendarStep();
      case 3:
        return _bookingStyleStep();
      case 4:
        return _payoutStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _spaceTypeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('What kind of space will you host?',
            'Choose the option that best describes your place.'),
        for (final type in _SpaceType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _selectionCard(
              title: type.title,
              subtitle: type.subtitle,
              icon: type.icon,
              selected: _spaceType == type,
              onTap: () => setState(() => _spaceType = type),
            ),
          ),
      ],
    );
  }

  Widget _incomeGoalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Set a monthly income goal',
            'This helps us suggest a competitive nightly rate. You can change this any time.'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text('\$${_monthlyIncomeGoal.round()} / month',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _rose,
                      )),
              Slider(
                value: _monthlyIncomeGoal,
                min: 100,
                max: 10000,
                divisions: 99,
                activeColor: _rose,
                onChanged: (v) => setState(() => _monthlyIncomeGoal = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('\$100', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Text('\$10,000', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('💡 Tip: Properties in your area earn an average of \$85/night.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _calendarStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Set your default availability',
            'You control your calendar. Update it any time from your Host Dashboard.'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Days available per week',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              _stepperRow(
                value: _daysAvailablePerWeek,
                min: 1,
                max: 7,
                suffix: _daysAvailablePerWeek == 1 ? 'day' : 'days',
                onChanged: (v) => setState(() => _daysAvailablePerWeek = v),
              ),
              const Divider(height: 24),
              Text('Minimum stay (nights)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              _stepperRow(
                value: _minNights,
                min: 1,
                max: 30,
                suffix: _minNights == 1 ? 'night' : 'nights',
                onChanged: (v) => setState(() => _minNights = v),
              ),
              const Divider(height: 24),
              Text('Check-in time',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _checkInCtrl,
                decoration: const InputDecoration(
                    hintText: 'e.g. 15:00', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 14),
              Text('Check-out time',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _checkOutCtrl,
                decoration: const InputDecoration(
                    hintText: 'e.g. 11:00', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepperRow({
    required int value,
    required int min,
    required int max,
    required String suffix,
    required void Function(int) onChanged,
  }) {
    return Row(
      children: [
        Expanded(child: Text('$value $suffix')),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: 'Decrease $suffix',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          tooltip: 'Increase $suffix',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  Widget _bookingStyleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('How would you like to accept bookings?',
            'You can change this in your listing settings later.'),
        for (final style in _BookingStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _selectionCard(
              title: style.title,
              subtitle: style.subtitle,
              icon: style.icon,
              selected: _bookingStyle == style,
              onTap: () => setState(() => _bookingStyle = style),
            ),
          ),
        if (_bookingStyle == _BookingStyle.instant)
          _infoBanner(
            icon: Icons.info_outline,
            message: 'Instant Book requires identity verification before going live.',
            tint: Colors.blue,
          ),
      ],
    );
  }

  Widget _payoutStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepHeader('Set up payouts',
            'Connect Stripe to receive earnings directly to your bank account.'),
        if (_loadingStripe)
          const Center(child: CircularProgressIndicator())
        else if (_stripeConnected)
          _infoBanner(
            icon: Icons.check_circle,
            message: "Stripe is connected. You're ready to receive payouts.",
            tint: Colors.green,
          )
        else ...[
          _infoBanner(
            icon: Icons.warning_amber_rounded,
            message:
                'Stripe is not yet connected. Complete Stripe onboarding to publish your listing.',
            tint: Colors.orange,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _connectStripe,
              icon: const Icon(Icons.credit_card),
              label: const Text('Connect with Stripe'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loadStripeStatus,
              child: const Text('Refresh status', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'You can tap Finish now and connect Stripe later from Host Settings.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _selectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? _rose.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _rose : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _rose : AppColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: _rose),
          ],
        ),
      ),
    );
  }

  Widget _infoBanner({required IconData icon, required String message, required Color tint}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
