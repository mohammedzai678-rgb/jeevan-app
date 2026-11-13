import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'ble_service.dart';

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
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // Inexact scheduling remains enabled when exact alarms are unavailable.
    }
  }

  static Future<void> sync(List<Map<String, dynamic>> medications) async {
    await _initialize();
    await _notifications.cancelAll();
    final voiceSchedules = <Map<String, dynamic>>[];
    var voiceId = 3000;
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        'jeevan_medication_alerts_v3',
        'Medication reminders',
        channelDescription: 'Daily reminders for scheduled medications.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: false,
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
        voiceSchedules.add({
          'id': voiceId++,
          'name': name,
          'time':
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        });
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
        final android = _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        bool exactAllowed = false;
        try {
          exactAllowed =
              await android?.canScheduleExactNotifications() ?? false;
        } catch (_) {}
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
          androidScheduleMode: exactAllowed
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: name,
        );
      }
    }
    try {
      await _deviceChannel.invokeMethod<void>(
        'syncMedicationVoiceAlarms',
        voiceSchedules,
      );
    } catch (_) {
      // Other platforms use the local notification's audible reminder.
    }
  }

  static Future<void> syncWatchSchedule(
    List<Map<String, dynamic>> medications,
    BleService ble,
  ) async {
    if (ble.current != BleState.connected) return;
    final times = <String>{};
    for (final medication in medications) {
      final values = medication['reminderTimes'];
      if (values is! List) continue;
      for (final value in values) {
        final match =
            RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.toString().trim());
        if (match == null) continue;
        final hour = int.tryParse(match.group(1)!) ?? 24;
        final minute = int.tryParse(match.group(2)!) ?? 60;
        if (hour > 23 || minute > 59) continue;
        times.add(
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
      }
    }
    final ordered = times.toList()..sort();
    await ble.sendCommand('set_schedule:${ordered.take(12).join(',')}');
  }

  static Future<void> showSosAlert() async {
    await _initialize();
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      'Emergency SOS',
      'VitaWatch SOS was triggered. Open JeevanCare now.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'jeevan_emergency_alerts_v3',
          'Emergency alerts',
          channelDescription: 'Urgent alerts from the VitaWatch SOS button.',
          importance: Importance.max,
          priority: Priority.max,
          playSound: false,
          enableVibration: true,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
        ),
      ),
    );
    await speakPrompt('Help me! Help me! Emergency.', urgent: true);
  }

  static Future<void> showMedicationAlert(String medication) async {
    await _initialize();
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      'Medication reminder',
      'Time to take $medication.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'jeevan_medication_alerts_v3',
          'Medication reminders',
          channelDescription: 'Sound and vibration for scheduled medications.',
          importance: Importance.max,
          priority: Priority.max,
          playSound: false,
          enableVibration: true,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
    );
    await speakPrompt('Take your medicine. $medication.');
  }

  static Future<void> speakPrompt(String text, {bool urgent = false}) async {
    try {
      await _deviceChannel.invokeMethod<void>(
        'speakPrompt',
        {'text': text, 'urgent': urgent},
      );
    } catch (_) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}
// Jeevan sync: 2026-11-13
