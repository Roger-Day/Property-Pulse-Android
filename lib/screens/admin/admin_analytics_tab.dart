import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../models/admin_analytics_deep.dart';
import '../../repositories/admin_repository.dart';
import '../../utils/responsive.dart';

/// Matches iOS `AdminAnalyticsView`: overview metrics, weekly bar trends, geographic bars.
class AdminAnalyticsTab extends StatefulWidget {
  const AdminAnalyticsTab({super.key});

  @override
  State<AdminAnalyticsTab> createState() => _AdminAnalyticsTabState();
}

class _AdminAnalyticsTabState extends State<AdminAnalyticsTab> {
  Future<AdminAnalyticsDeep>? _future;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
    });
  }

  Future<void> _reload() async {
    final admin = context.read<AdminRepository>();
    setState(() {
      _future = admin.fetchAdminAnalyticsDeep();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminAnalyticsDeep>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data;
        if (data == null || data.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(data?.errorMessage ?? snap.error.toString()),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: Responsive.hPadding(context, top: 12, bottom: 32),
            children: [
              Text(
                'Overview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final w = (c.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: w,
                        child: _MetricTile(
                          title: 'Total users',
                          value: '${data.totalUsers}',
                          icon: Icons.people_outline,
                          color: const Color(0xFF007AFF),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _MetricTile(
                          title: 'Total properties',
                          value: '${data.totalProperties}',
                          icon: Icons.apartment_outlined,
                          color: const Color(0xFFFF9500),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _MetricTile(
                          title: 'Active listings',
                          value: '${data.activeListings}',
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF34C759),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _MetricTile(
                          title: 'Conversations',
                          value: '${data.totalConversations}',
                          icon: Icons.chat_bubble_outline,
                          color: const Color(0xFFAF52DE),
                        ),
                      ),
                      SizedBox(
                        width: w,
                        child: _MetricTile(
                          title: 'Open moderation',
                          value: '${data.openModerationReports}',
                          icon: Icons.shield_outlined,
                          color: const Color(0xFFFF3B30),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Weekly trends',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              _WeeklyTrendCard(
                title: 'User registrations',
                points: data.weeklyUserData,
                growth: data.userGrowthPercentage,
                color: const Color(0xFF007AFF),
              ),
              const SizedBox(height: 12),
              _WeeklyTrendCard(
                title: 'New listings',
                points: data.weeklyPropertyData,
                growth: data.propertyGrowthPercentage,
                color: const Color(0xFFFF9500),
              ),
              const SizedBox(height: 24),
              Text(
                'Geographic distribution',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              _GeoCard(title: 'Properties by state', points: data.propertyByState),
              const SizedBox(height: 12),
              if (data.userByState.isNotEmpty)
                _GeoCard(title: 'Users by state', points: data.userByState),
              const SizedBox(height: 16),
              Text(
                'Loads full collections client-side (same approach as iOS). Large databases may be slow.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyTrendCard extends StatelessWidget {
  const _WeeklyTrendCard({
    required this.title,
    required this.points,
    required this.growth,
    required this.color,
  });

  final String title;
  final List<WeeklyDataPoint> points;
  final double growth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    var maxC = 0;
    for (final p in points) {
      if (p.count > maxC) maxC = p.count;
    }
    final maxH = 60.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (growth >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        growth >= 0 ? Icons.north_east : Icons.south_east,
                        size: 14,
                        color: growth >= 0 ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${growth.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: growth >= 0 ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (points.isEmpty)
              Text('No data', style: Theme.of(context).textTheme.bodySmall)
            else
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final p in points)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                '${p.count}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                height: maxC <= 0
                                    ? 4.0
                                    : (p.count / maxC * maxH).clamp(4.0, maxH),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.weekLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontSize: 10,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GeoCard extends StatelessWidget {
  const _GeoCard({required this.title, required this.points});

  final String title;
  final List<StateDataPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$title — no state data', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    var maxC = 0;
    for (final p in points) {
      if (p.count > maxC) maxC = p.count;
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(p.state),
                        Text('${p.count} (${p.percentage.toStringAsFixed(0)}%)'),
                      ],
                    ),
                    LinearProgressIndicator(
                      value: maxC <= 0 ? 0 : p.count / maxC,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
