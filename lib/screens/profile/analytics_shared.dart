import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

/// Shared building blocks for the analytics surfaces:
///  • My Analytics (analytics_screen.dart — iOS UserAnalyticsView mirror)
///  • Market Intelligence (market_intelligence_screen.dart)
///  • Your Activity (activity_screen.dart)

class AnalyticsSectionHeader extends StatelessWidget {
  const AnalyticsSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4),
    );
  }
}

class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class AnalyticsMetricTile extends StatelessWidget {
  const AnalyticsMetricTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class AnalyticsMetricGrid extends StatelessWidget {
  const AnalyticsMetricGrid(this.tiles, {super.key});
  final List<AnalyticsMetricTile> tiles;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: tiles,
    );
  }
}

class AnalyticsStatRow extends StatelessWidget {
  const AnalyticsStatRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class EngagementCard extends StatelessWidget {
  const EngagementCard({
    super.key,
    required this.propertyViews,
    required this.savedCount,
    required this.likedCount,
    required this.messages,
    required this.appOpens,
    this.compact = false,
  });

  final int propertyViews;
  final int savedCount;
  final int likedCount;
  final int messages;
  final int appOpens;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      AnalyticsStatRow('Properties Viewed', '$propertyViews'),
      AnalyticsStatRow('Saved Properties', '$savedCount'),
      AnalyticsStatRow('Liked Properties', '$likedCount'),
      if (!compact) ...[
        AnalyticsStatRow('Messages Sent', '$messages'),
        AnalyticsStatRow('App Opens', '$appOpens'),
      ],
    ];

    return AnalyticsCard(
      child: Column(children: rows),
    );
  }
}
