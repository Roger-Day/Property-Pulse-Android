import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../constants/app_colors.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/user_profile_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  Stream<List<NotificationModel>>? _stream;
  String? _streamUid; // tracks the uid used to build the current stream

  Stream<List<NotificationModel>> _buildStream() {
    final uid = context.read<AuthProvider>().user?.uid;
    _streamUid = uid;
    return uid != null
        ? context.read<UserProfileRepository>().watchNotifications(uid)
        : const Stream.empty();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild the stream if the user uid changes (e.g. sign-in after first mount).
    final currentUid = context.read<AuthProvider>().user?.uid;
    if (_stream == null || currentUid != _streamUid) {
      _stream = _buildStream();
    }
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _stream = _buildStream());
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  Future<void> _markAllRead() async {
    HapticFeedback.lightImpact();
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    await context.read<UserProfileRepository>().markAllNotificationsRead(uid);
  }

  Future<void> _markRead(String id) async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;
    await context.read<UserProfileRepository>().markNotificationRead(
          userId: uid,
          notificationId: id,
        );
  }

  @override
  Widget build(BuildContext context) {
    final inboxStream = _stream ?? const Stream<List<NotificationModel>>.empty();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        // Same visibility as iOS `NotificationCenterView`: show whenever the inbox
        // has rows (trailing toolbar), not only when some are unread.
        actions: [
          StreamBuilder<List<NotificationModel>>(
            stream: inboxStream,
            builder: (context, snap) {
              final items = snap.data ?? [];
              if (items.isEmpty) return const SizedBox.shrink();
              return TextButton(
                onPressed: _markAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                ),
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: inboxStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _NotificationsLoadingSkeleton();
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.notifications_none_outlined,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You have no notifications yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final n = items[index];
                return _NotificationTile(
                  notification: n,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    if (!n.isRead) await _markRead(n.id);
                    if (!context.mounted) return;
                    _handleTap(context, n);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _handleTap(BuildContext context, NotificationModel n) {
    switch (n.type) {
      case 'appointment':
        context.go('/profile/appointments');
        return;
      case 'message':
        final tid = n.referenceId;
        if (tid != null && tid.isNotEmpty) {
          context.go('/messages/thread/$tid');
        } else {
          context.go('/messages');
        }
        return;
      case 'listing':
      case 'property':
        final pid = n.referenceId;
        if (pid == null || pid.isEmpty) return;
        context.push('/property/$pid');
        return;
      default:
        return;
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final NotificationModel notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread
            ? AppColors.primary.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread indicator dot
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unread ? AppColors.primary : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w400,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _relativeTime(notification.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            _typeIcon(notification.type),
          ],
        ),
      ),
    );
  }

  Widget _typeIcon(String? type) {
    IconData icon = Icons.notifications_outlined;
    Color color = AppColors.textSecondary;
    switch (type) {
      case 'appointment':
        icon = Icons.calendar_month_outlined;
        color = const Color(0xFF7C3AED);
        break;
      case 'message':
        icon = Icons.chat_bubble_outline;
        color = AppColors.primary;
        break;
      case 'listing':
      case 'property':
        icon = Icons.home_outlined;
        color = AppColors.secondary;
        break;
      default:
        break;
    }
    return Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

class _NotificationsLoadingSkeleton extends StatelessWidget {
  const _NotificationsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F4F6);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: shine,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 7,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, __) {
          final color = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);
          final line = isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 6),
                      Container(width: 220, height: 13, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5))),
                      const SizedBox(height: 6),
                      Container(width: 80, height: 11, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(4))),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
