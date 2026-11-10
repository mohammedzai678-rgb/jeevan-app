/// Hand-written models (no codegen) mirroring the FastAPI JSON.
library;

int? _int(Object? v) => v is num ? v.toInt() : null;
double? _dbl(Object? v) => v is num ? v.toDouble() : null;

class Vitals {
  final int? heartRate;
  final int? spo2;
  final double? temperature;
  final int? ecgBpm;
  final int? ecgValue;
  final bool? leadOff;
  final bool? fingerDetected;

  const Vitals({this.heartRate, this.spo2, this.temperature, this.ecgBpm, this.ecgValue, this.leadOff, this.fingerDetected});

  factory Vitals.fromJson(Map<String, dynamic> j) => Vitals(
        heartRate: _int(j['heart_rate']),
        spo2: _int(j['spo2']),
        temperature: _dbl(j['temperature']),
        ecgBpm: _int(j['ecg_bpm']),
        ecgValue: _int(j['ecg_value']),
        leadOff: j['lead_off'] as bool?,
        fingerDetected: j['finger_detected'] as bool?,
      );

  Vitals copyWith({int? heartRate, int? spo2, double? temperature, int? ecgBpm}) => Vitals(
        heartRate: heartRate ?? this.heartRate,
        spo2: spo2 ?? this.spo2,
        temperature: temperature ?? this.temperature,
        ecgBpm: ecgBpm ?? this.ecgBpm,
        ecgValue: ecgValue,
        leadOff: leadOff,
        fingerDetected: fingerDetected,
      );

  bool get isEmpty => heartRate == null && spo2 == null && temperature == null && ecgBpm == null;
}

class Finding {
  final String metric, value, status, normalRange, explanation, recommendation;
  const Finding(this.metric, this.value, this.status, this.normalRange, this.explanation, this.recommendation);
  factory Finding.fromJson(Map<String, dynamic> j) => Finding(
        '${j['metric']}',
        '${j['value']}',
        '${j['status']}',
        '${j['normal_range'] ?? ''}',
        '${j['explanation'] ?? ''}',
        '${j['recommendation'] ?? ''}',
      );
}

class Analysis {
  final String overallStatus;
  final int riskScore;
  final String summary;
  final List<Finding> findings;
  final List<String> redFlags;
  const Analysis({this.overallStatus = 'normal', this.riskScore = 0, this.summary = '', this.findings = const [], this.redFlags = const []});

  factory Analysis.fromJson(Map<String, dynamic> j) => Analysis(
        overallStatus: (j['overall_status'] as String?) ?? 'normal',
        riskScore: _int(j['risk_score']) ?? 0,
        summary: (j['summary'] as String?) ?? '',
        findings: ((j['findings'] as List?) ?? const []).map((e) => Finding.fromJson(e as Map<String, dynamic>)).toList(),
        redFlags: ((j['red_flags'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

class Reminder {
  final bool active;
  final String slot, medication;
  const Reminder({this.active = false, this.slot = '', this.medication = ''});
  factory Reminder.fromJson(Map<String, dynamic> j) =>
      Reminder(active: j['active'] == true, slot: '${j['slot'] ?? ''}', medication: '${j['medication'] ?? ''}');
}

/// Where the displayed numbers came from; drives the latency badge.
enum VitalsSource { ble, cloud, none }

class DeviceSnapshot {
  final String deviceId;
  final bool online;
  final String sensor, command, signalQuality;
  final int? rssi;
  final int seq;
  final Vitals vitals;
  final Analysis analysis;
  final Reminder reminder;
  final VitalsSource source;
  final DateTime receivedAt;

  DeviceSnapshot({
    required this.deviceId,
    this.online = false,
    this.sensor = 'idle',
    this.command = '',
    this.signalQuality = 'UNKNOWN',
    this.rssi,
    this.seq = 0,
    this.vitals = const Vitals(),
    this.analysis = const Analysis(),
    this.reminder = const Reminder(),
    this.source = VitalsSource.cloud,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory DeviceSnapshot.fromJson(Map<String, dynamic> j) => DeviceSnapshot(
        deviceId: '${j['device_id']}',
        online: j['online'] == true,
        sensor: '${j['sensor'] ?? 'idle'}',
        command: '${j['command'] ?? ''}',
        signalQuality: '${j['signal_quality'] ?? 'UNKNOWN'}',
        rssi: _int(j['rssi']),
        seq: _int(j['seq']) ?? 0,
        vitals: Vitals.fromJson((j['vitals'] as Map?)?.cast<String, dynamic>() ?? {}),
        analysis: Analysis.fromJson((j['analysis'] as Map?)?.cast<String, dynamic>() ?? {}),
        reminder: Reminder.fromJson((j['reminder'] as Map?)?.cast<String, dynamic>() ?? {}),
      );

  DeviceSnapshot copyWith({bool? online, Vitals? vitals, Analysis? analysis, Reminder? reminder, VitalsSource? source}) => DeviceSnapshot(
        deviceId: deviceId,
        online: online ?? this.online,
        sensor: sensor,
        command: command,
        signalQuality: signalQuality,
        rssi: rssi,
        seq: seq,
        vitals: vitals ?? this.vitals,
        analysis: analysis ?? this.analysis,
        reminder: reminder ?? this.reminder,
        source: source ?? this.source,
      );
}

class SosEvent {
  final String eventId, roomId, source, status, mapsUrl;
  final double lat, lng;
  final DateTime time;
  final Map<String, dynamic> deliveryResults;

  SosEvent({
    required this.eventId,
    required this.roomId,
    required this.source,
    required this.status,
    required this.mapsUrl,
    required this.lat,
    required this.lng,
    required this.time,
    this.deliveryResults = const {},
  });

  bool get active => status == 'active';

  factory SosEvent.fromJson(Map<String, dynamic> j) {
    final loc = (j['location'] as Map?)?.cast<String, dynamic>() ?? {};
    return SosEvent(
      eventId: '${j['event_id']}',
      roomId: '${j['room_id'] ?? ''}',
      source: '${j['source'] ?? ''}',
      status: '${j['status'] ?? 'active'}',
      mapsUrl: '${j['maps_url'] ?? ''}',
      lat: _dbl(loc['lat']) ?? 0,
      lng: _dbl(loc['lng']) ?? 0,
      time: DateTime.tryParse('${j['timestamp']}')?.toLocal() ?? DateTime.now(),
    );
  }

  SosEvent copyWith({String? status, double? lat, double? lng, Map<String, dynamic>? deliveryResults}) => SosEvent(
        eventId: eventId,
        roomId: roomId,
        source: source,
        status: status ?? this.status,
        mapsUrl: mapsUrl,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        time: time,
        deliveryResults: deliveryResults ?? this.deliveryResults,
      );
}

class Reading {
  final String id;
  final DateTime at;
  final int heartRate, spo2;
  final double temperature;
  final String status;
  const Reading(this.at, this.heartRate, this.spo2, this.temperature, this.status, {this.id = ''});
  factory Reading.fromJson(Map<String, dynamic> j) => Reading(
        DateTime.tryParse('${j['recorded_at']}')?.toLocal() ?? DateTime.now(),
        _int(j['heart_rate']) ?? 0,
        _int(j['spo2']) ?? 0,
        _dbl(j['temperature']) ?? 0,
        ((j['ai_analysis'] as Map?)?['overall_status'] as String?) ?? 'normal',
        id: '${j['id'] ?? ''}',
      );
}

class Session {
  final String accessToken, refreshToken, userId;
  final String? email;
  final DateTime expiresAt;
  const Session(this.accessToken, this.refreshToken, this.userId, this.email, this.expiresAt);

  bool get expiringSoon => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
        'a': accessToken,
        'r': refreshToken,
        'u': userId,
        'e': email,
        'x': expiresAt.millisecondsSinceEpoch,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        j['a'] as String,
        j['r'] as String,
        j['u'] as String,
        j['e'] as String?,
        DateTime.fromMillisecondsSinceEpoch(j['x'] as int),
      );
}

class Source {
  final int n;
  final String title, heading, snippet;
  final bool private;
  const Source(this.n, this.title, this.heading, this.snippet, this.private);
  factory Source.fromJson(Map<String, dynamic> j) =>
      Source(_int(j['n']) ?? 0, '${j['title']}', '${j['heading']}', '${j['snippet']}', j['private'] == true);
}

class ChatMessage {
  final bool fromUser;
  final String text;
  final List<Source> sources;
  final bool emergency, fallback, streaming;
  final int? firstTokenMs;
  const ChatMessage({
    required this.fromUser,
    required this.text,
    this.sources = const [],
    this.emergency = false,
    this.fallback = false,
    this.streaming = false,
    this.firstTokenMs,
  });

  ChatMessage copyWith({String? text, List<Source>? sources, bool? emergency, bool? fallback, bool? streaming, int? firstTokenMs}) =>
      ChatMessage(
        fromUser: fromUser,
        text: text ?? this.text,
        sources: sources ?? this.sources,
        emergency: emergency ?? this.emergency,
        fallback: fallback ?? this.fallback,
        streaming: streaming ?? this.streaming,
        firstTokenMs: firstTokenMs ?? this.firstTokenMs,
      );
}

class CareFacility {
  final String id, name, type, source, address, phone;
  final double lat, lon;
  final bool open24x7, emergency;
  final int? distanceMeters;

  const CareFacility({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.type = 'hospital',
    this.source = 'tomtom',
    this.address = '',
    this.phone = '',
    this.open24x7 = false,
    this.emergency = false,
    this.distanceMeters,
  });

  factory CareFacility.fromJson(Map<String, dynamic> j) => CareFacility(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Medical Facility'}',
        lat: _dbl(j['lat']) ?? 0.0,
        lon: _dbl(j['lon']) ?? 0.0,
        type: '${j['type'] ?? 'hospital'}',
        source: '${j['source'] ?? 'tomtom'}',
        address: '${j['address'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        open24x7: j['open24x7'] == true,
        emergency: j['emergency'] == true,
        distanceMeters: _int(j['distanceMeters'] ?? j['distance_meters']),
      );
}

class EmergencyRouteInfo {
  final String source;
  final int distanceMeters;
  final int travelTimeSeconds;
  final int trafficDelaySeconds;
  final List<({double lat, double lon})> points;

  const EmergencyRouteInfo({
    this.source = 'tomtom',
    required this.distanceMeters,
    required this.travelTimeSeconds,
    this.trafficDelaySeconds = 0,
    this.points = const [],
  });

  factory EmergencyRouteInfo.fromJson(Map<String, dynamic> j) => EmergencyRouteInfo(
        source: '${j['source'] ?? 'tomtom'}',
        distanceMeters: _int(j['distanceMeters'] ?? j['distance_meters']) ?? 0,
        travelTimeSeconds: _int(j['travelTimeSeconds'] ?? j['travel_time_seconds']) ?? 0,
        trafficDelaySeconds: _int(j['trafficDelaySeconds'] ?? j['traffic_delay_seconds']) ?? 0,
        points: ((j['points'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => (lat: _dbl(p['lat']) ?? 0.0, lon: _dbl(p['lon']) ?? 0.0))
            .toList(),
      );
}

class RtcSession {
  final String appId, channelId, uid, role, token;
  final int expiresAt;

  const RtcSession({
    required this.appId,
    required this.channelId,
    required this.uid,
    required this.role,
    required this.token,
    required this.expiresAt,
  });

  factory RtcSession.fromJson(Map<String, dynamic> j) => RtcSession(
        appId: '${j['appId'] ?? ''}',
        channelId: '${j['channelId'] ?? ''}',
        uid: '${j['uid'] ?? ''}',
        role: '${j['role'] ?? 'publisher'}',
        token: '${j['token'] ?? ''}',
        expiresAt: _int(j['expiresAt']) ?? 0,
      );
}

