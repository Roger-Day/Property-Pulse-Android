import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../theme/design_tokens.dart' hide PPCard;
import '../../../widgets/pp_widgets.dart';

/// Pulse Finder (Phase 3) — the suggested-prompt cards on the intro screen.
/// Tapping one starts the conversation with that prompt as the first user
/// message (see `PulseFinderConversationController.sendMessage`).
class PulseFinderPromptCards extends StatelessWidget {
  const PulseFinderPromptCards({super.key, required this.onSelected});

  final ValueChanged<String> onSelected;

  static const List<({IconData icon, String label, String prompt})> prompts = [
    (
      icon: Icons.villa_outlined,
      label: 'Find my first home',
      prompt: 'Help me find my first home',
    ),
    (
      icon: Icons.house_siding_outlined,
      label: 'Help me find an Airbnb',
      prompt: 'Help me find a good Airbnb property',
    ),
    (
      icon: Icons.trending_up,
      label: 'Find an investment property',
      prompt: 'Help me find a good investment property',
    ),
    (
      icon: Icons.moving_outlined,
      label: 'Help me relocate',
      prompt: 'Help me relocate to a new area',
    ),
    (
      icon: Icons.storefront_outlined,
      label: 'Find a commercial space',
      prompt: 'Help me find a commercial space',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: prompts.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PPCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(PPRadius.md),
              onTap: () => onSelected(p.prompt),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(p.icon, color: AppColors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        p.label,
                        style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
