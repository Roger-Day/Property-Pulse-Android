import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import 'profile_subscreen_widgets.dart';

class ProfilePlaceholderScreen extends StatelessWidget {
  const ProfilePlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.primaryLabel,
    this.onPrimaryTap,
  });

  final String title;
  final String subtitle;
  final String? primaryLabel;
  final VoidCallback? onPrimaryTap;

  @override
  Widget build(BuildContext context) {
    return ProfileGroupedScaffold(
      title: title,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          ProfileSectionHeader(title),
          const SizedBox(height: 4),
          ProfileGroupedCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                ),
                if (primaryLabel != null && onPrimaryTap != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onPrimaryTap,
                    child: Text(primaryLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
