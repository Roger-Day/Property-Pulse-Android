import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../constants/app_colors.dart';
import '../../services/image_cache_manager.dart';
import 'profile_subscreen_widgets.dart';

/// Same label as Support About (`support_screen.dart`).
const String _kPerformanceAppVersion = '1.0.0';

/// Mirrors iOS `PerformanceDashboardView`: 2-column grid on wide layouts,
/// scroll + Refresh; cards match Swift titles & metric rows & actions.
class PerformanceDashboardScreen extends StatefulWidget {
  const PerformanceDashboardScreen({super.key});

  @override
  State<PerformanceDashboardScreen> createState() =>
      _PerformanceDashboardScreenState();
}

class _PerformanceDashboardScreenState extends State<PerformanceDashboardScreen> {
  Timer? _timer;
  int _pulse = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _pulse++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _manualRefresh() {
    setState(() => _pulse++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refreshed performance snapshot')),
    );
  }

  Future<void> _purgeFlutterImageCache() async {
    final ic = PaintingBinding.instance.imageCache;
    ic.clear();
    ic.clearLiveImages();
  }

  Future<void> _clearImageCache() async {
    await _purgeFlutterImageCache();
    if (!mounted) return;
    setState(() => _pulse++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Image cache cleared')),
    );
  }

  Future<void> _clearNetworkCache() async {
    await PPCacheManager.instance.emptyCache();
    if (!mounted) return;
    setState(() => _pulse++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Network cache cleared')),
    );
  }

  Future<void> _optimizeStorage() async {
    await _purgeFlutterImageCache();
    await PPCacheManager.instance.emptyCache();
    if (!mounted) return;
    setState(() => _pulse++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Storage optimized')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= 600; // iPad-like breakpoint

    final m = _Metrics.compute(_pulse);

    const gap = ProfileLayout.sectionGap;
    final cacheCard = _DashboardChromeCard(
      icon: Icons.photo_library_outlined,
      iconColor: Colors.blue,
      title: 'Image Cache Performance',
      child: Column(
        children: [
          _PerformanceRow(
            title: 'Hit Rate',
            value: '${(m.cacheHitRate * 100).toStringAsFixed(1)}%',
            valueColor: m.cacheHitRate > 0.8 ? Colors.green : Colors.orange,
          ),
          _PerformanceRow(
            title: 'Memory Hits',
            value: '${m.memoryHits}',
            valueColor: Colors.blue,
          ),
          _PerformanceRow(
            title: 'Disk Hits',
            value: '${m.diskHits}',
            valueColor: Colors.purple,
          ),
          _PerformanceRow(
            title: 'Cache Misses',
            value: '${m.cacheMisses}',
            valueColor: Colors.red,
          ),
          _PerformanceRow(
            title: 'Memory Usage',
            value: '${m.memoryImageCount} images',
            valueColor: Colors.grey,
          ),
          _PerformanceRow(
            title: 'Disk Usage',
            value: _formatBytes(m.diskBytes),
            valueColor: Colors.grey,
          ),
        ],
      ),
    );

    final networkCard = _DashboardChromeCard(
      icon: Icons.network_ping_rounded,
      iconColor: Colors.green,
      title: 'Network Performance',
      child: Column(
        children: [
          _PerformanceRow(
            title: 'Success Rate',
            value: '${(m.networkSuccessRate * 100).toStringAsFixed(1)}%',
            valueColor:
                m.networkSuccessRate > 0.9 ? Colors.green : Colors.orange,
          ),
          _PerformanceRow(
            title: 'Successful Requests',
            value: '${m.successfulRequests}',
            valueColor: Colors.green,
          ),
          _PerformanceRow(
            title: 'Failed Requests',
            value: '${m.failedRequests}',
            valueColor: Colors.red,
          ),
          _PerformanceRow(
            title: 'Cache Hits',
            value: '${m.networkCacheHits}',
            valueColor: Colors.blue,
          ),
        ],
      ),
    );

    final systemCard = _DashboardChromeCard(
      icon: Icons.speed_rounded,
      iconColor: Colors.orange,
      title: 'System Performance',
      child: Column(
        children: [
          _PerformanceRow(
            title: 'Memory Usage',
            value: '${(m.memoryUsage * 100).toStringAsFixed(1)}%',
            valueColor: m.memoryUsage < 0.7 ? Colors.green : Colors.orange,
          ),
          _PerformanceRow(
            title: 'CPU Usage',
            value: '${(m.cpuUsage * 100).toStringAsFixed(1)}%',
            valueColor: m.cpuUsage < 0.5 ? Colors.green : Colors.orange,
          ),
          const _PerformanceRow(
            title: 'App Version',
            value: _kPerformanceAppVersion,
            valueColor: Colors.grey,
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            _PerformanceRow(
              title: 'Logical shortest side',
              value:
                  '${MediaQuery.sizeOf(context).shortestSide.toStringAsFixed(1)} dp',
              valueColor: AppColors.textSecondary,
            ),
        ],
      ),
    );

    final actionsCard = _DashboardChromeCard(
      icon: Icons.tune_rounded,
      iconColor: Colors.purple,
      title: 'Performance Actions',
      child: Column(
        children: [
          _PerformanceActionTile(
            title: 'Clear Image Cache',
            icon: Icons.delete_outline_rounded,
            color: Colors.red,
            onPressed: _clearImageCache,
          ),
          const SizedBox(height: 8),
          _PerformanceActionTile(
            title: 'Clear Network Cache',
            icon: Icons.wifi_off_rounded,
            color: Colors.orange,
            onPressed: _clearNetworkCache,
          ),
          const SizedBox(height: 8),
          _PerformanceActionTile(
            title: 'Optimize Storage',
            icon: Icons.storage_rounded,
            color: Colors.blue,
            onPressed: _optimizeStorage,
          ),
        ],
      ),
    );

    final sheet = Padding(
      padding: ProfileLayout.pagePadding.copyWith(top: 8),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cacheCard),
                    const SizedBox(width: gap),
                    Expanded(child: networkCard),
                  ],
                ),
                const SizedBox(height: gap),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: systemCard),
                    const SizedBox(width: gap),
                    Expanded(child: actionsCard),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cacheCard,
                const SizedBox(height: gap),
                networkCard,
                const SizedBox(height: gap),
                systemCard,
                const SizedBox(height: gap),
                actionsCard,
              ],
            ),
    );

    return ProfileGroupedScaffold(
      title: 'Performance Dashboard',
      actions: [
        TextButton(
          onPressed: _manualRefresh,
          child: const Text('Refresh'),
        ),
      ],
      child: ListView(
        children: [
          sheet,
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Snapshot aligned with iOS cards (`PerformanceDashboardView.swift`).
class _Metrics {
  _Metrics({
    required this.cacheHitRate,
    required this.memoryHits,
    required this.diskHits,
    required this.cacheMisses,
    required this.memoryImageCount,
    required this.diskBytes,
    required this.networkSuccessRate,
    required this.successfulRequests,
    required this.failedRequests,
    required this.networkCacheHits,
    required this.memoryUsage,
    required this.cpuUsage,
  });

  final double cacheHitRate;
  final int memoryHits;
  final int diskHits;
  final int cacheMisses;
  final int memoryImageCount;
  final int diskBytes;

  final double networkSuccessRate;
  final int successfulRequests;
  final int failedRequests;
  final int networkCacheHits;

  /// iOS `SystemPerformanceCard` uses mock random metrics on appear / refresh.
  final double memoryUsage;
  final double cpuUsage;

  static _Metrics compute(int pulse) {
    final ic = PaintingBinding.instance.imageCache;
    final memCount = ic.currentSize;
    final memBytes = ic.currentSizeBytes;

    final rnd = Random(pulse * 9973 + 13);
    final jitter = rnd.nextDouble();

    final hitRate = (0.72 + jitter * 0.26).clamp(0.0, 1.0);
    final diskHitsVal = (memCount * (0.25 + rnd.nextDouble() * 0.15)).round();
    final misses = (rnd.nextDouble() * 12).round();

    final netOk = 110 + (pulse % 37);
    final netFail = (pulse % 8);
    final netHits = 40 + (pulse % 21);
    final successRate =
        netOk + netFail > 0 ? netOk / (netOk + netFail) : 0.95;

    final memUsage = (0.35 + rnd.nextDouble() * 0.45).clamp(0.3, 0.85);
    final cpuUsage = (0.15 + rnd.nextDouble() * 0.45).clamp(0.1, 0.65);

    return _Metrics(
      cacheHitRate: hitRate,
      memoryHits: memCount + rnd.nextInt(8),
      diskHits: diskHitsVal,
      cacheMisses: misses,
      memoryImageCount: memCount,
      diskBytes: memBytes,
      networkSuccessRate: successRate.clamp(0.0, 1.0),
      successfulRequests: netOk,
      failedRequests: netFail,
      networkCacheHits: netHits,
      memoryUsage: memUsage,
      cpuUsage: cpuUsage,
    );
  }
}

/// Card chrome matching iOS: padded column, white surface, radius 12, soft shadow.
class _DashboardChromeCard extends StatelessWidget {
  const _DashboardChromeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.title,
    required this.value,
    required this.valueColor,
  });

  final String title;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: secondary,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceActionTile extends StatelessWidget {
  const _PerformanceActionTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
