import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../repositories/user_profile_repository.dart';
import 'analytics_shared.dart';

/// My Analytics — the canonical Listings Analytics experience.
/// Mirrors iOS `UserAnalyticsView` section-for-section:
///   1. Your Listings Performance (2×2 summary)
///   2. Week / Month / Quarter / Year time-range picker
///   3. Your Listings Overview
///   4. Top Performing Property
///   5. All Your Properties
///   6. Performance Insights
///
/// Market/Trends live in Market Intelligence; engagement lives in
/// Profile → Activity.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _TimeRange { week, month, quarter, year }

extension on _TimeRange {
  String get label => switch (this) {
        _TimeRange.week => 'Week',
        _TimeRange.month => 'Month',
        _TimeRange.quarter => 'Quarter',
        _TimeRange.year => 'Year',
      };
}

/// Per-listing analytics — mirrors iOS `UserPropertyAnalytics`.
class _PropertyAnalytics {
  const _PropertyAnalytics({
    required this.propertyId,
    required this.title,
    required this.totalViews,
    required this.totalInquiries,
    required this.averageViewTimeMin,
    required this.daysListed,
  });

  final String propertyId;
  final String title;
  final int totalViews;
  final int totalInquiries;
  final double averageViewTimeMin;
  final int daysListed;

  double get conversionRate =>
      totalViews == 0 ? 0 : (totalInquiries / totalViews) * 100;
}

/// Aggregate summary — mirrors iOS `UserAnalyticsSummary`.
class _Summary {
  const _Summary({
    required this.totalListedProperties,
    required this.totalViews,
    required this.totalInquiries,
    required this.averageViewTimeMin,
    required this.averageDaysOnMarket,
  });

  final int totalListedProperties;
  final int totalViews;
  final int totalInquiries;
  final double averageViewTimeMin;
  final double averageDaysOnMarket;

  double get overallConversionRate =>
      totalViews == 0 ? 0 : (totalInquiries / totalViews) * 100;
}

class _AnalyticsData {
  const _AnalyticsData({required this.summary, required this.properties});
  final _Summary summary;
  final List<_PropertyAnalytics> properties;

  // Matches iOS `topPerformingUserProperty` (`userPropertyAnalyticsList.max`):
  // picks the highest-view listing unconditionally, even at 0 views.
  _PropertyAnalytics? get topPerforming {
    if (properties.isEmpty) return null;
    final sorted = [...properties]
      ..sort((a, b) => b.totalViews.compareTo(a.totalViews));
    return sorted.first;
  }
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Future<_AnalyticsData>? _future;
  _TimeRange _range = _TimeRange.month; // iOS default: .month

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _refresh() {
    HapticFeedback.lightImpact();
    setState(() => _future = _load());
  }

  Future<_AnalyticsData> _load() async {
    final db = FirebaseFirestore.instance;
    final repo = context.read<UserProfileRepository>();
    final listings = await repo.getMyListings(widget.userId);

    // Per-listing analytics from property_analytics/{propertyId} — same
    // collection iOS reads in AnalyticsViewModel / RealtorAnalyticsGateView.
    final analyticsById = <String, Map<String, dynamic>>{};
    final ids = listings.map((e) => e.id).toList();
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, min(i + 30, ids.length));
      try {
        final snap = await db
            .collection(AppConstants.propertyAnalyticsCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          analyticsById[d.id] = d.data();
        }
      } catch (_) {}
    }

    final perProperty = <_PropertyAnalytics>[];
    var totalViews = 0;
    var totalInquiries = 0;
    var totalViewTimeMin = 0.0;
    var viewTimeCount = 0;
    var totalDays = 0;

    for (final p in listings) {
      // ignore: avoid_print
      print('[DEBUG_ANALYTICS] id=${p.id} title=${p.title} createdAt=${p.createdAt}');
      final a = analyticsById[p.id] ?? const <String, dynamic>{};
      final views = (a['views'] as num?)?.toInt() ?? 0;
      final inquiries = (a['inquiries'] as num?)?.toInt() ?? 0;
      // Stored in seconds — displayed in minutes (iOS "%.1f min").
      final avgSecs = (a['averageTimeOnPage'] as num?)?.toDouble() ?? 0;
      final avgMin = avgSecs / 60.0;
      final days = p.createdAt != null
          ? DateTime.now().difference(p.createdAt!).inDays
          : 0;
      // ignore: avoid_print
      print('[DEBUG_ANALYTICS] days=$days now=${DateTime.now()}');

      totalViews += views;
      totalInquiries += inquiries;
      if (avgMin > 0) {
        totalViewTimeMin += avgMin;
        viewTimeCount++;
      }
      totalDays += days;

      perProperty.add(_PropertyAnalytics(
        propertyId: p.id,
        title: p.title,
        totalViews: views,
        totalInquiries: inquiries,
        averageViewTimeMin: avgMin,
        daysListed: days,
      ));
    }

    final result = _AnalyticsData(
      summary: _Summary(
        totalListedProperties: listings.length,
        totalViews: totalViews,
        totalInquiries: totalInquiries,
        averageViewTimeMin:
            viewTimeCount == 0 ? 0 : totalViewTimeMin / viewTimeCount,
        averageDaysOnMarket:
            listings.isEmpty ? 0 : totalDays / listings.length,
      ),
      properties: perProperty,
    );
    // ignore: avoid_print
    print('[DEBUG_ANALYTICS] result.summary.averageDaysOnMarket=${result.summary.averageDaysOnMarket} totalDays=$totalDays listingsLen=${listings.length}');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Analytics'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        actions: [
          // iOS: arrow.clockwise refresh button (topBarTrailing)
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            // iOS: ProgressView("Loading your analytics...")
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading your analytics...'),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final d = snap.data!;
          final top = d.topPerforming;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── 1. Your Listings Performance ───────────────────────
                _SummaryCard(summary: d.summary),
                const SizedBox(height: 16),

                // ── 2. Time range picker (Week/Month/Quarter/Year) ─────
                _TimeRangePicker(
                  selected: _range,
                  onChanged: (r) => setState(() => _range = r),
                ),
                const SizedBox(height: 16),

                // ── 3. Your Listings Overview ──────────────────────────
                _ListingsOverviewCard(summary: d.summary),
                const SizedBox(height: 16),

                // ── 4. Top Performing Property ─────────────────────────
                if (top != null) ...[
                  _TopPerformingCard(property: top),
                  const SizedBox(height: 16),
                ],

                // ── 5. All Your Properties ─────────────────────────────
                _AllPropertiesCard(properties: d.properties),
                const SizedBox(height: 16),

                // ── 6. Performance Insights ────────────────────────────
                _InsightsCard(summary: d.summary),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── 1. Summary card — iOS UserAnalyticsSummaryCard ──────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Listings Performance',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.totalListedProperties} properties listed',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.bar_chart_rounded,
                  color: Colors.blue, size: 28),
            ],
          ),
          const SizedBox(height: 16),
          AnalyticsMetricGrid([
            AnalyticsMetricTile(
              icon: Icons.visibility,
              color: Colors.blue,
              label: 'Total Views',
              value: '${summary.totalViews}',
            ),
            AnalyticsMetricTile(
              icon: Icons.access_time_filled,
              color: Colors.green,
              label: 'Avg View Time',
              value: '${summary.averageViewTimeMin.toStringAsFixed(1)} min',
            ),
            AnalyticsMetricTile(
              icon: Icons.message,
              color: Colors.orange,
              label: 'Total Inquiries',
              value: '${summary.totalInquiries}',
            ),
            AnalyticsMetricTile(
              icon: Icons.trending_up_rounded,
              color: Colors.purple,
              label: 'Conversion Rate',
              value: '${summary.overallConversionRate.toStringAsFixed(1)}%',
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── 2. Time range picker — iOS TimeRangePicker ───────────────────────────────

class _TimeRangePicker extends StatelessWidget {
  const _TimeRangePicker({required this.selected, required this.onChanged});
  final _TimeRange selected;
  final ValueChanged<_TimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_TimeRange>(
      segments: _TimeRange.values
          .map((r) => ButtonSegment(value: r, label: Text(r.label)))
          .toList(),
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

// ─── 3. Listings overview — iOS UserListingsMetricsSection ────────────────────

class _ListingsOverviewCard extends StatelessWidget {
  const _ListingsOverviewCard({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Listings Overview',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          AnalyticsMetricGrid([
            AnalyticsMetricTile(
              icon: Icons.home,
              color: Colors.blue,
              label: 'Listed Properties',
              value: '${summary.totalListedProperties}',
            ),
            AnalyticsMetricTile(
              icon: Icons.calendar_today,
              color: Colors.green,
              label: 'Avg Days Listed',
              value: summary.averageDaysOnMarket.toStringAsFixed(0),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── 4. Top performing — iOS TopPerformingPropertyCard ────────────────────────

class _TopPerformingCard extends StatelessWidget {
  const _TopPerformingCard({required this.property});
  final _PropertyAnalytics property;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Performing Property',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      property.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _TopStat(
                value: '${property.totalViews}',
                label: 'Views',
                color: Colors.blue,
              ),
              _TopStat(
                value:
                    '${property.averageViewTimeMin.toStringAsFixed(1)} min',
                label: 'Avg Time',
                color: Colors.green,
              ),
              _TopStat(
                value: '${property.totalInquiries}',
                label: 'Inquiries',
                color: Colors.orange,
              ),
              _TopStat(
                value: '${property.conversionRate.toStringAsFixed(1)}%',
                label: 'Conversion',
                color: Colors.purple,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopStat extends StatelessWidget {
  const _TopStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
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

// ─── 5. All properties — iOS UserPropertiesAnalyticsList ──────────────────────

class _AllPropertiesCard extends StatelessWidget {
  const _AllPropertiesCard({required this.properties});
  final List<_PropertyAnalytics> properties;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'All Your Properties',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (properties.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'No listings yet — create your first listing to start tracking performance.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ] else
            ...properties.map((p) => Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Listed ${p.daysListed} days ago',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _TopStat(
                            value: '${p.totalViews}',
                            label: 'Views',
                            color: Colors.blue,
                          ),
                          _TopStat(
                            value:
                                '${p.averageViewTimeMin.toStringAsFixed(1)} min',
                            label: 'Avg Time',
                            color: Colors.green,
                          ),
                          _TopStat(
                            value: '${p.totalInquiries}',
                            label: 'Inquiries',
                            color: Colors.orange,
                          ),
                          _TopStat(
                            value: '${p.conversionRate.toStringAsFixed(1)}%',
                            label: 'Conversion',
                            color: Colors.purple,
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ─── 6. Insights — iOS PerformanceInsightsCard ────────────────────────────────

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Performance Insights',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _InsightRow(
            icon: Icons.lightbulb,
            color: Colors.amber,
            text:
                'Your properties are getting ${summary.totalViews} total views',
          ),
          const SizedBox(height: 10),
          _InsightRow(
            icon: Icons.access_time_filled,
            color: Colors.green,
            text:
                'Users spend an average of ${summary.averageViewTimeMin.toStringAsFixed(1)} minutes viewing your listings',
          ),
          if (summary.overallConversionRate > 0) ...[
            const SizedBox(height: 10),
            _InsightRow(
              icon: Icons.trending_up_rounded,
              color: Colors.purple,
              text:
                  '${summary.overallConversionRate.toStringAsFixed(1)}% of viewers send an inquiry',
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}
