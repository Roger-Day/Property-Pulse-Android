import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import 'profile_subscreen_widgets.dart';

/// Support, FAQ, About, and Data Export — mirrors iOS `SupportView`,
/// `HelpFAQView`, `ContactSupportView`, `AboutView`, `DataExportView`.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProfileGroupedScaffold(
      title: 'Help & Support',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          const ProfileSheetHeroHeader(
            icon: Icons.support_agent_rounded,
            iconColor: AppColors.primary,
            title: 'How can we help?',
            subtitle:
                'Find answers below, preview & share your data export, or email support.',
          ),
          // ── FAQ ──────────────────────────────────────────────────────────
          const ProfileSectionHeader('Frequently Asked Questions'),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(0),
            child: Column(
              children: _faqs.map((faq) => _FaqTile(faq: faq)).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // ── Contact Support ───────────────────────────────────────────────
          const ProfileSectionHeader('Contact Support'),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Our team is here to help Monday – Friday, 9 am – 6 pm.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _launch(
                    'mailto:${AppConstants.supportEmail}?subject=Property Pulse Support',
                  ),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email support'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Data Export ───────────────────────────────────────────────────
          const ProfileSectionHeader('Your Data'),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview saved properties, messages, and appointments, then '
                  'share a CSV file — same flow as on iOS.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 16),
                ProfilePrimaryButton(
                  label: 'Open data export',
                  icon: Icons.download_rounded,
                  onPressed: () => context.push('/profile/data-export'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── About ─────────────────────────────────────────────────────────
          const ProfileSectionHeader('About'),
          const SizedBox(height: 8),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(0),
            child: Column(
              children: [
                _LinkTile(
                  icon: Icons.description_outlined,
                  label: 'Terms of Service',
                  onTap: () => _launch(AppConstants.termsOfServiceUrl),
                ),
                const Divider(height: 1, indent: 56),
                _LinkTile(
                  icon: Icons.lock_outline,
                  label: 'Privacy Policy',
                  onTap: () => _launch(AppConstants.privacyPolicyUrl),
                ),
                const Divider(height: 1, indent: 56),
                const _LinkTile(
                  icon: Icons.info_outline,
                  label: 'App version',
                  trailing: '1.0.0',
                  onTap: null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAQ data & tiles
// ─────────────────────────────────────────────────────────────────────────────

class _Faq {
  const _Faq(this.question, this.answer);
  final String question;
  final String answer;
}

const _faqs = [
  _Faq(
    'How do I save a property?',
    'Tap the heart icon on any listing. Saved properties appear in your Saved tab.',
  ),
  _Faq(
    'How do I message a host?',
    'Open a property listing and tap "Message". You need a verified account to send messages.',
  ),
  _Faq(
    'How do I book a stay?',
    'On a rental listing, tap "Book", choose your dates, and complete payment via Stripe. Your booking will appear in My Stays.',
  ),
  _Faq(
    'How do I become a verified agent?',
    'Go to Profile → Identity Verification and upload a government-issued ID. Verification is typically reviewed within 48 hours.',
  ),
  _Faq(
    'What is Premium?',
    'Premium removes listing limits, enables boost slots, and unlocks analytics. Subscribe monthly or yearly via Profile → Premium.',
  ),
  _Faq(
    'How do I delete my account?',
    'Email us at ${AppConstants.supportEmail} with your request. We will delete all your data within 30 days.',
  ),
];

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.faq});
  final _Faq faq;
  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.faq.question,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              widget.faq.answer,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ),
        const Divider(height: 1, indent: 16),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: trailing != null
          ? Text(
              trailing!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            )
          : (onTap != null
              ? const Icon(Icons.chevron_right, color: AppColors.textTertiary)
              : null),
      onTap: onTap,
    );
  }
}
