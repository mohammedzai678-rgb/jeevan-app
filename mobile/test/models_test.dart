import 'package:flutter_test/flutter_test.dart';
import 'package:jeevan_app/data/models.dart';

void main() {
  group('Models JSON parsing', () {
    test('DeviceSnapshot.fromJson parses nested vitals, analysis, and reminder', () {
      final snap = DeviceSnapshot.fromJson({
        'device_id': 'VITAWATCH-01',
        'online': true,
        'sensor': 'read_max30102',
        'command': 'auto',
        'signal_quality': 'GOOD',
        'rssi': -58,
        'seq': 42,
        'vitals': {
          'heart_rate': 76,
          'spo2': 99,
          'temperature': 36.7,
          'ecg_bpm': 75,
          'lead_off': false,
          'finger_detected': true,
        },
        'analysis': {
          'overall_status': 'normal',
          'risk_score': 10,
          'summary': 'All measured vitals are normal.',
          'findings': [
            {
              'metric': 'Heart Rate',
              'value': '76 BPM',
              'status': 'normal',
              'normal_range': '60-100 BPM',
              'explanation': 'Normal resting range.',
              'recommendation': 'No action needed.',
            },
          ],
          'red_flags': <String>[],
        },
        'reminder': {
          'active': true,
          'slot': '08:00',
          'medication': 'Aspirin 75mg',
        },
      });

      expect(snap.deviceId, 'VITAWATCH-01');
      expect(snap.online, isTrue);
      expect(snap.sensor, 'read_max30102');
      expect(snap.rssi, -58);
      expect(snap.seq, 42);
      expect(snap.vitals.heartRate, 76);
      expect(snap.vitals.spo2, 99);
      expect(snap.vitals.temperature, 36.7);
      expect(snap.vitals.fingerDetected, isTrue);
      expect(snap.analysis.overallStatus, 'normal');
      expect(snap.analysis.findings, hasLength(1));
      expect(snap.reminder.active, isTrue);
      expect(snap.reminder.medication, 'Aspirin 75mg');
    });

    test('SosEvent.fromJson parses nested location and active status', () {
      final ev = SosEvent.fromJson({
        'event_id': 'evt_991',
        'room_id': 'room_sos_991',
        'source': 'watch_button',
        'status': 'active',
        'maps_url': 'https://maps.google.com/?q=12.9716,77.5946',
        'location': {'lat': 12.9716, 'lng': 77.5946},
        'timestamp': '2026-11-07T14:00:00Z',
      });

      expect(ev.eventId, 'evt_991');
      expect(ev.roomId, 'room_sos_991');
      expect(ev.source, 'watch_button');
      expect(ev.active, isTrue);
      expect(ev.lat, closeTo(12.9716, 0.0001));
      expect(ev.lng, closeTo(77.5946, 0.0001));
    });
  });
}
