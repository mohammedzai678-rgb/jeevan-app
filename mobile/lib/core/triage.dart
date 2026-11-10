/// On-device port of server/app/triage.py so BLE samples get an instant status with zero network.
library;

import '../data/models.dart';

Analysis localTriage(Vitals v) {
  final findings = <Finding>[];
  final flags = <String>[];
  var crit = 0, warn = 0, att = 0;

  void add(String metric, String value, String status, String range, String why, String rec) {
    findings.add(Finding(metric, value, status, range, why, rec));
    if (status == 'critical') crit++;
    if (status == 'warning') warn++;
    if (status == 'attention') att++;
  }

  final hr = v.heartRate;
  if (hr != null) {
    if (hr < 40 || hr > 150) {
      add('Heart Rate', '$hr BPM', 'critical', '60-100 BPM', 'Severe ${hr < 40 ? 'bradycardia' : 'tachycardia'}.', 'Seek urgent medical attention.');
      flags.add('Critical heart rate: $hr BPM');
    } else if (hr < 50 || hr > 120) {
      add('Heart Rate', '$hr BPM', 'warning', '60-100 BPM', 'Marked ${hr < 50 ? 'bradycardia' : 'tachycardia'}.', 'Rest, hydrate and recheck.');
      flags.add('Abnormal heart rate: $hr BPM');
    } else if (hr > 100 || hr < 60) {
      add('Heart Rate', '$hr BPM', 'attention', '60-100 BPM', 'Mildly ${hr > 100 ? 'elevated' : 'low'}.', 'Relax and recheck at rest.');
    } else {
      add('Heart Rate', '$hr BPM', 'normal', '60-100 BPM', 'Normal resting range.', 'No action needed.');
    }
  }

  final s = v.spo2;
  if (s != null) {
    if (s < 90) {
      add('SpO2', '$s%', 'critical', '95-100%', 'Severe hypoxemia.', 'Seek urgent care; sit upright.');
      crit++; // weighted x2 like the server
      flags.add('Severe hypoxemia: SpO2 $s%');
    } else if (s < 94) {
      add('SpO2', '$s%', 'warning', '95-100%', 'Low saturation (or poor contact).', 'Warm finger, stay still, rescan.');
      flags.add('Low SpO2: $s%');
    } else if (s < 95) {
      add('SpO2', '$s%', 'attention', '95-100%', 'Borderline.', 'Monitor closely.');
    } else {
      add('SpO2', '$s%', 'normal', '95-100%', 'Optimal.', 'No action needed.');
    }
  }

  final t = v.temperature;
  if (t != null) {
    final ts = t.toStringAsFixed(1);
    if (t >= 40 || t < 34) {
      add('Temperature', '$ts °C', 'critical', '36.1-37.2 °C', t >= 40 ? 'Hyperthermia range.' : 'Hypothermia range.', 'Seek emergency care.');
      flags.add('Critical temperature: $ts °C');
    } else if (t >= 38.5 || t < 35.5) {
      add('Temperature', '$ts °C', 'warning', '36.1-37.2 °C', t >= 38.5 ? 'Fever.' : 'Subnormal temperature.', 'Rest, fluids, monitor.');
      flags.add('${t >= 38.5 ? 'Fever' : 'Low temperature'}: $ts °C');
    } else if (t >= 37.5 || t < 36.0) {
      add('Temperature', '$ts °C', 'attention', '36.1-37.2 °C', 'Slightly out of range.', 'Hydrate and recheck.');
    } else {
      add('Temperature', '$ts °C', 'normal', '36.1-37.2 °C', 'Normal.', 'No action needed.');
    }
  }

  if (v.leadOff == true) {
    add('ECG', 'LEADS OFF', 'attention', 'n/a', 'Electrodes disconnected.', 'Attach electrodes firmly.');
  } else if (v.ecgBpm != null) {
    final e = v.ecgBpm!;
    if (e < 45 || e > 145) {
      add('ECG', '$e BPM', 'critical', '60-100 BPM', 'Marked ECG rate abnormality.', 'Check electrodes; seek a clinical ECG.');
      flags.add('ECG rate abnormality: $e BPM');
    } else if (hr != null && (e - hr).abs() > 20) {
      add('ECG', '$e BPM', 'warning', '60-100 BPM', 'Pulse and ECG disagree.', 'Check for motion or loose sensors.');
      flags.add('Pulse/ECG mismatch: $hr vs $e');
    } else {
      add('ECG', '$e BPM', 'normal', '60-100 BPM', 'Regular rate.', 'No action needed.');
    }
  }

  if (crit > 0) {
    return Analysis(overallStatus: 'critical', riskScore: (85 + crit * 5).clamp(0, 100), summary: 'Critical: seek medical help now.', findings: findings, redFlags: flags);
  }
  if (warn > 0) {
    return Analysis(overallStatus: 'warning', riskScore: (55 + warn * 10).clamp(0, 80), summary: '$warn metric(s) outside the normal range.', findings: findings, redFlags: flags);
  }
  if (att > 0) {
    return Analysis(overallStatus: 'attention', riskScore: 35, summary: 'Minor deviations. Rest and recheck.', findings: findings, redFlags: flags);
  }
  if (findings.isEmpty) return const Analysis(summary: 'Waiting for sensor data.');
  return Analysis(overallStatus: 'normal', riskScore: 10, summary: 'All measured vitals are normal.', findings: findings);
}
