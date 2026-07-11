import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../services/push_notification_service.dart';

/// Mirrors iOS in-app notification banner — shows a styled overlay card when
/// an FCM message arrives while the app is in the foreground.
///
/// Wrap over the root scaffold:
/// ```dart
/// InAppNotificationOverlay(child: myApp)
/// ```
class InAppNotificationOverlay extends StatefulWidget {
  const InAppNotificationOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<InAppNotificationOverlay> createState() =>
      _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState
    extends State<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  RemoteMessage? _current;
  Timer? _dismissTimer;
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(
            begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _sub = PushNotificationService.instance.foregroundMessages
        .listen(_showBanner);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _showBanner(RemoteMessage message) {
    setState(() => _current = message);
    _ctrl.forward(from: 0);
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _current = null);
    });
  }

  void _onTap() {
    final data = _current?.data ?? {};
    _dismiss();
    final route = PushNotificationService.routeForData(data);
    if (mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slide,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _BannerCard(
                    message: _current!,
                    onTap: _onTap,
                    onDismiss: _dismiss,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.message,
    required this.onTap,
    required this.onDismiss,
  });
  final RemoteMessage message;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  IconData _iconFor(String? type) {
    switch (type) {
      case 'message':
      case 'chat':
        return Icons.message;
      case 'booking':
      case 'booking_confirmed':
        return Icons.hotel;
      case 'appointment':
        return Icons.calendar_month;
      case 'property':
      case 'price_drop':
        return Icons.home;
      case 'verification':
        return Icons.verified;
      case 'review':
        return Icons.star;
      case 'lead':
        return Icons.people;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title'] as String? ?? 'Property Pulse';
    final body =
        notification?.body ?? message.data['body'] as String? ?? '';
    final type = message.data['type'] as String?;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // App icon / type icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconFor(type),
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              // Title + body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Dismiss
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: onDismiss,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                    minWidth: 28, minHeight: 28),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
