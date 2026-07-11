import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../models/project_model.dart';
import '../utils/responsive.dart';

/// Home horizontal strip — parity with iOS `NewDevelopmentsSection`.
class NewDevelopmentsStrip extends StatelessWidget {
  const NewDevelopmentsStrip({
    super.key,
    required this.projects,
    required this.onSeeAll,
  });

  final List<ProjectModel> projects;
  final VoidCallback onSeeAll;

  /// Matches the property carousel: ~85% of screen on phones (two-column
  /// body needs room; still peeks the next card), fixed on tablets.
  static double cardWidthFor(BuildContext context) => Responsive.isWide(context)
      ? 380
      : MediaQuery.sizeOf(context).width * 0.85;

  @override
  Widget build(BuildContext context) {
    const horizontalPad = 20.0;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Developments',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Developer-led projects and new builds',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onSeeAll,
                  child: Text(
                    'See all',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: horizontalPad),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.domain_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No new developments yet. Check back soon.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: _kStripCardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(horizontalPad, 4, horizontalPad, 4),
                itemCount: projects.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (context, i) {
                  final p = projects[i];
                  final w = cardWidthFor(context);
                  return SizedBox(
                    width: w,
                    child: NewDevelopmentHomeCard(
                      project: p,
                      onTap: () =>
                          context.push('/development/${p.firestoreDocumentId}'),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Fixed vertical size so horizontal ListView gets a bounded height.
/// Matches PropertiesSection's home-card row height (two-column body).
const double _kStripCardHeight = 400;

/// Single card — mirrors iOS `NewDevelopmentCard` / Android `HomePropertyCard`
/// two-column layout: full-bleed 200dp image with status overlay, then
/// LEFT (title/location/developer) │ divider │ RIGHT (price/specs).
class NewDevelopmentHomeCard extends StatelessWidget {
  const NewDevelopmentHomeCard({
    super.key,
    required this.project,
    required this.onTap,
  });

  final ProjectModel project;
  final VoidCallback onTap;

  static const double _imageHeight = 200;
  static const double _radius = 20;

  String get _developerLine {
    if (project.developerName.trim().isNotEmpty) {
      return project.developerName.trim();
    }
    if (project.developerId.trim().isNotEmpty) return project.developerId.trim();
    return '—';
  }

  String get _priceLine {
    if (project.startingPrice != null) {
      final fmt = NumberFormat.simpleCurrency(
        name: project.startingPriceCurrencyCode,
      );
      return 'From ${fmt.format(project.startingPrice)}';
    }
    return 'Pricing TBA';
  }

  /// Bedroom range across unit types, e.g. "1–3" or "2" when uniform.
  String? get _bedroomRange {
    final counts = project.unitTypes
        .map((u) => u.bedrooms)
        .where((b) => b > 0)
        .toList();
    if (counts.isEmpty) return null;
    final lo = counts.reduce((a, b) => a < b ? a : b);
    final hi = counts.reduce((a, b) => a > b ? a : b);
    return lo == hi ? '$lo' : '$lo–$hi';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLabel = project.statusRaw.trim().isEmpty
        ? 'Pre-construction'
        : projectStatusDisplayLabel(project.statusRaw);
    final capsule = _statusCapsuleColor(project.statusRaw);

    final name =
        project.projectName.trim().isEmpty ? 'Development' : project.projectName;
    final loc = project.location.trim().isEmpty ? '—' : project.location.trim();
    final bedroomRange = _bedroomRange;

    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Image + status badge overlay (matches HomePropertyCard) ──
            SizedBox(
              height: _imageHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: scheme.surfaceContainerHighest),
                  if (project.primaryImageUrl != null)
                    CachedNetworkImage(
                      imageUrl: project.primaryImageUrl!,
                      fit: BoxFit.cover,
                      memCacheHeight: 400,
                      imageBuilder: (ctx, provider) => Semantics(
                        label: 'Development photo for ${project.projectName}',
                        child: Image(image: provider, fit: BoxFit.cover),
                      ),
                      placeholder: (_, __) => const _HeroPlaceholder(),
                      errorWidget: (_, __, ___) => const _HeroPlaceholder(),
                    )
                  else
                    const _HeroPlaceholder(),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: capsule,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Text info — two-column layout (matches HomePropertyCard) ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── LEFT column ─────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            loc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 8),
                          // Developer row — icon avatar (no photo field on
                          // projects), mirrors the lister avatar row.
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.domain_rounded,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Developer',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      _developerLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Divider ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        width: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),

                    // ── RIGHT column: price + specs ─────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _priceLine,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (project.totalUnits != null &&
                              project.totalUnits! > 0) ...[
                            _DevSpecRow(
                              icon: Icons.domain_rounded,
                              value: '${project.totalUnits}',
                              label: 'Units',
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (bedroomRange != null)
                            _DevSpecRow(
                              icon: Icons.bed_rounded,
                              value: bedroomRange,
                              label: 'Beds',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Matches Android property card's `_CardSpecRow` styling exactly.
class _DevSpecRow extends StatelessWidget {
  const _DevSpecRow({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

Color _statusCapsuleColor(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  if (s == 'planning') return Colors.blue;
  if (s == 'pre-construction' ||
      s == 'pre-sale' ||
      s.contains('pre')) {
    return Colors.purple;
  }
  if (s == 'under-construction' || s.contains('under')) {
    return Colors.orange;
  }
  if (s == 'completed') return Colors.green;
  return Colors.purple;
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.domain_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
