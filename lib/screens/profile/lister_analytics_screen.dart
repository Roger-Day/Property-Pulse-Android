import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../repositories/user_profile_repository.dart';

/// Lister analytics dashboard with iOS-style parity sections.
class ListerAnalyticsScreen extends StatefulWidget {
  const ListerAnalyticsScreen({super.key});

  @override
  State<ListerAnalyticsScreen> createState() => _ListerAnalyticsScreenState();
}

class _ListerAnalyticsScreenState extends State<ListerAnalyticsScreen> {
  Future<_ListerAnalyticsData>? _future;
  _AnalyticsTimeRange _selectedRange = _AnalyticsTimeRange.month;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_ListerAnalyticsData> _load() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const _ListerAnalyticsData.empty();
    }
    final repo = context.read<UserProfileRepository>();
    final listings = await repo.getMyListings(uid);
    if (listings.isEmpty) {
      return const _ListerAnalyticsData.empty();
    }

    final ids = listings.map((e) => e.id).toList();
    final analyticsById = <String, _PropertyAnalyticsRow>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, min(i + 30, ids.length));
      final snap = await FirebaseFirestore.instance
          .collection(AppConstants.propertyAnalyticsCollection)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        int intVal(String key) => (m[key] as num?)?.toInt() ?? 0;
        double doubleVal(String key) => (m[key] as num?)?.toDouble() ?? 0;
        final views = intVal('views');
        // iOS writes `totalViewTime` in seconds; compute per-view average in minutes.
        final totalViewTimeSecs = doubleVal('totalViewTime');
        final avgTimeMins = views > 0 ? (totalViewTimeSecs / views / 60.0) : 0.0;
        analyticsById[d.id] = _PropertyAnalyticsRow(
          views: views,
          inquiries: intVal('inquiries'),
          savedCount: intVal('savedCount'),
          likedCount: intVal('likedCount'),
          averageTimeMins: avgTimeMins,
        );
      }
    }

    var totalViews = 0;
    var totalInquiries = 0;
    var weightedTimeSum = 0.0;
    final rows = <_ListingRow>[];

    for (final p in listings) {
      final a = analyticsById[p.id] ?? const _PropertyAnalyticsRow.zero();
      totalViews += a.views;
      totalInquiries += a.inquiries;
      // avgTimeMins already computed correctly from totalViewTime/views/60
      weightedTimeSum += a.averageTimeMins * a.views;
      rows.add(
        _ListingRow(
          id: p.id,
          title: p.title,
          views: a.views,
          avgTime: a.averageTimeMins,
          inquiries: a.inquiries,
          saved: a.savedCount,
          liked: a.likedCount,
          daysListed: p.createdAt == null
              ? 0
              : DateTime.now().difference(p.createdAt!).inDays.clamp(0, 9999),
        ),
      );
    }
    rows.sort((a, b) => b.views.compareTo(a.views));

    final avgViewTime =
        totalViews == 0 ? 0.0 : weightedTimeSum / totalViews;
    final conversionRate =
        totalViews == 0 ? 0.0 : (totalInquiries / totalViews) * 100;
    final avgDaysListed = rows.isEmpty
        ? 0.0
        : rows.map((e) => e.daysListed).reduce((a, b) => a + b) / rows.length;
    final top = rows.isEmpty ? null : rows.first;

    return _ListerAnalyticsData(
      totalViews: totalViews,
      avgViewTime: avgViewTime,
      totalInquiries: totalInquiries,
      conversionRate: conversionRate,
      totalListings: listings.length,
      avgDaysListed: avgDaysListed,
      topProperty: top,
      rows: rows,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ListerAnalyticsData>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(snap.error.toString()));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                child: _SummarySection(data: data),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: _TimeRangeSection(
                  selected: _selectedRange,
                  onChanged: (r) {
                    setState(() {
                      _selectedRange = r;
                      _future = _load(); // reload with new range
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: _ListingsOverviewSection(data: data),
              ),
              if (data.topProperty != null) ...[
                const SizedBox(height: 12),
                _SectionCard(
                  child: _TopPropertySection(row: data.topProperty!),
                ),
              ],
              const SizedBox(height: 12),
              _SectionCard(
                child: _AllPropertiesSection(rows: data.rows),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: _InsightsSection(data: data),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ListerAnalyticsData {
  const _ListerAnalyticsData({
    required this.totalViews,
    required this.avgViewTime,
    required this.totalInquiries,
    required this.conversionRate,
    required this.totalListings,
    required this.avgDaysListed,
    required this.topProperty,
    required this.rows,
  });

  final int totalViews;
  final double avgViewTime;
  final int totalInquiries;
  final double conversionRate;
  final int totalListings;
  final double avgDaysListed;
  final _ListingRow? topProperty;
  final List<_ListingRow> rows;

  const _ListerAnalyticsData.empty()
      : totalViews = 0,
        avgViewTime = 0,
        totalInquiries = 0,
        conversionRate = 0,
        totalListings = 0,
        avgDaysListed = 0,
        topProperty = null,
        rows = const [];
}

class _ListingRow {
  const _ListingRow({
    required this.id,
    required this.title,
    required this.views,
    required this.avgTime,
    required this.inquiries,
    required this.saved,
    required this.liked,
    required this.daysListed,
  });

  final String id;
  final String title;
  final int views;
  final double avgTime;
  final int inquiries;
  final int saved;
  final int liked;
  final int daysListed;
}

class _PropertyAnalyticsRow {
  const _PropertyAnalyticsRow({
    required this.views,
    required this.inquiries,
    required this.savedCount,
    required this.likedCount,
    required this.averageTimeMins,
  });

  final int views;
  final int inquiries;
  final int savedCount;
  final int likedCount;
  /// Average view time in minutes, derived from totalViewTime/views/60.
  final double averageTimeMins;

  const _PropertyAnalyticsRow.zero()
      : views = 0,
        inquiries = 0,
        savedCount = 0,
        likedCount = 0,
        averageTimeMins = 0;
}

enum _AnalyticsTimeRange { week, month, quarter, year }

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.data});
  final _ListerAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Listings Performance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${data.totalListings} properties listed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.bar_chart_rounded, color: Colors.blue),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          children: [
            _MetricCard('Total Views', '${data.totalViews}', Icons.visibility, Colors.blue),
            _MetricCard('Avg View Time', '${data.avgViewTime.toStringAsFixed(1)} min',
                Icons.schedule_rounded, Colors.green),
            _MetricCard('Total Inquiries', '${data.totalInquiries}', Icons.mail_outline,
                Colors.orange),
            _MetricCard('Conversion Rate', '${data.conversionRate.toStringAsFixed(1)}%',
                Icons.trending_up_rounded, Colors.purple),
          ],
        ),
      ],
    );
  }
}

class _TimeRangeSection extends StatelessWidget {
  const _TimeRangeSection({required this.selected, required this.onChanged});
  final _AnalyticsTimeRange selected;
  final ValueChanged<_AnalyticsTimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AnalyticsTimeRange>(
      segments: const [
        ButtonSegment(value: _AnalyticsTimeRange.week, label: Text('Week')),
        ButtonSegment(value: _AnalyticsTimeRange.month, label: Text('Month')),
        ButtonSegment(value: _AnalyticsTimeRange.quarter, label: Text('Quarter')),
        ButtonSegment(value: _AnalyticsTimeRange.year, label: Text('Year')),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _ListingsOverviewSection extends StatelessWidget {
  const _ListingsOverviewSection({required this.data});
  final _ListerAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Listings Overview',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                'Listed Properties',
                '${data.totalListings}',
                Icons.home_rounded,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                'Avg Days Listed',
                data.avgDaysListed.toStringAsFixed(0),
                Icons.calendar_today_rounded,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TopPropertySection extends StatelessWidget {
  const _TopPropertySection({required this.row});
  final _ListingRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top Performing Property',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  row.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.star, color: Colors.amber),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MiniStat('Views', '${row.views}', Colors.blue),
            _MiniStat('Avg Time',
                row.avgTime > 0 ? '${row.avgTime.toStringAsFixed(1)}m' : '—',
                Colors.green),
            _MiniStat('Inquiries', '${row.inquiries}', Colors.orange),
            _MiniStat(
              'Conversion',
              row.views == 0
                  ? '0%'
                  : '${((row.inquiries / row.views) * 100).toStringAsFixed(1)}%',
              Colors.purple,
            ),
          ],
        ),
      ],
    );
  }
}

class _AllPropertiesSection extends StatelessWidget {
  const _AllPropertiesSection({required this.rows});
  final List<_ListingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'All Your Properties',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(
            'You have no active listings yet. Add a listing to see analytics.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          )
        else
          ...rows.map(
            (r) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(
                        r.views >= 10
                            ? Icons.arrow_upward_rounded
                            : (r.views == 0
                                ? Icons.remove_rounded
                                : Icons.arrow_downward_rounded),
                        size: 16,
                        color: r.views >= 10
                            ? Colors.green
                            : (r.views == 0 ? Colors.grey : Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _PropertyStat('Views', '${r.views}', Colors.blue),
                      _PropertyStat('Avg Time',
                          r.avgTime > 0 ? '${r.avgTime.toStringAsFixed(1)}m' : '—',
                          Colors.green),
                      _PropertyStat('Inquiries', '${r.inquiries}', Colors.orange),
                      _PropertyStat('Saved', '${r.saved}', Colors.purple),
                      _PropertyStat('Liked', '${r.liked}', Colors.pink),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.data});
  final _ListerAnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final topTitle = data.topProperty?.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Performance Insights',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        _InsightRow(
          icon: Icons.lightbulb_rounded,
          color: Colors.amber,
          text: 'Your properties are getting ${data.totalViews} total views',
        ),
        _InsightRow(
          icon: Icons.schedule_rounded,
          color: Colors.green,
          text:
              'Users spend an average of ${data.avgViewTime.toStringAsFixed(1)} minutes viewing your listings',
        ),
        if (topTitle != null)
          _InsightRow(
            icon: Icons.star_rounded,
            color: Colors.orange,
            text: '$topTitle is your top performer with ${data.topProperty!.views} views',
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.title, this.value, this.icon, this.color);
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.title, this.value, this.color);
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _PropertyStat extends StatelessWidget {
  const _PropertyStat(this.title, this.value, this.color);
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
