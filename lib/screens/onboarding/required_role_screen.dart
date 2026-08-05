import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../repositories/user_profile_repository.dart';
import 'airbnb_host_onboarding_screen.dart';

/// Mandatory, one-question, non-dismissible role picker shown once per
/// device right after sign-in — mirrors iOS `RequiredUserTypeOnboardingView`.
///
/// Distinct from the optional 9-step [OnboardingScreen] flow (which runs
/// pre-auth and never actually writes a role to Firestore) — this is the
/// screen that sets the account's real `role` field, gating navigation
/// throughout the rest of the app.
class RequiredRoleScreen extends StatefulWidget {
  const RequiredRoleScreen({super.key});

  @override
  State<RequiredRoleScreen> createState() => _RequiredRoleScreenState();
}

class _RequiredRoleScreenState extends State<RequiredRoleScreen> {
  bool _saving = false;

  Future<void> _select(String role) async {
    if (_saving) return;
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      await context
          .read<UserProfileRepository>()
          .setInitialRole(userId: uid, role: role);
    } catch (_) {
      // Non-fatal — mirrors iOS's silent retry-on-next-activation approach.
      // The device-local flag below still advances the user past this
      // screen; the role write will be retried by the user reopening
      // profile settings if it didn't land.
    }
    if (!mounted) return;
    await context.read<OnboardingProvider>().markRequiredRoleSelected();
    if (!mounted) return;

    if (role == 'airbnbHost') {
      // Mirrors iOS's dedicated 5-step host setup — reachable right after
      // choosing this role, since nothing else in the app currently opens
      // it. The router redirect will send them to /home once this pops.
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AirbnbHostOnboardingScreen(),
      ));
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (context.mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mandatory: user must choose. Mirrors iOS
      // `.interactiveDismissDisabled(true)`.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Welcome'),
          automaticallyImplyLeading: false,
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How will you use Property Pulse?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pick one option to personalize your experience. You can switch later.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 20),
                _OptionCard(
                  title: "I'm looking for a property",
                  subtitle: 'Browse, save, and message — always free',
                  icon: Icons.search_rounded,
                  tint: Colors.green,
                  onTap: () => _select('seeker'),
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                _OptionCard(
                  title: "I'm listing my own property",
                  subtitle: 'Designed for individual homeowners',
                  icon: Icons.house_rounded,
                  tint: AppColors.primary,
                  onTap: () => _select('owner'),
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                _OptionCard(
                  title: 'I list properties for clients',
                  subtitle: 'Built for managing multiple listings',
                  icon: Icons.people_alt_rounded,
                  tint: Colors.purple,
                  onTap: () => _select('realtor'),
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                _OptionCard(
                  title: "I'm a developer",
                  subtitle: 'Create and manage new development builds',
                  icon: Icons.apartment_rounded,
                  tint: Colors.indigo,
                  onTap: () => _select('developer'),
                  enabled: !_saving,
                ),
                const SizedBox(height: 12),
                _OptionCard(
                  title: 'I host short-stay properties',
                  subtitle: 'List and manage Airbnb-style short-stay rentals',
                  icon: Icons.cottage_rounded,
                  tint: const Color(0xFFED3D45),
                  onTap: () => _select('airbnbHost'),
                  enabled: !_saving,
                ),
                const SizedBox(height: 20),
                Text(
                  'Browsing & messaging stay free.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  "You won't be asked to verify anything during signup.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
