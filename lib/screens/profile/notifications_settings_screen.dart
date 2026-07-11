import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../repositories/user_profile_repository.dart';
import '../../services/push_notification_service.dart';
import 'profile_subscreen_widgets.dart';

/// Mirrors iOS `NotificationSettingsView`: sections, compact toggles, immediate
/// persistence, device token panel, trailing Done.
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key, required this.userId});

  final String userId;

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool _loading = true;

  bool _newProperties = true;
  bool _priceChanges = true;
  bool _statusUpdates = true;
  bool _messageNotifications = true;
  bool _appointmentReminders = true;
  bool _marketing = false;

  PermissionStatus _systemPermission = PermissionStatus.denied;
  String? _fcmTokenPreview;

  @override
  void initState() {
    super.initState();
    _fcmTokenPreview = PushNotificationService.instance.currentToken;
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<UserProfileRepository>();
    final data = await repo.getNotificationSettings(widget.userId);
    final perm = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _newProperties = _readBool(data, ['newListings', 'newPropertyAlerts'], true);
      _priceChanges =
          _readBool(data, ['priceChanges', 'priceChangeAlerts'], true);
      _statusUpdates =
          _readBool(data, ['statusUpdates', 'statusChangeAlerts'], true);
      _messageNotifications =
          _readBool(data, ['messages', 'messageNotifications'], true);
      _appointmentReminders =
          _readBool(data, ['appointments', 'appointmentReminders'], true);
      _marketing = _readBool(data, ['marketing'], false);
      _systemPermission = perm;
      _fcmTokenPreview = PushNotificationService.instance.currentToken;
      _loading = false;
    });
  }

  static bool _readBool(
    Map<String, dynamic> data,
    List<String> keys,
    bool fallback,
  ) {
    for (final k in keys) {
      final v = data[k];
      if (v is bool) return v;
    }
    return fallback;
  }

  Map<String, dynamic> get _prefsPayload => {
        'newListings': _newProperties,
        'priceChanges': _priceChanges,
        'statusUpdates': _statusUpdates,
        'messages': _messageNotifications,
        'appointments': _appointmentReminders,
        'marketing': _marketing,
      };

  Future<void> _persist() async {
    try {
      await context.read<UserProfileRepository>().updateNotificationSettings(
            widget.userId,
            _prefsPayload,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preferences: $e')),
      );
    }
  }

  Future<void> _refreshSystemPermission() async {
    final perm = await Permission.notification.status;
    if (!mounted) return;
    setState(() => _systemPermission = perm);
  }

  Future<void> _requestSystemNotifications() async {
    await Permission.notification.request();
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await PushNotificationService.instance.refreshFcmToken();
    final perm = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _systemPermission = perm;
      _fcmTokenPreview = PushNotificationService.instance.currentToken;
    });
    final granted =
        perm.isGranted || perm == PermissionStatus.provisional;
    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifications enabled for this device')),
      );
    }
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
    await _refreshSystemPermission();
    if (!mounted) return;
    setState(() {
      _fcmTokenPreview = PushNotificationService.instance.currentToken;
    });
  }

  Future<void> _retryToken() async {
    final t = await PushNotificationService.instance.refreshFcmToken();
    if (!mounted) return;
    setState(() => _fcmTokenPreview = t);
  }

  bool get _authorized =>
      _systemPermission.isGranted ||
      _systemPermission == PermissionStatus.provisional;

  bool get _needsSystemEnable =>
      !_authorized && _systemPermission != PermissionStatus.provisional;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return ProfileGroupedScaffold(
        title: 'Notifications',
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Done'),
          ),
        ],
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ProfileGroupedScaffold(
      title: 'Notifications',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
      child: ListView(
        padding: ProfileLayout.pagePadding,
        children: [
          const _NotificationSectionTitle('Notification Status'),
          ProfileGroupedCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _authorized
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: _authorized ? AppColors.success : AppColors.error,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _authorized
                                  ? 'Notifications Enabled'
                                  : 'Notifications Disabled',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _authorized
                                  ? "You'll receive alerts for important updates"
                                  : 'Enable notifications to stay updated',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_needsSystemEnable) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _requestSystemNotifications,
                          child: const Text('Enable Notifications'),
                        ),
                        OutlinedButton(
                          onPressed: _openSystemSettings,
                          child: const Text('Open Settings'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _NotificationSectionTitle('Property Alerts'),
          ProfileGroupedCard(
            child: Column(
              children: [
                _NotificationToggleRow(
                  title: 'New Properties',
                  value: _newProperties,
                  onChanged: (v) {
                    setState(() => _newProperties = v);
                    _persist();
                  },
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _NotificationToggleRow(
                  title: 'Price Changes',
                  value: _priceChanges,
                  onChanged: (v) {
                    setState(() => _priceChanges = v);
                    _persist();
                  },
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _NotificationToggleRow(
                  title: 'Status Updates',
                  value: _statusUpdates,
                  onChanged: (v) {
                    setState(() => _statusUpdates = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _NotificationSectionTitle('Communication'),
          ProfileGroupedCard(
            child: Column(
              children: [
                _NotificationToggleRow(
                  title: 'Message Notifications',
                  value: _messageNotifications,
                  onChanged: (v) {
                    setState(() => _messageNotifications = v);
                    _persist();
                  },
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _NotificationToggleRow(
                  title: 'Appointment Reminders',
                  value: _appointmentReminders,
                  onChanged: (v) {
                    setState(() => _appointmentReminders = v);
                    _persist();
                  },
                ),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _NotificationToggleRow(
                  title: 'Offers & updates',
                  subtitle: 'Tips, offers, and product updates',
                  value: _marketing,
                  onChanged: (v) {
                    setState(() => _marketing = v);
                    _persist();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _NotificationSectionTitle('Device Information'),
          ProfileGroupedCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_fcmTokenPreview != null &&
                      _fcmTokenPreview!.isNotEmpty) ...[
                    Text(
                      'Device Token',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _fcmTokenPreview!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontFamily: 'monospace',
                          ),
                    ),
                  ] else ...[
                    Text(
                      'No Device Token',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Device token not available. This is needed for push notifications.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () async {
                            await _requestSystemNotifications();
                          },
                          child: const Text('Check Status'),
                        ),
                        OutlinedButton(
                          onPressed: _retryToken,
                          child: const Text('Retry Token'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NotificationSectionTitle extends StatelessWidget {
  const _NotificationSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 16, bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Compact row matching iOS `ToggleRow` (title + switch, optional subtitle).
class _NotificationToggleRow extends StatelessWidget {
  const _NotificationToggleRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: scheme.primary,
    );
  }
}
