import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'push_notification_service.dart';

/// Schedules a local "1 hour before" appointment reminder — mirrors iOS
/// `NotificationHelper.scheduleAppointmentReminder` (`date - 3600s`), which
/// runs independently of the FCM push notification for the same event.
class AppointmentReminderService {
  AppointmentReminderService._();
  static final AppointmentReminderService instance =
      AppointmentReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _channelId = 'appointment_reminders';
  static const _channelName = 'Appointment Reminders';
  static const _channelDescription =
      'Reminders for upcoming property appointments';

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      // Fall back to UTC if the platform timezone name isn't in the tz
      // database (rare, e.g. some emulator configurations).
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Stable notification id derived from the Firestore document id, so
  /// scheduling/cancelling always target the same slot.
  int _notificationId(String appointmentId) => appointmentId.hashCode & 0x7fffffff;

  /// Schedules a reminder for one hour before [date], unless that moment has
  /// already passed (mirrors iOS, which silently skips past-due reminders).
  Future<void> scheduleReminder({
    required String appointmentId,
    required String propertyTitle,
    required DateTime date,
  }) async {
    try {
      await init();
      final reminderTime = date.subtract(const Duration(hours: 1));
      if (reminderTime.isBefore(DateTime.now())) return;

      await _plugin.zonedSchedule(
        _notificationId(appointmentId),
        'Upcoming Appointment',
        'Your appointment for $propertyTitle is in 1 hour.',
        tz.TZDateTime.from(reminderTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'propertypulse://appointment/$appointmentId',
      );
    } catch (e) {
      // Reminders are best-effort — never block appointment creation on this.
      debugPrint('AppointmentReminderService: scheduleReminder failed: $e');
    }
  }

  /// Cancels a previously scheduled reminder — call on cancel/reject/reschedule.
  Future<void> cancelReminder(String appointmentId) async {
    try {
      await _plugin.cancel(_notificationId(appointmentId));
    } catch (e) {
      debugPrint('AppointmentReminderService: cancelReminder failed: $e');
    }
  }

  bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    // payload is `propertypulse://appointment/{id}` — reuse the same
    // `/appointment/{id}` route the deep link and push notification use.
    final id = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.host;
    if (id.isEmpty) return;
    PushNotificationService.goToPath('/appointment/$id');
  }
}
