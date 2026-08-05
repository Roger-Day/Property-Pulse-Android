import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../models/property_model.dart';
import '../../../widgets/pp_widgets.dart';
import '../../../widgets/property_card.dart';

/// Pulse Finder (Phase 3 / 3.1) — one search result, paired with the
/// deterministic "why this property" bullets and match-quality label from
/// `PulseFinderExplainer`. Never fetches or computes anything itself —
/// purely a display of data already gathered.
///
/// Wraps the REAL [PropertyCard] (the exact widget Search/Map use) rather
/// than a hand-built image/title/price block, per the Phase 3.1 spec's
/// "do not redesign existing property cards" — the explanation section is
/// appended as sibling content below it, not nested inside a second card.
class PulseFinderResultCard extends StatelessWidget {
  const PulseFinderResultCard({
    super.key,
    required this.property,
    required this.reasons,
    this.label,
    this.onTap,
  });

  final PropertyModel property;
  final List<String> reasons;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            PropertyCard(property: property, onTap: onTap),
            if (label != null)
              Positioned(
                top: 10,
                left: 10,
                child: _MatchLabelChip(label: label!),
              ),
          ],
        ),
        if (reasons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PPCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Why this property',
                    style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...reasons.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_circle, size: 14, color: AppColors.success),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r, style: tt.bodySmall)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MatchLabelChip extends StatelessWidget {
  const _MatchLabelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
