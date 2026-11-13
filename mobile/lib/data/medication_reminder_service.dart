import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules daily device notifications for the medication times saved by the user.
class MedicationReminderService {
  MedicationReminderService._();

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _deviceChannel = MethodChannel('jeevan/device');
  static Future<void>? _initializing;

  static Future<void> _initialize() async {
    if (_initializing != null) return _initializing!;
    _initializing = _initializeOnce();
    try {
      await _initializing;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  static Future<void> _initializeOnce() async {
    tz_data.initializeTimeZones();
    try {
      final zoneId = await _deviceChannel.invokeMethod<String>('getTimeZoneId');
      if (zoneId != null && zoneId.isNotEmpty) {
        tz.setLocalLocation(tz.getLocation(zoneId));
      }
    } catch (_) {
      // Keep the timezone package default if the device channel is unavailable.
    }
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> sync(List<Map<String, dynamic>> medications) async {
    await _initialize();
    await _notifications.cancelAll();
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        'jeevan_medication_reminders',
        'Medication reminders',
        channelDescription: 'Daily reminders for scheduled medications.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    var id = 1000;
    for (final medication in medications) {
      final name = (medication['name'] ?? 'Medication').toString().trim();
      final dosage = (medication['dosage'] ?? '').toString().trim();
      final times = (medication['reminderTimes'] as List?)
              ?.map((value) => value.toString().trim())
              .toSet()
              .toList() ??
          const <String>[];
      for (final time in times) {
        final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
        if (match == null) continue;
        final hour = int.tryParse(match.group(1)!) ?? 24;
        final minute = int.tryParse(match.group(2)!) ?? 60;
        if (hour > 23 || minute > 59) continue;
        final now = tz.TZDateTime.now(tz.local);
        var scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        );
        if (!scheduled.isAfter(now)) {
          scheduled = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day + 1,
            hour,
            minute,
          );
        }
        await _notifications.zonedSchedule(
          id++,
          'Medication reminder',
          dosage.isEmpty
              ? 'Time to take $name.'
              : 'Time to take $name ($dosage).',
          scheduled,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: name,
        );
      }
    }
  }
}
