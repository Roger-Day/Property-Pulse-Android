import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../repositories/admin_application_repository.dart';

/// Weekday raw values match iOS `Weekday` enum / Firestore.
enum _AdminWeekday {
  monday('monday', 'Monday'),
  tuesday('tuesday', 'Tuesday'),
  wednesday('wednesday', 'Wednesday'),
  thursday('thursday', 'Thursday'),
  friday('friday', 'Friday'),
  saturday('saturday', 'Saturday'),
  sunday('sunday', 'Sunday');

  const _AdminWeekday(this.raw, this.label);
  final String raw;
  final String label;
}

/// Mirrors iOS `AdminApplicationView` — six-step wizard + submit to `adminApplications`.
class AdminApplicationFormScreen extends StatefulWidget {
  const AdminApplicationFormScreen({super.key});

  @override
  State<AdminApplicationFormScreen> createState() =>
      _AdminApplicationFormScreenState();
}

class _RefDraft {
  _RefDraft()
      : name = TextEditingController(),
        position = TextEditingController(),
        company = TextEditingController(),
        email = TextEditingController(),
        relationship = TextEditingController();

  final TextEditingController name;
  final TextEditingController position;
  final TextEditingController company;
  final TextEditingController email;
  final TextEditingController relationship;
  var yearsKnown = 0;

  void dispose() {
    name.dispose();
    position.dispose();
    company.dispose();
    email.dispose();
    relationship.dispose();
  }
}

class _AdminApplicationFormScreenState extends State<AdminApplicationFormScreen> {
  static const _totalSteps = 6;

  final PageController _pageController = PageController();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _position = TextEditingController();
  final _department = TextEditingController();

  final _techSkills = TextEditingController();
  final _certs = TextEditingController();
  final _languages = TextEditingController();

  final _motivation = TextEditingController();

  var _yearsRe = 0;
  var _mgmtYears = 0;
  var _hoursPerWeek = 0;
  final Set<String> _preferredDays = {};
  var _commitmentRaw = 'long_term';

  final List<TextEditingController> _leadership =
      List.generate(3, (_) => TextEditingController());

  final List<_RefDraft> _references = [_RefDraft(), _RefDraft()];

  var _currentStep = 0;
  var _submitting = false;
  String _currentRoleRaw = 'Property Seeker';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _name.text = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : '';
    _email.text = user?.email ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoleFromProfile());
  }

  Future<void> _loadRoleFromProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .get();
      final role = doc.data()?['role'] as String?;
      if (!mounted) return;
      if (role != null && role.trim().isNotEmpty) {
        setState(() => _currentRoleRaw = role.trim());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    _name.dispose();
    _email.dispose();
    _company.dispose();
    _position.dispose();
    _department.dispose();
    _techSkills.dispose();
    _certs.dispose();
    _languages.dispose();
    _motivation.dispose();
    for (final c in _leadership) {
      c.dispose();
    }
    for (final r in _references) {
      r.dispose();
    }
    super.dispose();
  }

  int get _referenceSlotCount => max(2, _references.length + 1);

  void _ensureRefSlot(int index) {
    while (_references.length <= index) {
      _references.add(_RefDraft());
    }
  }

  List<String> _splitCommaList(String text) {
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool _isStepValid(int step) {
    switch (step) {
      case 0:
        return _name.text.trim().isNotEmpty && _email.text.trim().isNotEmpty;
      case 1:
        return true;
      case 2:
        return _hoursPerWeek > 0;
      case 3:
        return _motivation.text.trim().isNotEmpty;
      case 4:
        final slots = _referenceSlotCount;
        for (var i = 0; i < slots; i++) {
          _ensureRefSlot(i);
        }
        final filled = _references
            .take(slots)
            .where(
              (r) =>
                  r.name.text.trim().isNotEmpty &&
                  r.email.text.trim().isNotEmpty,
            )
            .length;
        return filled >= 2 &&
            _references.take(slots).every(
                  (r) =>
                      r.name.text.trim().isEmpty ||
                      (r.name.text.trim().isNotEmpty &&
                          r.email.text.trim().isNotEmpty),
                );
      default:
        return true;
    }
  }

  bool _isApplicationComplete() {
    return _isStepValid(0) &&
        _isStepValid(2) &&
        _isStepValid(3) &&
        _isStepValid(4);
  }

  Future<void> _submit() async {
    if (!_isApplicationComplete() || _submitting) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final slots = _referenceSlotCount;
    for (var i = 0; i < slots; i++) {
      _ensureRefSlot(i);
    }
    final refPayload = _references
        .take(slots)
        .where(
          (r) =>
              r.name.text.trim().isNotEmpty && r.email.text.trim().isNotEmpty,
        )
        .map(
          (r) => AdminReferenceSubmit(
            id: AdminApplicationRepository.newReferenceId(),
            name: r.name.text,
            position: r.position.text,
            company: r.company.text,
            email: r.email.text,
            relationship: r.relationship.text.trim().isEmpty
                ? 'Professional'
                : r.relationship.text,
            yearsKnown: r.yearsKnown,
          ),
        )
        .toList();

    final leadership = _leadership
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    setState(() => _submitting = true);

    try {
      await context.read<AdminApplicationRepository>().submitFullApplication(
            applicantId: uid,
            applicantName: _name.text,
            applicantEmail: _email.text,
            currentRoleRaw: _currentRoleRaw,
            yearsInRealEstate: _yearsRe,
            managementExperience: _mgmtYears,
            companyName: _company.text.trim().isEmpty ? null : _company.text,
            position: _position.text.trim().isEmpty ? null : _position.text,
            department:
                _department.text.trim().isEmpty ? null : _department.text,
            technicalSkills: _splitCommaList(_techSkills.text),
            certifications: _splitCommaList(_certs.text),
            languages: _splitCommaList(_languages.text),
            hoursPerWeek: _hoursPerWeek,
            preferredDayRawValues: _preferredDays.toList()..sort(),
            commitmentRaw: _commitmentRaw,
            motivation: _motivation.text,
            leadershipExamples: leadership,
            references: refPayload,
          );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Application Submitted'),
          content: const Text(
            'Your admin application has been submitted successfully. '
            'You will be notified of the status.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: Text('$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _goStep(int delta) {
    final next = (_currentStep + delta).clamp(0, _totalSteps - 1);
    setState(() => _currentStep = next);
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for Admin'),
        leading: TextButton(
          onPressed: _submitting ? null : () => context.pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 88,
      ),
      body: Column(
        children: [
          _ProgressHeader(currentStep: _currentStep, total: _totalSteps),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _basicStep(theme),
                _experienceStep(theme),
                _availabilityStep(theme),
                _motivationStep(theme),
                _referencesStep(theme),
                _reviewStep(theme),
              ],
            ),
          ),
          Material(
            elevation: 8,
            color: theme.colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    if (_currentStep > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _submitting ? null : () => _goStep(-1),
                          child: const Text('Previous'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: _currentStep < _totalSteps - 1
                          ? FilledButton(
                              onPressed:
                                  !_isStepValid(_currentStep) || _submitting
                                      ? null
                                      : () => _goStep(1),
                              child: const Text('Next'),
                            )
                          : FilledButton(
                              onPressed:
                                  !_isApplicationComplete() || _submitting
                                      ? null
                                      : _submit,
                              child: _submitting
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : const Text('Submit Application'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, {required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _basicStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          theme,
          children: [
            Text('Personal Information', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Professional Information',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company Name (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _position,
              decoration: const InputDecoration(
                labelText: 'Position (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _department,
              decoration: const InputDecoration(
                labelText: 'Department (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Experience', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Years in Real Estate: $_yearsRe')),
                IconButton(
                  onPressed: () => setState(() {
                    _yearsRe = (_yearsRe - 1).clamp(0, 50);
                  }),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _yearsRe = (_yearsRe + 1).clamp(0, 50);
                  }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child:
                        Text('Management Experience (years): $_mgmtYears')),
                IconButton(
                  onPressed: () => setState(() {
                    _mgmtYears = (_mgmtYears - 1).clamp(0, 30);
                  }),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _mgmtYears = (_mgmtYears + 1).clamp(0, 30);
                  }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _experienceStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          theme,
          children: [
            Text('Technical Skills', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'List your technical skills (comma-separated)',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _techSkills,
              decoration: const InputDecoration(
                hintText: 'e.g., Kotlin, Firebase, Flutter',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Certifications', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'List your certifications (comma-separated)',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _certs,
              decoration: const InputDecoration(
                hintText: 'e.g., Real Estate License',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Languages', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _languages,
              decoration: const InputDecoration(
                hintText: 'e.g., English, Spanish',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _availabilityStep(ThemeData theme) {
    const commitmentChoices = <MapEntry<String, String>>[
      MapEntry('short_term', 'Short Term (1-3 months)'),
      MapEntry('medium_term', 'Medium Term (3-12 months)'),
      MapEntry('long_term', 'Long Term (1+ years)'),
      MapEntry('indefinite', 'Indefinite'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          theme,
          children: [
            Text('Availability', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Hours per week: $_hoursPerWeek')),
                IconButton(
                  onPressed: () => setState(() {
                    _hoursPerWeek = (_hoursPerWeek - 1).clamp(1, 40);
                  }),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _hoursPerWeek = (_hoursPerWeek + 1).clamp(1, 40);
                  }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Preferred Days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _AdminWeekday.values.map((day) {
                final sel = _preferredDays.contains(day.raw);
                return FilterChip(
                  label: Text(day.label),
                  selected: sel,
                  onSelected: (_) {
                    setState(() {
                      if (sel) {
                        _preferredDays.remove(day.raw);
                      } else {
                        _preferredDays.add(day.raw);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Commitment Level', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: commitmentChoices
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _commitmentRaw == e.key,
                      onSelected: (_) =>
                          setState(() => _commitmentRaw = e.key),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _motivationStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          theme,
          children: [
            Text(
              'Why do you want to be an admin?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Please explain your motivation for becoming an admin and how '
              'you would contribute to the platform.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivation,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text('Leadership Examples', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Describe specific examples of your leadership experience.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) ...[
              TextField(
                controller: _leadership[i],
                decoration: InputDecoration(
                  labelText: 'Leadership example ${i + 1}',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ],
    );
  }

  Widget _referencesStep(ThemeData theme) {
    final n = _referenceSlotCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'References',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Add at least 2 professional references who can vouch for your qualifications.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (var index = 0; index < n; index++)
          _referenceCard(theme, index),
      ],
    );
  }

  Widget _referenceCard(ThemeData theme, int index) {
    _ensureRefSlot(index);
    final r = _references[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reference ${index + 1}',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: r.name,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: r.position,
              decoration: const InputDecoration(
                labelText: 'Position',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: r.company,
              decoration: const InputDecoration(
                labelText: 'Company',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: r.email,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: r.relationship,
              decoration: const InputDecoration(
                labelText: 'Relationship',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Years known: ${r.yearsKnown}')),
                IconButton(
                  onPressed: () => setState(() {
                    r.yearsKnown = (r.yearsKnown - 1).clamp(0, 50);
                  }),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    r.yearsKnown = (r.yearsKnown + 1).clamp(0, 50);
                  }),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep(ThemeData theme) {
    final days = _preferredDays.isEmpty
        ? '—'
        : _AdminWeekday.values
            .where((d) => _preferredDays.contains(d.raw))
            .map((d) => d.label)
            .join(', ');
    final commitmentLabel = const {
      'short_term': 'Short Term (1-3 months)',
      'medium_term': 'Medium Term (3-12 months)',
      'long_term': 'Long Term (1+ years)',
      'indefinite': 'Indefinite',
    }[_commitmentRaw];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Review Your Application',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _card(
          theme,
          children: [
            Text(
              'Personal Information',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Name: ${_name.text.trim()}',
                style: theme.textTheme.bodyMedium),
            Text('Email: ${_email.text.trim()}',
                style: theme.textTheme.bodyMedium),
            Text('Current Role: $_currentRoleRaw',
                style: theme.textTheme.bodyMedium),
          ],
        ),
        _card(
          theme,
          children: [
            Text(
              'Experience',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Real Estate Experience: $_yearsRe years',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Management Experience: $_mgmtYears years',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Technical Skills: ${_techSkills.text.trim().isEmpty ? '—' : _techSkills.text.trim()}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text(
              'Availability',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Hours per week: $_hoursPerWeek',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Commitment: ${commitmentLabel ?? _commitmentRaw}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Preferred days: $days',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        _card(
          theme,
          children: [
            Text(
              'Motivation',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _motivation.text.trim().isEmpty ? '—' : _motivation.text.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.currentStep,
    required this.total,
  });

  final int currentStep;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade900.withValues(alpha: 0.4)
          : Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                for (var step = 0; step < total; step++) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: step <= currentStep ? cs.primary : Colors.grey,
                    ),
                  ),
                  if (step < total - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        color: step < currentStep ? cs.primary : Colors.grey,
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Step ${currentStep + 1} of $total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
