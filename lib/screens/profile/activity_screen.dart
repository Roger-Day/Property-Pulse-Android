import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_colors.dart';
import 'analytics_shared.dart';

/// Profile → Activity — your app engagement (moved out of Analytics so
/// Listings Analytics can mirror iOS 1:1 while this data stays available).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.userId});

  final String userId;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityData {
  const _ActivityData({
    required this.propertyViews,
    required this.savedCount,
    required this.likedCount,
    required this.messages,
    required this.appOpens,
  });

  final int propertyViews;
  final int savedCount;
  final int likedCount;
  final int messages;
  final int appOpens;
}

class _ActivityScreenState extends State<ActivityScreen> {
  Future<_ActivityData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ActivityData> _load() async {
    var propViews = 0;
    var savedCount = 0;
    var likedCount = 0;
    var messages = 0;
    var appOpens = 0;
    try {
      final engDoc = await FirebaseFirestore.instance
          .collection('user_engagement')
          .doc(widget.userId)
          .get();
      if (engDoc.exists) {
        final e = engDoc.data()!;
        propViews = (e['propertyViews'] as num?)?.toInt() ?? 0;
        savedCount = (e['savedProperties'] as num?)?.toInt() ?? 0;
        likedCount = (e['propertiesLiked'] as num?)?.toInt() ?? 0;
        messages = (e['messages'] as num?)?.toInt() ?? 0;
        appOpens = (e['appOpens'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    return _ActivityData(
      propertyViews: propViews,
      savedCount: savedCount,
      likedCount: likedCount,
      messages: messages,
      appOpens: appOpens,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Your Activity'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<_ActivityData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data ??
                const _ActivityData(
                  propertyViews: 0,
                  savedCount: 0,
                  likedCount: 0,
                  messages: 0,
                  appOpens: 0,
                );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const AnalyticsSectionHeader('Your Engagement'),
                const SizedBox(height: 12),
                EngagementCard(
                  propertyViews: d.propertyViews,
                  savedCount: d.savedCount,
                  likedCount: d.likedCount,
                  messages: d.messages,
                  appOpens: d.appOpens,
                ),
                const SizedBox(height: 20),
                const AnalyticsSectionHeader('Quick Links'),
                const SizedBox(height: 12),
                AnalyticsCard(
                  child: Column(
                    children: [
                      _ActivityLink(
                        icon: Icons.bookmark_outline,
                        label: 'Saved Properties',
                        onTap: () => context.push('/saved'),
                      ),
                      const Divider(height: 16),
                      _ActivityLink(
                        icon: Icons.history,
                        label: 'Viewing History',
                        onTap: () => context.push('/profile/viewing-history'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActivityLink extends StatelessWidget {
  const _ActivityLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
