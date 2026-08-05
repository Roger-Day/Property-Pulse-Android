import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/appointment_row.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/property_repository.dart';
import '../../repositories/user_profile_repository.dart';

/// Mirrors iOS `AppointmentSchedulingView` — standalone screen for scheduling
/// a viewing from anywhere in the app (profile appointments tab, deep link, etc.).
/// When [preSelectedProperty] is provided, the property picker is skipped.
class AppointmentSchedulingScreen extends StatefulWidget {
  const AppointmentSchedulingScreen({
    super.key,
    this.preSelectedProperty,
  });

  final PropertyModel? preSelectedProperty;

  @override
  State<AppointmentSchedulingScreen> createState() =>
      _AppointmentSchedulingScreenState();
}

class _AppointmentSchedulingScreenState
    extends State<AppointmentSchedulingScreen> {
  PropertyModel? _selectedProperty;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String _type = 'Property Viewing';
  int _duration = 60;
  final _notesCtrl = TextEditingController();
  bool _submitting = false;

  static const _types = kAppointmentTypes;
  static const _durations = [30, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    _selectedProperty = widget.preSelectedProperty;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit => _selectedProperty != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null || !mounted) return;

    setState(() {
      _date = DateTime(
          picked.year, picked.month, picked.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn || auth.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to schedule appointments.')),
      );
      return;
    }
    if (_selectedProperty == null) return;
    if (!_date.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Choose a date and time in the future.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final p = _selectedProperty!;
      await context.read<UserProfileRepository>().createAppointment(
            userId: auth.user!.uid,
            userName: auth.user!.displayName ?? 'Guest',
            userEmail: auth.user!.email ?? '',
            propertyId: p.id,
            propertyTitle: p.title,
            propertyAddress: '${p.street}, ${p.city}, ${p.state}',
            realtorId:
                p.realtorId ?? p.ownerId ?? p.hostUserId ?? '',
            realtorName: p.realtorName?.isNotEmpty == true
                ? p.realtorName!
                : (p.ownerName ?? 'Agent'),
            realtorEmail: p.realtorEmail ?? '',
            date: _date,
            duration: _duration,
            appointmentType: _type,
            notes: _notesCtrl.text.trim(),
          );
      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSuccess() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
        title: const Text('Appointment Requested'),
        content: const Text(
            'Your appointment request has been sent. You\'ll be notified when it\'s confirmed.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _openPropertyPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PropertyPickerSheet(
        onSelected: (p) => setState(() => _selectedProperty = p),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isSignedIn || auth.isAnonymous) {
      return Scaffold(
        appBar: AppBar(title: const Text('Schedule Appointment')),
        body: _SignInPrompt(
          onSignIn: () => context.push('/auth'),
        ),
      );
    }

    final dateFmt = DateFormat('EEE, MMM d · h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Appointment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Property ──────────────────────────────────────────────────────
          _FormSection(
            title: 'Property',
            child: _selectedProperty == null
                ? OutlinedButton.icon(
                    onPressed: _openPropertyPicker,
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Select Property'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  )
                : _SelectedPropertyTile(
                    property: _selectedProperty!,
                    onClear: widget.preSelectedProperty == null
                        ? () =>
                            setState(() => _selectedProperty = null)
                        : null,
                  ),
          ),
          const SizedBox(height: 16),

          // ── Appointment type ───────────────────────────────────────────────
          _FormSection(
            title: 'Appointment Type',
            child: DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _types
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
          ),
          const SizedBox(height: 16),

          // ── Date & time ────────────────────────────────────────────────────
          _FormSection(
            title: 'Date & Time',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today,
                      color: AppColors.primary),
                  title: Text(dateFmt.format(_date),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('Change'),
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _duration,
                  decoration: const InputDecoration(
                    labelText: 'Duration',
                    border: OutlineInputBorder(),
                  ),
                  items: _durations
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(_durationLabel(d)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _duration = v ?? _duration),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Notes ──────────────────────────────────────────────────────────
          _FormSection(
            title: 'Notes (Optional)',
            child: TextField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add any details for the agent…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Submit ─────────────────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (_canSubmit && !_submitting) ? _submit : null,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.calendar_month),
            label: const Text('Schedule Appointment'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The agent will be notified and will confirm your appointment.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _durationLabel(int mins) {
    if (mins < 60) return '$mins minutes';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '$h hour${h > 1 ? 's' : ''}';
    return '$h h ${m}min';
  }
}

// ─── Property picker sheet ────────────────────────────────────────────────────

class _PropertyPickerSheet extends StatefulWidget {
  const _PropertyPickerSheet({required this.onSelected});
  final void Function(PropertyModel) onSelected;

  @override
  State<_PropertyPickerSheet> createState() =>
      _PropertyPickerSheetState();
}

class _PropertyPickerSheetState extends State<_PropertyPickerSheet> {
  final _searchCtrl = TextEditingController();
  Future<List<PropertyModel>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<PropertyModel>> _load() {
    return context
        .read<PropertyRepository>()
        .watchHomePropertyPool()
        .first;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle
          const SizedBox(height: 8),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Text('Select Property',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search properties…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<PropertyModel>>(
              future: _future,
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final q = _searchCtrl.text.toLowerCase().trim();
                final items = snap.data!.where((p) {
                  if (q.isEmpty) return true;
                  return p.title.toLowerCase().contains(q) ||
                      p.city.toLowerCase().contains(q) ||
                      p.state.toLowerCase().contains(q);
                }).toList();

                if (items.isEmpty) {
                  return Center(
                    child: Text('No properties found',
                        style: TextStyle(
                            color: AppColors.textSecondary)),
                  );
                }

                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final p = items[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${p.city}, ${p.state} · ${p.displayPriceWithCurrencyCode}',
                          style: const TextStyle(fontSize: 12)),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onSelected(p);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Selected property tile ───────────────────────────────────────────────────

class _SelectedPropertyTile extends StatelessWidget {
  const _SelectedPropertyTile(
      {required this.property, required this.onClear});
  final PropertyModel property;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.home, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${property.city}, ${property.state}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Clear selected property',
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}

// ─── Form section wrapper ─────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// ─── Sign-in prompt ───────────────────────────────────────────────────────────

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Sign In Required',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to schedule appointments and property viewings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onSignIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
            ),
          ],
        ),
      ),
    );
  }
}
