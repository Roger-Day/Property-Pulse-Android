import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import 'analytics_shared.dart';

/// Market Intelligence — Android's differentiating analytics feature.
///
/// Hosts the Market and Trends insights that used to live inside the
/// Analytics dashboard. Listings Analytics (My Analytics) is now the
/// canonical iOS-mirrored experience; market-wide data lives here.
class MarketIntelligenceScreen extends StatefulWidget {
  const MarketIntelligenceScreen({super.key, required this.userId});

  final String userId;

  @override
  State<MarketIntelligenceScreen> createState() =>
      _MarketIntelligenceScreenState();
}

class _MarketIntelligenceScreenState extends State<MarketIntelligenceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Market Intelligence'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Market'), Tab(text: 'Trends')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MarketInsightsTab(userId: widget.userId),
          _TrendsTab(userId: widget.userId),
        ],
      ),
    );
  }
}

// ─── Data models ────────────────────────────────────────────────────────────

class _MarketData {
  const _MarketData({
    required this.averagePrice,
    required this.priceChangePct,
    required this.inventoryCount,
    required this.forSaleCount,
    required this.forRentCount,
    required this.avgDaysOnMarket,
    required this.marketTrend,
  });

  final double averagePrice;
  final double priceChangePct;
  final int inventoryCount;
  final int forSaleCount;
  final int forRentCount;
  final double avgDaysOnMarket;
  final String marketTrend; // 'rising' | 'stable' | 'falling'
}

class _TrendsData {
  const _TrendsData({
    required this.totalSearches,
    required this.topFilters,
    required this.recentQueries,
  });

  final int totalSearches;
  final List<MapEntry<String, int>> topFilters;
  final List<String> recentQueries;
}

// ─── Market Insights Tab ─────────────────────────────────────────────────────

class _MarketInsightsTab extends StatefulWidget {
  const _MarketInsightsTab({required this.userId});
  final String userId;

  @override
  State<_MarketInsightsTab> createState() => _MarketInsightsTabState();
}

class _MarketInsightsTabState extends State<_MarketInsightsTab> {
  Future<_MarketData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MarketData> _load() async {
    final db = FirebaseFirestore.instance;
    var totalPrice = 0.0;
    final priceChanges = <double>[];
    var inventoryCount = 0;
    var forSaleCount = 0;
    var forRentCount = 0;
    var totalDays = 0;
    var daysCount = 0;

    try {
      final snap = await db
          .collection(AppConstants.propertiesCollection)
          .where('status', whereIn: ['active', 'available'])
          .limit(200)
          .get();
      for (final doc in snap.docs) {
        final m = doc.data();
        final price = (m['price'] as num?)?.toDouble() ?? 0;
        if (price > 0) {
          totalPrice += price;
          inventoryCount++;
        }
        final origPrice = (m['originalPrice'] as num?)?.toDouble();
        if (origPrice != null && origPrice > 0 && price > 0) {
          priceChanges.add(((price - origPrice) / origPrice) * 100);
        }
        final type = (m['listingType'] as String? ?? '').toLowerCase();
        if (type.contains('rent') || type == 'for_rent') {
          forRentCount++;
        } else {
          forSaleCount++;
        }
        final createdAt = m['createdAt'];
        if (createdAt is Timestamp) {
          totalDays += DateTime.now().difference(createdAt.toDate()).inDays;
          daysCount++;
        }
      }
    } catch (_) {}

    final avgPrice = inventoryCount == 0 ? 0.0 : totalPrice / inventoryCount;
    final avgPriceChange = priceChanges.isEmpty
        ? 0.0
        : priceChanges.reduce((a, b) => a + b) / priceChanges.length;
    final avgDays = daysCount == 0 ? 0.0 : totalDays / daysCount;
    String trend;
    if (avgPriceChange > 1) {
      trend = 'rising';
    } else if (avgPriceChange < -1) {
      trend = 'falling';
    } else {
      trend = 'stable';
    }

    return _MarketData(
      averagePrice: avgPrice,
      priceChangePct: avgPriceChange,
      inventoryCount: inventoryCount,
      forSaleCount: forSaleCount,
      forRentCount: forRentCount,
      avgDaysOnMarket: avgDays,
      marketTrend: trend,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder<_MarketData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final d = snap.data!;
          final trendColor = d.marketTrend == 'rising'
              ? Colors.green
              : d.marketTrend == 'falling'
                  ? Colors.red
                  : Colors.orange;
          final trendIcon = d.marketTrend == 'rising'
              ? Icons.trending_up
              : d.marketTrend == 'falling'
                  ? Icons.trending_down
                  : Icons.trending_flat;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AnalyticsSectionHeader('Market Overview'),
              const SizedBox(height: 12),
              AnalyticsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(trendIcon, color: trendColor),
                        const SizedBox(width: 8),
                        Text(
                          'Market Trend: ${d.marketTrend[0].toUpperCase()}${d.marketTrend.substring(1)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: trendColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AnalyticsStatRow('Avg Listing Price',
                        '\$${d.averagePrice.toStringAsFixed(0)}'),
                    AnalyticsStatRow('Avg Price Change',
                        '${d.priceChangePct >= 0 ? '+' : ''}${d.priceChangePct.toStringAsFixed(1)}%'),
                    AnalyticsStatRow('Active Listings', '${d.inventoryCount}'),
                    AnalyticsStatRow(
                        'Avg Days on Market', d.avgDaysOnMarket.toStringAsFixed(1)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const AnalyticsSectionHeader('Inventory Breakdown'),
              const SizedBox(height: 12),
              AnalyticsMetricGrid([
                AnalyticsMetricTile(
                  icon: Icons.sell_outlined,
                  color: Colors.blue,
                  label: 'For Sale',
                  value: '${d.forSaleCount}',
                ),
                AnalyticsMetricTile(
                  icon: Icons.key_outlined,
                  color: Colors.teal,
                  label: 'For Rent',
                  value: '${d.forRentCount}',
                ),
                AnalyticsMetricTile(
                  icon: Icons.apartment_outlined,
                  color: Colors.indigo,
                  label: 'Total Active',
                  value: '${d.inventoryCount}',
                ),
                AnalyticsMetricTile(
                  icon: Icons.schedule_outlined,
                  color: Colors.orange,
                  label: 'Days on Market',
                  value: d.avgDaysOnMarket.toStringAsFixed(0),
                ),
              ]),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

// ─── Trends Tab ──────────────────────────────────────────────────────────────

class _TrendsTab extends StatefulWidget {
  const _TrendsTab({required this.userId});
  final String userId;

  @override
  State<_TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<_TrendsTab> {
  Future<_TrendsData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TrendsData> _load() async {
    final db = FirebaseFirestore.instance;
    var totalSearches = 0;
    final filterCounts = <String, int>{};
    final recentQueries = <String>[];

    try {
      final snap = await db
          .collection('search_history')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      totalSearches = snap.docs.length;
      for (final doc in snap.docs) {
        final m = doc.data();
        final q = m['query'] as String? ?? '';
        if (q.isNotEmpty && recentQueries.length < 5) recentQueries.add(q);
        final filters = m['filters'];
        if (filters is Map) {
          for (final key in filters.keys) {
            final v = filters[key];
            if (v != null && v != '' && v != false && v != 0) {
              filterCounts[key as String] = (filterCounts[key] ?? 0) + 1;
            }
          }
        }
      }
    } catch (_) {}

    final topFilters = filterCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _TrendsData(
      totalSearches: totalSearches,
      topFilters: topFilters.take(5).toList(),
      recentQueries: recentQueries,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: FutureBuilder<_TrendsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final d = snap.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const AnalyticsSectionHeader('Your Search Activity'),
              const SizedBox(height: 12),
              AnalyticsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnalyticsStatRow('Total Searches', '${d.totalSearches}'),
                    if (d.recentQueries.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Recent Searches',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      ...d.recentQueries.map(
                        (q) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.search,
                                  size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 6),
                              Text(q,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (d.topFilters.isNotEmpty) ...[
                const SizedBox(height: 20),
                const AnalyticsSectionHeader('Most-Used Filters'),
                const SizedBox(height: 12),
                AnalyticsCard(
                  child: Column(
                    children: d.topFilters.map((e) {
                      final pct = d.totalSearches == 0
                          ? 0.0
                          : e.value / d.totalSearches;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  e.key,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                Text(
                                  '${e.value}x',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct.clamp(0.0, 1.0),
                                minHeight: 6,
                                backgroundColor: AppColors.divider,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}
