import 'package:flutter_test/flutter_test.dart';
import 'package:jeevan_app/core/triage.dart';
import 'package:jeevan_app/data/models.dart';

void main() {
  group('localTriage', () {
    test('returns normal for healthy resting vitals', () {
      const vitals = Vitals(heartRate: 72, spo2: 98, temperature: 36.8, ecgBpm: 74);
      final res = localTriage(vitals);

      expect(res.overallStatus, 'normal');
      expect(res.riskScore, 10);
      expect(res.redFlags, isEmpty);
      expect(res.findings, hasLength(4));
    });

    test('returns warning for moderate fever and tachycardia', () {
      const vitals = Vitals(heartRate: 112, spo2: 97, temperature: 38.8);
      final res = localTriage(vitals);

      expect(res.overallStatus, 'warning');
      expect(res.riskScore, greaterThanOrEqualTo(65));
      expect(res.redFlags, isNotEmpty);
    });

    test('returns critical for severe hypoxemia', () {
      const vitals = Vitals(heartRate: 88, spo2: 86, temperature: 36.9);
      final res = localTriage(vitals);

      expect(res.overallStatus, 'critical');
      expect(res.riskScore, greaterThanOrEqualTo(90));
      expect(res.redFlags.any((f) => f.contains('hypoxemia')), isTrue);
    });

    test('flags attention when ECG leads are off', () {
      const vitals = Vitals(heartRate: 75, spo2: 98, temperature: 36.6, leadOff: true);
      final res = localTriage(vitals);

      expect(res.overallStatus, 'attention');
      expect(res.findings.any((f) => f.metric == 'ECG' && f.value == 'LEADS OFF'), isTrue);
    });
  });
}
// Jeevan sync: 2026-11-13
