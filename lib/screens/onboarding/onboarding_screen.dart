import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/analytics_service.dart';

/// Android equivalent of iOS `OnboardingFlowView`.
///
/// 9 paged steps with progress bar + Skip.
/// Interactive user-type cards, permission request buttons, personalised
/// features list, region picker, and a name field — matching iOS parity.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _index = 0;

  // Profile step
  final TextEditingController _nameController = TextEditingController();

  // Location step
  final TextEditingController _regionController = TextEditingController();

  // Permissions state
  bool _locationGranted = false;
  bool _notifGranted = false;

  // ── Step definitions ─────────────────────────────────────────────────────

  static const _steps = <_StepData>[
    _StepData(
      icon: Icons.waving_hand_rounded,
      title: 'Welcome',
      body: 'Welcome to Property Pulse. Discover listings, developments, and tools to find your next place.',
    ),
    _StepData(
      icon: Icons.people_outline_rounded,
      title: 'Tell us about yourself',
      body: 'How are you planning to use Property Pulse? You can refine this later in your profile.',
    ),
    _StepData(
      icon: Icons.verified_user_outlined,
      title: 'Permissions',
      body: 'Allow notifications and location access for a better, personalised experience.',
    ),
    _StepData(
      icon: Icons.star_outline_rounded,
      title: 'Features for you',
      body: 'Here\'s what Property Pulse has built for your needs.',
    ),
    _StepData(
      icon: Icons.notifications_outlined,
      title: 'Stay updated',
      body: 'Turn on notifications so you never miss messages, appointments, or listing updates.',
    ),
    _StepData(
      icon: Icons.location_on_outlined,
      title: 'Your location',
      body: 'Tell us where you\'re looking so we can show you relevant listings on the home feed.',
    ),
    _StepData(
      icon: Icons.person_outline_rounded,
      title: 'Your profile',
      body: 'Add your name so hosts and agents can recognise you in messages.',
    ),
    _StepData(
      icon: Icons.tune_rounded,
      title: 'Preferences',
      body: 'You can fine-tune card density, image autoplay, and tip overlays in Settings at any time.',
    ),
    _StepData(
      icon: Icons.check_circle_outline_rounded,
      title: "You\'re all set",
      body: 'Create an account or sign in to save favourites, message hosts, and more.',
    ),
  ];

  // ── User type data ───────────────────────────────────────────────────────

  static const _userTypes = <_UserTypeOption>[
    _UserTypeOption(
      id: 'propertySeeker',
      icon: Icons.search_rounded,
      label: 'Home Seeker',
      description: 'Looking to buy or rent a property',
    ),
    _UserTypeOption(
      id: 'realtor',
      icon: Icons.badge_outlined,
      label: 'Agent / Realtor',
      description: 'Connecting buyers and sellers',
    ),
    _UserTypeOption(
      id: 'owner',
      icon: Icons.home_work_outlined,
      label: 'Property Owner',
      description: 'Listing or renting out your property',
    ),
    _UserTypeOption(
      id: 'developer',
      icon: Icons.construction_outlined,
      label: 'Developer',
      description: 'Building and selling developments',
    ),
  ];

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    AnalyticsService.logOnboardingStarted();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OnboardingProvider>().markInProgress();
    });
    _checkCurrentPermissions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentPermissions() async {
    final locStatus = await Geolocator.checkPermission();
    final notifSettings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!mounted) return;
    setState(() {
      _locationGranted = locStatus == LocationPermission.always ||
          locStatus == LocationPermission.whileInUse;
      _notifGranted = notifSettings.authorizationStatus ==
          AuthorizationStatus.authorized;
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    // Persist display name before completing
    final ob = context.read<OnboardingProvider>();
    final name = _nameController.text.trim();
    if (name.isNotEmpty) await ob.setDisplayName(name);
    await ob.completeOnboarding();
    AnalyticsService.logOnboardingCompleted();
    if (!mounted) return;
    context.go('/auth');
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip onboarding?'),
        content: const Text('You can revisit these steps any time in Settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      AnalyticsService.logOnboardingSkipped();
      await context.read<OnboardingProvider>().skipOnboarding();
      if (!mounted) return;
      context.go('/auth');
    }
  }

  void _next() {
    AnalyticsService.logOnboardingStepCompleted(_index + 1);
    if (_index < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  // ── Permission helpers ────────────────────────────────────────────────────

  Future<void> _requestLocation() async {
    var status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      _locationGranted = status == LocationPermission.always ||
          status == LocationPermission.whileInUse;
    });
  }

  Future<void> _requestNotifications() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (!mounted) return;
    setState(() {
      _notifGranted = settings.authorizationStatus ==
          AuthorizationStatus.authorized;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onboarding = context.watch<OnboardingProvider>();

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.08),
              scheme.secondary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header: Skip + progress counter ───────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _skip,
                      child: Text(
                        'Skip',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} of ${_steps.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),

              // ── Progress bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    minHeight: 4,
                    backgroundColor:
                        scheme.outlineVariant.withValues(alpha: 0.5),
                    color: AppColors.primary,
                  ),
                ),
              ),

              // ── Pages ─────────────────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _buildPage(context, i, onboarding),
                ),
              ),

              // ── Primary action button ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _index == _steps.length - 1 ? 'Get Started' : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_index < _steps.length - 1) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    int i,
    OnboardingProvider onboarding,
  ) {
    final step = _steps[i];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Step icon in a coloured circle (matches iOS 120pt container)
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: Icon(step.icon, size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 28),
          // ── Interactive content per step ────────────────────────────────
          _buildStepContent(i, onboarding),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStepContent(int i, OnboardingProvider onboarding) {
    switch (i) {
      case 1:
        return _UserTypeGrid(
          options: _userTypes,
          selected: onboarding.userType,
          onSelect: (type) {
            onboarding.setUserType(type);
            AnalyticsService.logOnboardingUserTypeSelected(type);
          },
        );
      case 2:
        return _PermissionsStep(
          locationGranted: _locationGranted,
          notifGranted: _notifGranted,
          onRequestLocation: _requestLocation,
          onRequestNotif: _requestNotifications,
        );
      case 3:
        return _FeaturesStep(userType: onboarding.userType);
      case 4:
        return _NotificationStep(
          granted: _notifGranted,
          onRequest: _requestNotifications,
        );
      case 5:
        return _LocationStep(controller: _regionController);
      case 6:
        return _ProfileStep(controller: _nameController);
      case 7:
        return const _PreferencesStep();
      case 8:
        return const _CompletionStep();
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Step data ────────────────────────────────────────────────────────────────

class _StepData {
  const _StepData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _UserTypeOption {
  const _UserTypeOption({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
  });

  final String id;
  final IconData icon;
  final String label;
  final String description;
}

// ── Step 1: User-type selection ──────────────────────────────────────────────

class _UserTypeGrid extends StatelessWidget {
  const _UserTypeGrid({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<_UserTypeOption> options;
  final String selected;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: options
          .map(
            (o) => _UserTypeCard(
              option: o,
              isSelected: selected == o.id,
              onTap: () => onSelect(o.id),
            ),
          )
          .toList(),
    );
  }
}

class _UserTypeCard extends StatelessWidget {
  const _UserTypeCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _UserTypeOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              option.icon,
              size: 34,
              color: isSelected ? AppColors.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              option.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? AppColors.primary : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              option.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 2: Permissions ──────────────────────────────────────────────────────

class _PermissionsStep extends StatelessWidget {
  const _PermissionsStep({
    required this.locationGranted,
    required this.notifGranted,
    required this.onRequestLocation,
    required this.onRequestNotif,
  });

  final bool locationGranted;
  final bool notifGranted;
  final VoidCallback onRequestLocation;
  final VoidCallback onRequestNotif;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PermissionRow(
          icon: Icons.location_on_outlined,
          title: 'Location',
          description: 'Find nearby listings and get local recommendations.',
          granted: locationGranted,
          onRequest: onRequestLocation,
        ),
        const SizedBox(height: 12),
        _PermissionRow(
          icon: Icons.notifications_outlined,
          title: 'Notifications',
          description: 'Stay updated on messages, appointments, and listings.',
          granted: notifGranted,
          onRequest: onRequestNotif,
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onRequest,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          granted
              ? Icon(Icons.check_circle_rounded,
                  color: AppColors.secondary, size: 26)
              : FilledButton.tonal(
                  onPressed: onRequest,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Allow', style: TextStyle(fontSize: 13)),
                ),
        ],
      ),
    );
  }
}

// ── Step 3: Features (personalised) ─────────────────────────────────────────

class _FeaturesStep extends StatelessWidget {
  const _FeaturesStep({required this.userType});

  final String userType;

  static const _featuresByType = <String, List<(IconData, String)>>{
    'propertySeeker': [
      (Icons.tune_rounded, 'Filter by budget, size, and location'),
      (Icons.bookmark_outline_rounded, 'Save favourite listings'),
      (Icons.calendar_month_outlined, 'Book property viewings'),
      (Icons.notifications_outlined, 'Get price-drop alerts'),
    ],
    'realtor': [
      (Icons.home_outlined, 'Manage and promote listings'),
      (Icons.bar_chart_rounded, 'View listing analytics'),
      (Icons.chat_rounded, 'Connect directly with buyers'),
      (Icons.verified_outlined, 'Verify your identity for trust'),
    ],
    'owner': [
      (Icons.add_home_outlined, 'List your property for free'),
      (Icons.calendar_month_outlined, 'Manage bookings and viewings'),
      (Icons.visibility_outlined, 'Track listing views and saves'),
      (Icons.verified_outlined, 'Get your listing verified'),
    ],
    'developer': [
      (Icons.domain_outlined, 'Showcase development projects'),
      (Icons.inventory_2_outlined, 'Manage unit inventory'),
      (Icons.people_outline_rounded, 'Connect with investors and buyers'),
      (Icons.bar_chart_rounded, 'Track project analytics'),
    ],
  };

  static const _defaultFeatures = <(IconData, String)>[
    (Icons.search_rounded, 'Search thousands of verified listings'),
    (Icons.chat_rounded, 'Message hosts and agents directly'),
    (Icons.map_outlined, 'Explore listings on an interactive map'),
    (Icons.star_outline_rounded, 'Discover featured new developments'),
  ];

  @override
  Widget build(BuildContext context) {
    final features = _featuresByType[userType] ?? _defaultFeatures;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: features
          .map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(f.$1, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Step 4: Notification permission ─────────────────────────────────────────

class _NotificationStep extends StatelessWidget {
  const _NotificationStep({required this.granted, required this.onRequest});

  final bool granted;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            granted
                ? Icons.notifications_active_rounded
                : Icons.notifications_outlined,
            size: 48,
            color: granted ? AppColors.secondary : AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            granted ? 'Notifications are on' : 'Enable Notifications',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            granted
                ? 'You\'re all set. We\'ll notify you about messages, viewings, and listing updates.'
                : 'Allow notifications to receive real-time updates on your enquiries and saved listings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (!granted) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRequest,
              icon: const Icon(Icons.notifications_rounded, size: 18),
              label: const Text('Enable Notifications'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Step 5: Location / Region ────────────────────────────────────────────────

class _LocationStep extends StatelessWidget {
  const _LocationStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'City or Region',
            hintText: 'e.g. London, New York, Lagos',
            prefixIcon: const Icon(Icons.location_city_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'You can update your preferred region any time in your profile.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 6: Profile — display name ───────────────────────────────────────────

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Avatar placeholder
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(alpha: 0.12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            size: 36,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your name',
            hintText: 'Enter your display name',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'This is shown to hosts and agents when you send messages.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── Step 7: Preferences ──────────────────────────────────────────────────────

class _PreferencesStep extends StatefulWidget {
  const _PreferencesStep();

  @override
  State<_PreferencesStep> createState() => _PreferencesStepState();
}

class _PreferencesStepState extends State<_PreferencesStep> {
  bool _compactCards = false;
  bool _autoplay = true;
  bool _showTips = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          _PrefTile(
            title: 'Compact card view',
            subtitle: 'Show more listings on screen',
            value: _compactCards,
            onChanged: (v) => setState(() => _compactCards = v),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _PrefTile(
            title: 'Autoplay images',
            subtitle: 'Automatically scroll listing photos',
            value: _autoplay,
            onChanged: (v) => setState(() => _autoplay = v),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _PrefTile(
            title: 'Show tips',
            subtitle: 'Helpful hints while browsing',
            value: _showTips,
            onChanged: (v) => setState(() => _showTips = v),
          ),
        ],
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  const _PrefTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// ── Step 8: Completion ────────────────────────────────────────────────────────

class _CompletionStep extends StatelessWidget {
  const _CompletionStep();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Celebration ring
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.secondary.withValues(alpha: 0.12),
          ),
          child: Icon(
            Icons.celebration_rounded,
            size: 40,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Welcome to Property Pulse!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            children: [
              _CompletionBullet(
                icon: Icons.search_rounded,
                text: 'Browse thousands of properties',
              ),
              const SizedBox(height: 10),
              _CompletionBullet(
                icon: Icons.bookmark_outline_rounded,
                text: 'Save your favourite listings',
              ),
              const SizedBox(height: 10),
              _CompletionBullet(
                icon: Icons.chat_rounded,
                text: 'Message hosts and agents',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletionBullet extends StatelessWidget {
  const _CompletionBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.secondary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
