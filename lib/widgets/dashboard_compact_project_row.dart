import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../models/project_model.dart';

/// iOS `CompactProjectRowView` — 40×40 image, subheadline title, caption secondary.
class DashboardCompactProjectRow extends StatelessWidget {
  const DashboardCompactProjectRow({
    super.key,
    required this.project,
    required this.onTap,
  });

  final ProjectModel project;
  final VoidCallback onTap;

  String get _priceLine {
    if (project.startingPrice == null) return 'Pricing TBA';
    final code = project.startingPriceCurrencyCode.trim().isEmpty
        ? 'USD'
        : project.startingPriceCurrencyCode;
    return NumberFormat.simpleCurrency(name: code).format(project.startingPrice);
  }

  String get _secondaryLine {
    final loc = project.location.trim();
    return loc.isEmpty ? _priceLine : loc;
  }

  @override
  Widget build(BuildContext context) {
    final img = project.primaryImageUrl;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: img != null && img.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          memCacheWidth: 80,
                          imageBuilder: (ctx, provider) => Semantics(
                            label: 'Project thumbnail',
                            child: Image(image: provider, fit: BoxFit.cover),
                          ),
                        )
                      : ColoredBox(
                          color: AppColors.surfaceVariant,
                          child: Icon(
                            Icons.apartment_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _secondaryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
