import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../models/project_model.dart';

/// Pixel-aligned with iOS `ProjectCardView` (image 200pt, corner 16, padding 14).
class ProjectListingCard extends StatelessWidget {
  const ProjectListingCard({
    super.key,
    required this.project,
    required this.onTap,
  });

  final ProjectModel project;
  final VoidCallback onTap;

  static const double _imageHeight = 200;
  static const double _radius = 16;
  static const double _contentPadding = 14;

  String get _developerDisplayName {
    if (project.developerName.trim().isNotEmpty) {
      return project.developerName.trim();
    }
    return project.developerId.trim().isEmpty ? '—' : project.developerId.trim();
  }

  String get _priceLine {
    if (project.startingPrice != null) {
      final fmt = NumberFormat.simpleCurrency(
        name: project.startingPriceCurrencyCode.trim().isEmpty
            ? 'USD'
            : project.startingPriceCurrencyCode,
      );
      return 'From ${fmt.format(project.startingPrice)}';
    }
    return 'Pricing TBA';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = project.projectName.trim().isEmpty
        ? 'Development'
        : project.projectName.trim();
    final loc = project.location.trim().isEmpty ? '—' : project.location.trim();
    final pill = projectStatusPillStyle(project.statusRaw);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_radius),
                ),
                child: SizedBox(
                  height: _imageHeight,
                  child: Stack(
                    alignment: Alignment.bottomLeft,
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.grey.withValues(alpha: 0.15)),
                      if (project.primaryImageUrl != null &&
                          project.primaryImageUrl!.trim().isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: project.primaryImageUrl!.trim(),
                          fit: BoxFit.cover,
                          memCacheHeight: 400,
                          imageBuilder: (ctx, provider) => Semantics(
                            label: 'Photo of ${project.projectName}',
                            child: Image(image: provider, fit: BoxFit.cover),
                          ),
                          placeholder: (_, __) => const _ImgPlaceholder(),
                          errorWidget: (_, __, ___) => const _ImgPlaceholder(),
                        )
                      else
                        const _ImgPlaceholder(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(_contentPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StatusCapsule(
                                  label: pill.label,
                                  background: pill.background,
                                ),
                                if (project.isExpired) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Expired',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              loc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(_contentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _priceLine,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.apartment_rounded,
                          size: 24,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Developer',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _developerDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({
    required this.label,
    required this.background,
  });

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.grey.withValues(alpha: 0.15),
      child: Center(
        child: Icon(
          Icons.apartment_rounded,
          size: 44,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// iOS `ProjectStatusPill` label + fill — driven by stored `status` string.
({String label, Color background}) projectStatusPillStyle(String? raw) {
  final s = raw?.trim().toLowerCase() ?? '';
  String label;
  Color bg;
  switch (s) {
    case 'planning':
      label = 'Planning';
      bg = Colors.blue;
      break;
    case 'pre-construction':
    case 'pre-sale':
      label = 'Pre-construction';
      bg = Colors.purple;
      break;
    case 'under-construction':
      label = 'Under Construction';
      bg = Colors.orange;
      break;
    case 'completed':
      label = 'Completed';
      bg = Colors.green;
      break;
    default:
      label = projectStatusDisplayLabel(raw);
      bg = Colors.purple;
  }
  return (label: label, background: bg);
}
