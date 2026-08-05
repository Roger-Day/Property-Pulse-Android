import 'package:flutter/material.dart';

import '../../../constants/app_colors.dart';
import '../../../repositories/property_repository.dart';
import '../../../widgets/pp_widgets.dart';
import '../models/pulse_finder_intent.dart';

/// Pulse Finder (Phase 3.1 / 3.2) — "What I Understood" summary card.
///
/// Purely a deterministic rendering of the structured [PropertyFilter] the
/// AI already produced — no AI call, no invented text. Shown above the
/// curated recommendations so the user can confirm (or correct) what Pulse
/// Finder took away from the conversation before looking at results.
///
/// [intent] is shown as its own line, distinct from [propertyTypeRefinement]
/// — the property hierarchy this fixes: "Apartment" is a property type
/// NESTED beneath "Short Stay," never a substitute for it. Deliberately
/// never reads `filter.propertyType` directly for display: for a locked
/// shortStay intent that field holds the structural `'airbnb'` marker, not
/// a user-facing sub-type — see `PulseFinderSearchProfile`'s header.
class PulseFinderSummaryCard extends StatelessWidget {
  const PulseFinderSummaryCard({
    super.key,
    required this.filter,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEditSearch,
    required this.onRunSearchAgain,
    this.intent,
    this.propertyTypeRefinement,
  });

  final PropertyFilter filter;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEditSearch;
  final VoidCallback onRunSearchAgain;
  final PulseFinderIntent? intent;
  final String? propertyTypeRefinement;

  List<MapEntry<String, String>> _items() {
    final items = <MapEntry<String, String>>[];

    if (intent != null) {
      items.add(MapEntry('Category', intent!.displayLabel));
    }

    if (filter.minPrice != null || filter.maxPrice != null) {
      final currency = filter.currencyCode != null ? '${filter.currencyCode} ' : '';
      String budget;
      if (filter.minPrice != null && filter.maxPrice != null) {
        budget = '$currency${_money(filter.minPrice!)} – ${_money(filter.maxPrice!)}';
      } else if (filter.maxPrice != null) {
        budget = 'Up to $currency${_money(filter.maxPrice!)}';
      } else {
        budget = 'From $currency${_money(filter.minPrice!)}';
      }
      items.add(MapEntry('Budget', budget));
    }

    if (filter.city.isNotEmpty || filter.state.isNotEmpty) {
      final location = [filter.city, filter.state].where((s) => s.isNotEmpty).join(', ');
      items.add(MapEntry('Location', location));
    }

    if (propertyTypeRefinement != null && propertyTypeRefinement!.isNotEmpty) {
      items.add(MapEntry('Property Type', propertyTypeRefinement!));
    }

    if (filter.minBedrooms > 0) {
      items.add(MapEntry('Bedrooms', '${filter.minBedrooms}+'));
    }

    if (filter.minBathrooms > 0) {
      items.add(MapEntry('Bathrooms', '${filter.minBathrooms}+'));
    }

    if (filter.amenities.isNotEmpty) {
      items.add(MapEntry('Amenities', filter.amenities.join(', ')));
    }

    if (filter.query.trim().isNotEmpty) {
      items.add(MapEntry('Lifestyle & other requirements', filter.query.trim()));
    }

    return items;
  }

  String _money(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final items = _items();

    return PPCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: Row(
              children: [
                const Icon(Icons.fact_check_outlined, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What I Understood',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text(
                'No specific requirements captured yet.',
                style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
              )
            else
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(
                      style: tt.bodySmall?.copyWith(color: AppColors.textPrimary),
                      children: [
                        TextSpan(
                          text: '${item.key}: ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: item.value),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PPOutlinedButton(
                    label: 'Edit Search',
                    icon: Icons.edit_outlined,
                    onPressed: onEditSearch,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PPOutlinedButton(
                    label: 'Run Search Again',
                    icon: Icons.refresh,
                    onPressed: onRunSearchAgain,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
