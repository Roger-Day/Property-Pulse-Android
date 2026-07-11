import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/property_model.dart';
import 'realtor_upgrade_prompt_screen.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class PropertyAnalyticsData {
  const PropertyAnalyticsData({
    required this.views,
    required this.inquiries,
    required this.savedCount,
    required this.contactClicks,
    required this.averageTimeOnPage,
    required this.priceHistory,
  });

  final int views;
  final int inquiries;
  final int savedCount;
  final int contactClicks;
  final double averageTimeOnPage;
  final List<_PriceHistoryEntry> priceHistory;
}

class _PriceHistoryEntry {
  const _PriceHistoryEntry({required this.date, required this.price});
  final DateTime date;
  final double price;
}

// ─── Gate view — routes to Basic or Advanced ─────────────────────────────────

class RealtorAnalyticsGateScreen extends StatefulWidget {
  const RealtorAnalyticsGateScreen({
    super.key,
    required this.property,
    required this.isProOrElite,
  });

  final PropertyModel property;
  final bool isProOrElite;

  @override
  State<RealtorAnalyticsGateScreen> createState() =>
      _RealtorAnalyticsGateScreenState();
}

class _RealtorAnalyticsGateScreenState
    extends State<RealtorAnalyticsGateScreen> {
  PropertyAnalyticsData? _analytics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConstants.propertyAnalyticsCollection)
          .doc(widget.property.id)
          .get();
      if (!mounted) return;
      if (!snap.exists || snap.data() == null) {
        setState(() => _loading = false);
        return;
      }
      final m = snap.data()!;
      int intVal(String k) => (m[k] as num?)?.toInt() ?? 0;
      double dblVal(String k) => (m[k] as num?)?.toDouble() ?? 0;

      List<_PriceHistoryEntry> history = [];
      if (m['priceHistory'] is List) {
        for (final item in m['priceHistory'] as List) {
          if (item is Map<String, dynamic>) {
            final price = (item['price'] as num?)?.toDouble();
            final rawDate = item['date'];
            DateTime? date;
            if (rawDate is Timestamp) date = rawDate.toDate();
            if (price != null && date != null) {
              history.add(_PriceHistoryEntry(date: date, price: price));
            }
          }
        }
        history.sort((a, b) => a.date.compareTo(b.date));
      }

      final views = intVal('views');
      final totalViewSecs = dblVal('totalViewTime');
      final avgMins = views > 0 ? (totalViewSecs / views / 60) : 0.0;

      setState(() {
        _analytics = PropertyAnalyticsData(
          views: views,
          inquiries: intVal('inquiries'),
          savedCount: intVal('savedCount'),
          contactClicks: intVal('contactClicks'),
          averageTimeOnPage: avgMins,
          priceHistory: history,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isProOrElite) {
      return _AdvancedAnalyticsView(
        property: widget.property,
        analytics: _analytics,
        isLoading: _loading,
        error: _error,
      );
    }
    return _BasicAnalyticsView(
      property: widget.property,
      analytics: _analytics,
      isLoading: _loading,
      error: _error,
    );
  }
}

// ─── Basic Analytics (Free tier) ─────────────────────────────────────────────

class _BasicAnalyticsView extends StatelessWidget {
  const _BasicAnalyticsView({
    required this.property,
    required this.analytics,
    required this.isLoading,
    required this.error,
  });

  final PropertyModel property;
  final PropertyAnalyticsData? analytics;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Property Analytics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PropertyHeaderCard(property: property),
            const SizedBox(height: 12),
            _TierBanner(isAdvanced: false, tierLabel: 'Free'),
            const SizedBox(height: 12),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (error != null)
              _ErrorCard(message: error!)
            else if (analytics != null)
              _BasicMetricsSection(analytics: analytics!)
            else
              _NoAnalyticsCard(),
            const SizedBox(height: 12),
            // Soft-gated sections
            SoftGateOverlay(
              feature: RealtorGatedFeature.advancedAnalytics,
              label: 'Engagement Trends',
              child: _EngagementTrendsPreview(analytics: analytics),
            ),
            const SizedBox(height: 12),
            SoftGateOverlay(
              feature: RealtorGatedFeature.advancedAnalytics,
              label: 'Conversion Metrics',
              child: _ConversionMetricsPreview(analytics: analytics),
            ),
            const SizedBox(height: 12),
            SoftGateOverlay(
              feature: RealtorGatedFeature.advancedAnalytics,
              label: 'Performance Insights',
              child: _PerformanceInsightsPreview(analytics: analytics),
            ),
            const SizedBox(height: 16),
            _UpgradeSummaryCard(feature: RealtorGatedFeature.advancedAnalytics),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Advanced Analytics (Pro / Elite) ────────────────────────────────────────

class _AdvancedAnalyticsView extends StatefulWidget {
  const _AdvancedAnalyticsView({
    required this.property,
    required this.analytics,
    required this.isLoading,
    required this.error,
  });

  final PropertyModel property;
  final PropertyAnalyticsData? analytics;
  final bool isLoading;
  final String? error;

  @override
  State<_AdvancedAnalyticsView> createState() => _AdvancedAnalyticsViewState();
}

class _AdvancedAnalyticsViewState extends State<_AdvancedAnalyticsView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Property Analytics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PropertyHeaderCard(property: widget.property),
            const SizedBox(height: 12),
            _TierBanner(isAdvanced: true, tierLabel: 'Pro'),
            const SizedBox(height: 12),
            if (widget.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (widget.error != null)
              _ErrorCard(message: widget.error!)
            else if (widget.analytics != null) ...[
              _AdvancedCoreMetricsSection(analytics: widget.analytics!),
              const SizedBox(height: 12),
              _EngagementTrendsSection(analytics: widget.analytics!),
              const SizedBox(height: 12),
              _ConversionMetricsSection(analytics: widget.analytics!),
              const SizedBox(height: 12),
              _PerformanceInsightsSection(analytics: widget.analytics!),
            ] else
              _NoAnalyticsCard(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Shared components ────────────────────────────────────────────────────────

class _PropertyHeaderCard extends StatelessWidget {
  const _PropertyHeaderCard({required this.property});
  final PropertyModel property;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Row(
        children: [
          const Icon(Icons.home_work, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('${property.city}, ${property.state}',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierBanner extends StatelessWidget {
  const _TierBanner({required this.isAdvanced, required this.tierLabel});
  final bool isAdvanced;
  final String tierLabel;

  @override
  Widget build(BuildContext context) {
    final color = isAdvanced ? Colors.purple : AppColors.textSecondary;
    return _AnalyticsCard(
      child: Row(
        children: [
          Icon(
            isAdvanced ? Icons.bar_chart : Icons.bar_chart_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Text(
            isAdvanced ? 'Advanced Analytics' : 'Basic Analytics',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tierLabel,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _BasicMetricsSection extends StatelessWidget {
  const _BasicMetricsSection({required this.analytics});
  final PropertyAnalyticsData analytics;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Key Metrics',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BasicMetricTile(
                    icon: Icons.visibility,
                    color: Colors.blue,
                    value: '${analytics.views}',
                    label: 'Views'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BasicMetricTile(
                    icon: Icons.bookmark,
                    color: Colors.orange,
                    value: '${analytics.savedCount}',
                    label: 'Saves'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BasicMetricTile(
                    icon: Icons.message,
                    color: Colors.green,
                    value: '${analytics.inquiries}',
                    label: 'Inquiries'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BasicMetricTile extends StatelessWidget {
  const _BasicMetricTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _AdvancedCoreMetricsSection extends StatelessWidget {
  const _AdvancedCoreMetricsSection({required this.analytics});
  final PropertyAnalyticsData analytics;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Key Metrics', icon: Icons.bar_chart, color: Colors.blue),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                  title: 'Total Views',
                  value: '${analytics.views}',
                  icon: Icons.visibility,
                  color: Colors.blue),
              _MetricCard(
                  title: 'Inquiries',
                  value: '${analytics.inquiries}',
                  icon: Icons.message,
                  color: Colors.green),
              _MetricCard(
                  title: 'Saves',
                  value: '${analytics.savedCount}',
                  icon: Icons.bookmark,
                  color: Colors.orange),
              _MetricCard(
                  title: 'Contact Clicks',
                  value: '${analytics.contactClicks}',
                  icon: Icons.phone,
                  color: Colors.purple),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _EngagementTrendsSection extends StatelessWidget {
  const _EngagementTrendsSection({required this.analytics});
  final PropertyAnalyticsData analytics;

  @override
  Widget build(BuildContext context) {
    final points = [0.2, 0.45, 0.3, 0.6, 0.55, 0.75, 1.0];
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Engagement Trends',
              icon: Icons.show_chart,
              color: Colors.teal),
          const SizedBox(height: 12),
          // Sparkline
          SizedBox(
            height: 68,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points
                  .map(
                    (v) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: v * 60 + 8,
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    analytics.views > 0
                        ? (analytics.views / 30.0).toStringAsFixed(1)
                        : '–',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text('Avg Views / Day',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    analytics.averageTimeOnPage > 0
                        ? '${analytics.averageTimeOnPage.toStringAsFixed(1)} min'
                        : '–',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text('Avg Time on Page',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PlaceholderBadge(
              text: 'Time-series chart available after 7+ days of data'),
        ],
      ),
    );
  }
}

class _ConversionMetricsSection extends StatelessWidget {
  const _ConversionMetricsSection({required this.analytics});
  final PropertyAnalyticsData analytics;

  double _rate(int n) =>
      analytics.views > 0 ? n / analytics.views * 100 : 0;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Conversion Metrics',
              icon: Icons.percent,
              color: Colors.green),
          const SizedBox(height: 12),
          _ConversionRow(
              label: 'View → Save',
              pct: _rate(analytics.savedCount),
              color: Colors.orange),
          const SizedBox(height: 8),
          _ConversionRow(
              label: 'View → Inquiry',
              pct: _rate(analytics.inquiries),
              color: Colors.green),
          const SizedBox(height: 8),
          _ConversionRow(
              label: 'View → Contact',
              pct: _rate(analytics.contactClicks),
              color: Colors.purple),
          const SizedBox(height: 8),
          _PlaceholderBadge(
              text: 'Benchmark comparisons coming in a future update'),
        ],
      ),
    );
  }
}

class _ConversionRow extends StatelessWidget {
  const _ConversionRow({
    required this.label,
    required this.pct,
    required this.color,
  });
  final String label;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color.withOpacity(0.75)),
              minHeight: 10,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          child: Text(
            '${pct.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color),
          ),
        ),
      ],
    );
  }
}

class _PerformanceInsightsSection extends StatelessWidget {
  const _PerformanceInsightsSection({required this.analytics});
  final PropertyAnalyticsData analytics;

  int get _score {
    int s = 0;
    if (analytics.views > 50) s++;
    if (analytics.inquiries > 5) s++;
    if (analytics.savedCount > 3) s++;
    return s;
  }

  String get _label =>
      ['Needs Attention', 'Improving', 'Good', 'Strong'][_score];

  Color get _color => [Colors.red, Colors.orange, Colors.teal, Colors.green][_score];

  List<String> get _insights {
    final msgs = <String>[];
    if (analytics.views < 20) {
      msgs.add(
          'Add more photos or update the description to improve discoverability.');
    }
    if (analytics.savedCount == 0) {
      msgs.add(
          'Consider adjusting the price — no saves yet after ${analytics.views} views.');
    }
    if (analytics.inquiries > 0 && analytics.contactClicks == 0) {
      msgs.add(
          'Prospects are inquiring but not calling. Ensure your contact info is visible.');
    }
    if (msgs.isEmpty) {
      msgs.add('Your listing is performing well. Keep the details up to date.');
    }
    return msgs;
  }

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Performance Insights',
              icon: Icons.lightbulb,
              color: Colors.amber),
          const SizedBox(height: 12),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Score',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(_label,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _color)),
                ],
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  3,
                  (i) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _score
                            ? _color
                            : AppColors.textSecondary.withOpacity(0.2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          ..._insights.map(
            (msg) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right_alt,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(msg,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
          _PlaceholderBadge(
              text: 'AI-powered insights coming in a future update'),
        ],
      ),
    );
  }
}

// ─── Preview widgets (shown blurred in Basic tier) ───────────────────────────

class _EngagementTrendsPreview extends StatelessWidget {
  const _EngagementTrendsPreview({this.analytics});
  final PropertyAnalyticsData? analytics;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Engagement Trends',
              icon: Icons.show_chart,
              color: Colors.teal),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [0.2, 0.4, 0.3, 0.7, 0.5, 0.8, 1.0]
                  .map(
                    (v) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Container(
                          height: v * 40 + 6,
                          color: Colors.teal.withOpacity(0.4),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversionMetricsPreview extends StatelessWidget {
  const _ConversionMetricsPreview({this.analytics});
  final PropertyAnalyticsData? analytics;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Conversion Metrics',
              icon: Icons.percent,
              color: Colors.green),
          const SizedBox(height: 12),
          _ConversionRow(
              label: 'View → Save', pct: 24.0, color: Colors.orange),
          const SizedBox(height: 8),
          _ConversionRow(
              label: 'View → Inquiry', pct: 8.0, color: Colors.green),
        ],
      ),
    );
  }
}

class _PerformanceInsightsPreview extends StatelessWidget {
  const _PerformanceInsightsPreview({this.analytics});
  final PropertyAnalyticsData? analytics;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
              title: 'Performance Insights',
              icon: Icons.lightbulb,
              color: Colors.amber),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Overall Score',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Text('Strong',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Upgrade CTA card ─────────────────────────────────────────────────────────

class _UpgradeSummaryCard extends StatelessWidget {
  const _UpgradeSummaryCard({required this.feature});
  final RealtorGatedFeature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.orange, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Unlock all analytics with Realtor Pro',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(
                  'Trends, conversion rates, performance score and more.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => RealtorUpgradePromptScreen(feature: feature),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.purple,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });
  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }
}

class _PlaceholderBadge extends StatelessWidget {
  const _PlaceholderBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style:
                TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _NoAnalyticsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Column(
        children: [
          const Icon(Icons.bar_chart, size: 40, color: Colors.grey),
          const SizedBox(height: 8),
          Text('No analytics yet',
              style: TextStyle(color: AppColors.textSecondary)),
          Text('Analytics will appear after your listing gets views.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _AnalyticsCard(
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
