import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../repositories/user_profile_repository.dart';
import 'profile_subscreen_widgets.dart';

/// Viewing history screen — mirrors iOS `ViewingHistoryView`.
class ViewingHistoryScreen extends StatefulWidget {
  const ViewingHistoryScreen({super.key, required this.userId});

  final String userId;

  @override
  State<ViewingHistoryScreen> createState() => _ViewingHistoryScreenState();
}

class _ViewingHistoryScreenState extends State<ViewingHistoryScreen> {
  Future<List<Map<String, dynamic>>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() =>
      context.read<UserProfileRepository>().getViewingHistory(widget.userId);

  Future<void> _refresh() async {
    setState(() => _future = _fetch());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return ProfileGroupedScaffold(
      title: 'Viewing History',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ProfileErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const ProfileEmptyState(
              icon: Icons.history,
              title: 'No viewing history',
              subtitle: 'Properties you view will appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 76, endIndent: 16),
              itemBuilder: (context, i) => _HistoryTile(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final propertyId = item['propertyId'] as String? ?? item['id'] as String? ?? '';
    final title = item['propertyTitle'] as String? ?? 'Property';
    final imageUrl = item['heroImageUrl'] as String?;
    final price = (item['price'] as num?)?.toDouble();
    final currency = item['currencyCode'] as String? ?? 'USD';
    final city = item['city'] as String? ?? '';
    final state = item['state'] as String? ?? '';
    final ts = item['viewedAt'];
    final viewedAt = ts is Timestamp ? ts.toDate() : null;

    final subtitle = [city, state].where((s) => s.isNotEmpty).join(', ');
    final priceStr = price != null
        ? NumberFormat.simpleCurrency(name: currency).format(price)
        : '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          if (priceStr.isNotEmpty)
            Text(
              priceStr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          if (viewedAt != null)
            Text(
              'Viewed ${DateFormat.yMMMd().format(viewedAt)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
        ],
      ),
      onTap: propertyId.isNotEmpty
          ? () => context.push('/property/$propertyId')
          : null,
    );
  }

  Widget _placeholder() => Container(
        width: 60,
        height: 60,
        color: AppColors.surfaceVariant,
        child: const Icon(Icons.home_outlined,
            size: 28, color: AppColors.textTertiary),
      );
}
