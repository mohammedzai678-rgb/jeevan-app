import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'auth_service.dart';
import 'models.dart';
import 'secure_store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// REST client. One shared keep-alive `http.Client` (connection reuse = no repeated TLS handshakes),
/// bearer injection with transparent single retry after a token refresh.
class ApiClient {
  ApiClient(this._auth, this._store, {http.Client? client})
      : _http = client ?? http.Client();
  final AuthService _auth;
  final SecureStore _store;
  final http.Client _http;

  String get baseUrl {
    final o = _store.serverUrlOverride;
    return (o != null && o.isNotEmpty ? o : Config.apiBaseUrl)
        .replaceAll(RegExp(r'/+$'), '');
  }

  Uri uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Uri get wsUri {
    final u = Uri.parse(baseUrl);
    return u.replace(
        scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '${u.path}/ws/live');
  }

  Future<Map<String, String>> headers({bool json = true}) async {
    final t = await _auth.accessToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Object? body,
      Map<String, String>? query,
      bool retry = true,
      Duration timeout = const Duration(seconds: 15)}) async {
    final req = http.Request(method, uri(path, query))
      ..headers.addAll(await headers());
    if (body != null) req.body = jsonEncode(body);
    final res =
        await http.Response.fromStream(await _http.send(req).timeout(timeout))
            .timeout(timeout);
    if (res.statusCode == 401 && retry) {
      await _auth.accessToken(force: true);
      return _send(method, path,
          body: body, query: query, retry: false, timeout: timeout);
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiException(res.statusCode,
          detail is String ? detail : 'Request failed (${res.statusCode})');
    }
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  Future<List<DeviceSnapshot>> devices() async {
    final r = await _send('GET', '/api/devices');
    return ((r['devices'] as List?) ?? const [])
        .map((e) => DeviceSnapshot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> pair(String deviceId) =>
      _send('POST', '/api/devices/pair', body: {'device_id': deviceId});
  Future<void> unpair(String deviceId) =>
      _send('DELETE', '/api/devices/$deviceId');
  Future<void> command(String deviceId, String command) =>
      _send('POST', '/api/devices/$deviceId/command',
          body: {'command': command});
  Future<void> triggerReminder(
          String deviceId, String medication, String slot) =>
      _send('POST', '/api/devices/$deviceId/reminder',
          body: {'medication': medication, 'slot': slot});
  Future<void> ackReminder(String deviceId) =>
      _send('POST', '/api/devices/$deviceId/reminder/ack');

  Future<SosResult> sos(double? lat, double? lng,
      {String notes = '',
      String? deviceId,
      String? userName,
      String? bloodGroup,
      List<String> allergies = const [],
      List<String> conditions = const [],
      List<String> medications = const [],
      List<Map<String, dynamic>> contacts = const []}) async {
    final r = await _send('POST', '/api/sos', body: {
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
      'notes': notes,
      'device_id': deviceId,
      'user_name': userName,
      'blood_group': bloodGroup,
      'allergies': allergies,
      'conditions': conditions,
      'medications': medications,
      'contacts': contacts,
    });
    return SosResult('${r['event_id']}', '${r['room_id']}');
  }

  Future<void> sosLocation(String eventId, double lat, double lng) =>
      _send('POST', '/api/sos/$eventId/location',
          body: {'lat': lat, 'lng': lng});
  Future<void> sosResolve(String eventId) =>
      _send('POST', '/api/sos/$eventId/resolve');

  Future<List<CareFacility>> nearbyFacilities(double lat, double lon,
      {int radius = 7000}) async {
    final r = await _send('POST', '/api/emergency-route/facilities',
        body: {'lat': lat, 'lon': lon, 'radius': radius});
    return ((r['facilities'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => CareFacility.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<EmergencyRouteInfo> emergencyRoute({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
  }) async {
    final r = await _send('POST', '/api/emergency-route/route', body: {
      'origin_lat': originLat,
      'origin_lon': originLon,
      'dest_lat': destLat,
      'dest_lon': destLon,
    });
    return EmergencyRouteInfo.fromJson(r);
  }

  Future<RtcSession> createRtcChannel(String channelId) async {
    final r = await _send('POST', '/api/rtc/create-channel',
        body: {'channelId': channelId, 'role': 'publisher'});
    return RtcSession.fromJson(r);
  }

  Future<List<Reading>> history({int limit = 100}) async {
    final r =
        await _send('GET', '/api/vitals/history', query: {'limit': '$limit'});
    return ((r['readings'] as List?) ?? const [])
        .map((e) => Reading.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Analysis> recordVitals(
      {required int heartRate,
      required int spo2,
      required double temperature,
      int? systolic,
      int? diastolic}) async {
    final r = await _send('POST', '/api/vitals/record', body: {
      'heart_rate': heartRate,
      'spo2': spo2,
      'temperature': temperature,
      if (systolic != null && diastolic != null) ...{
        'systolic_bp': systolic,
        'diastolic_bp': diastolic
      },
    });
    return Analysis.fromJson((r['analysis'] as Map).cast<String, dynamic>());
  }

  Future<int> addDocument(String title, String text) async {
    final r = await _send('POST', '/api/assistant/documents',
        body: {'title': title, 'text': text});
    return (r['chunks'] as num?)?.toInt() ?? 0;
  }

  Future<int> documentChunks() async =>
      ((await _send('GET', '/api/assistant/documents'))['chunks'] as num?)
          ?.toInt() ??
      0;
  Future<void> clearDocuments() => _send('DELETE', '/api/assistant/documents');

  // ── Smart Walking Stick (ESP32 #2) & Geofence ─────────────────────────────
  Future<Map<String, dynamic>> stickStatus() =>
      _send('GET', '/api/stick/status');
  Future<Map<String, dynamic>> stickGeofence() =>
      _send('GET', '/api/stick/geofence');
  Future<Map<String, dynamic>> updateStickGeofence({
    required bool enabled,
    required double centerLat,
    required double centerLng,
    required double radiusM,
    String label = 'Home Safety Zone',
  }) =>
      _send('POST', '/api/stick/geofence', body: {
        'enabled': enabled,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius_m': radiusM,
        'label': label,
      });

  Future<Map<String, dynamic>> syncStickWithWatch() =>
      _send('POST', '/api/stick/sync-watch');
  Future<Map<String, dynamic>> simulateStick(Map<String, dynamic> payload) =>
      _send('POST', '/api/stick/simulate', body: payload);

  // ── Ecosystem & Website Feature Parity ────────────────────────────────────
  Future<Map<String, dynamic>> systemFeatures() =>
      _send('GET', '/api/system/features');
  Future<Map<String, dynamic>> weatherRadar(
          {double lat = 12.9716, double lon = 77.5946}) =>
      _send('GET', '/api/weather/radar', query: {'lat': '$lat', 'lon': '$lon'});
  Future<Map<String, dynamic>> disasterRiskScore(
          {double lat = 12.9716, double lng = 77.5946}) =>
      _send('GET', '/api/risk-score', query: {'lat': '$lat', 'lng': '$lng'});

  Future<Map<String, dynamic>> fdaInteractions(String drug1, String drug2) =>
      _send('GET', '/api/fda/interactions',
          query: {'drug1': drug1, 'drug2': drug2});

  Future<List<Map<String, dynamic>>> searchBloodBank(
      {String bloodType = '', String city = ''}) async {
    final r = await _send('GET', '/api/blood-bank/search',
        query: {'bloodType': bloodType, 'city': city});
    return ((r['donors'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> registerBloodDonor({
    required String name,
    required String bloodType,
    required String city,
    String? phone,
  }) =>
      _send('POST', '/api/blood-bank/register', body: {
        'name': name,
        'bloodType': bloodType,
        'city': city,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      });

  Future<List<Map<String, dynamic>>> listNgos({String category = 'all'}) async {
    final r = await _send('GET', '/api/ngo', query: {'category': category});
    return ((r['ngos'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> contactNgo(
          {required String ngoId,
          required String senderName,
          required String message}) =>
      _send('POST', '/api/ngo/contact',
          body: {'ngoId': ngoId, 'senderName': senderName, 'message': message});

  Future<Map<String, dynamic>> abdmGenerateOtp(String aadhaarNumber) =>
      _send('POST', '/api/abdm/generate-otp',
          body: {'aadhaarNumber': aadhaarNumber});
  Future<Map<String, dynamic>> abdmVerifyOtp(String txnId, String otp) =>
      _send('POST', '/api/abdm/verify-otp', body: {'txnId': txnId, 'otp': otp});

  Future<Map<String, dynamic>> getEmergencySummary() =>
      _send('GET', '/api/emergency-summary');
  Future<Map<String, dynamic>> updateEmergencySummary(
          Map<String, dynamic> body) =>
      _send('PUT', '/api/emergency-summary', body: body);

  Future<List<Map<String, dynamic>>> listMedications() async {
    final r = await _send('GET', '/api/medications');
    return ((r['medications'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> addMedication({
    required String name,
    required String dosage,
    String frequency = 'Once daily',
    List<String> reminderTimes = const ['08:00'],
    String? doctorName,
  }) =>
      _send('POST', '/api/medications', body: {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'reminderTimes': reminderTimes,
        if (doctorName != null && doctorName.isNotEmpty)
          'doctorName': doctorName,
      });

  Future<void> deleteMedication(String medId) =>
      _send('DELETE', '/api/medications/$medId');

  Future<Map<String, dynamic>> aiSymptomCheck(String text,
          {String language = 'en'}) =>
      _send('POST', '/api/gemini/symptom-check',
          body: {'text': text, 'language': language},
          timeout: const Duration(seconds: 90));
  Future<Map<String, dynamic>> aiMediScan(
    String text, {
    String? documentBase64,
    String mimeType = 'image/jpeg',
    String filename = 'document.jpg',
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/mediscan',
          body: {
            'text': text,
            if (documentBase64 != null && documentBase64.isNotEmpty)
              'documentBase64': documentBase64,
            'mimeType': mimeType,
            'filename': filename,
            'language': language,
          },
          timeout: const Duration(seconds: 120));
  Future<Map<String, dynamic>> aiMedicineAnalyzer(
    String text, {
    String? documentBase64,
    String mimeType = 'image/jpeg',
    String filename = 'medicine.jpg',
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/medicine-ingredients',
          body: {
            'text': text,
            'medicineName': text,
            if (documentBase64 != null && documentBase64.isNotEmpty)
              'documentBase64': documentBase64,
            'mimeType': mimeType,
            'filename': filename,
            'language': language,
          },
          timeout: const Duration(seconds: 120));
  Future<Map<String, dynamic>> aiWellbeing(
    String text, {
    String language = 'en',
    List<Map<String, String>> history = const [],
  }) =>
      _send('POST', '/api/gemini/wellbeing',
          body: {
            'text': text,
            'language': language,
            'history': history,
          },
          timeout: const Duration(seconds: 90));

  // ── Complete Website Sub-Routes Parity ────────────────────────────────────
  Future<Map<String, dynamic>> triage({
    required String symptoms,
    String? duration,
    int? severity,
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/triage',
          body: {
            'symptoms': symptoms,
            'text': symptoms,
            if (duration != null && duration.isNotEmpty) 'duration': duration,
            if (severity != null) 'severity': severity,
            'language': language,
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> bodySymptomCheck({
    required String bodyLocation,
    required List<String> symptoms,
    String duration = '1-3 days',
    int severity = 5,
    String additionalInfo = '',
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/symptom-check',
          body: {
            'bodyLocation': bodyLocation,
            'symptoms': symptoms,
            'duration': duration,
            'severity': severity,
            'additionalInfo': additionalInfo,
            'language': language,
            'text':
                '$bodyLocation: ${symptoms.join(", ")}${additionalInfo.isNotEmpty ? " ($additionalInfo)" : ""}',
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> medicationAdvice({
    required String drugName,
    String? dosage,
    String? scheduledTime,
    String? missedBy,
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/medication-advice',
          body: {
            'drugName': drugName,
            if (dosage != null && dosage.isNotEmpty) 'dosage': dosage,
            if (scheduledTime != null && scheduledTime.isNotEmpty)
              'scheduledTime': scheduledTime,
            if (missedBy != null && missedBy.isNotEmpty) 'missedBy': missedBy,
            'language': language,
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> vitalsReport({
    required int hr,
    required int spo2,
    required int sys,
    required int dia,
    required double temp,
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/vitals-report',
          body: {
            'hr': hr,
            'spo2': spo2,
            'sys': sys,
            'dia': dia,
            'temp': temp,
            'language': language,
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> diagnosticImaging({
    required String imagingType,
    required String bodyRegion,
    String clinicalContext = '',
    String? documentBase64,
    String mimeType = 'image/jpeg',
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/diagnostic-imaging',
          body: {
            'imagingType': imagingType,
            'bodyRegion': bodyRegion,
            'clinicalContext': clinicalContext,
            if (documentBase64 != null && documentBase64.isNotEmpty)
              'documentBase64': documentBase64,
            'mimeType': mimeType,
            'language': language,
          },
          timeout: const Duration(seconds: 120));

  Future<Map<String, dynamic>> mediscanFeedback({
    required String logId,
    required int reward,
    String? correction,
  }) =>
      _send('POST', '/api/gemini/feedback', body: {
        'logId': logId,
        'reward': reward,
        if (correction != null && correction.isNotEmpty)
          'correction': correction,
      });

  Future<Map<String, dynamic>> clinicalHistoryStep({
    required String chiefComplaint,
    required List<Map<String, String>> conversationHistory,
    String mode = 'allopathic',
    String language = 'en',
    String? imageContext,
  }) =>
      _send('POST', '/api/gemini/clinical-history',
          body: {
            'chiefComplaint': chiefComplaint,
            'conversationHistory': conversationHistory,
            'mode': mode,
            'language': language,
            if (imageContext != null && imageContext.isNotEmpty)
              'imageContext': imageContext,
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> clinicalHistorySummary({
    required String chiefComplaint,
    required List<Map<String, String>> conversationHistory,
    String mode = 'allopathic',
    String language = 'en',
  }) =>
      _send('POST', '/api/gemini/history-summary',
          body: {
            'chiefComplaint': chiefComplaint,
            'conversationHistory': conversationHistory,
            'mode': mode,
            'language': language,
          },
          timeout: const Duration(seconds: 90));

  Future<Map<String, dynamic>> sendMedicationStatusAlert({
    required String phone,
    required String medicationName,
    String? dosage,
    String? time,
    required bool taken,
  }) =>
      _send('POST', '/api/notifications/medication-status', body: {
        'phone': phone,
        'medicationName': medicationName,
        if (dosage != null && dosage.isNotEmpty) 'dosage': dosage,
        if (time != null && time.isNotEmpty) 'time': time,
        'taken': taken,
        'status': taken ? 'taken' : 'missed',
      });

  Future<Map<String, dynamic>> sendVideoCallInvite({
    required String roomId,
    required String name,
    String? phone,
    String? email,
  }) =>
      _send('POST', '/api/notifications/video-call-invite', body: {
        'roomId': roomId,
        'name': name,
        'recipientName': name,
        'userName': _store.patientName,
        'contacts': [
          {
            'name': name,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
            if (email != null && email.isNotEmpty) 'email': email,
          },
        ],
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
      });

  Future<Map<String, dynamic>> sendEmergencyAlert({
    required String eventId,
    required String roomId,
    required String userName,
    double? lat,
    double? lng,
    required List<Map<String, dynamic>> contacts,
    String? bloodGroup,
    String? medicalDetails,
    String? allergies,
    String? conditions,
    String? medications,
  }) async {
    final bg = (bloodGroup != null &&
            bloodGroup.isNotEmpty &&
            bloodGroup.toLowerCase() != 'not specified')
        ? bloodGroup
        : _store.bloodGroup;
    final medSummary = (medicalDetails != null && medicalDetails.isNotEmpty)
        ? medicalDetails
        : _store.medicalDetailsSummary;
    final videoLink = Config.videoCallUrl(roomId);
    final hasLocation = lat != null && lng != null;
    final mapsLink = hasLocation ? 'https://maps.google.com/?q=$lat,$lng' : '';
    final medical = <String, dynamic>{
      if ((allergies ?? _store.allergies).trim().isNotEmpty)
        'allergies': allergies ?? _store.allergies,
      if ((conditions ?? _store.conditions).trim().isNotEmpty)
        'conditions': conditions ?? _store.conditions,
      if ((medications ?? _store.medications).trim().isNotEmpty)
        'medications': medications ?? _store.medications,
      if (medSummary.trim().isNotEmpty) 'summary': medSummary,
    };
    final payload = <String, dynamic>{
      'eventId': eventId,
      'roomId': roomId,
      'userName': userName,
      if (bg != null && bg.isNotEmpty && bg.toLowerCase() != 'not specified')
        'bloodGroup': bg,
      if (medical.isNotEmpty) 'medicalDetails': medical,
      if (medSummary.trim().isNotEmpty) 'medicalSummary': medSummary,
      'videoLink': videoLink,
      if (mapsLink.isNotEmpty) 'mapsLink': mapsLink,
      if (hasLocation) 'location': {'lat': lat, 'lng': lng},
      'contacts': contacts,
    };
    return _send('POST', '/api/send-emergency', body: payload);
  }

  Future<Map<String, dynamic>> sendSafeNotification({
    required String eventId,
    String? userName,
    List<Map<String, dynamic>>? contacts,
    String? originalTriggeredAt,
  }) async {
    final payload = <String, dynamic>{
      'eventId': eventId,
      'event_id': eventId,
      'userName': userName ?? _store.patientName,
      if (contacts != null) 'contacts': contacts,
      if (originalTriggeredAt != null)
        'originalTriggeredAt': originalTriggeredAt,
    };
    return _send('POST', '/api/send-safe', body: payload);
  }

  Future<void> deleteVitalReading(String readingId) =>
      _send('DELETE', '/api/vitawatch/readings/$readingId');

  Future<Map<String, dynamic>> recordDeviceSnapshot(String deviceId) =>
      _send('POST', '/api/device/record-reading', body: {
        'device_id': deviceId,
        'deviceId': deviceId,
      });

  // ── Health Vault (routed through FastAPI — works with local auth) ──
  Future<List<Map<String, dynamic>>> healthVaultDocuments() async {
    final r = await _send('GET', '/api/health-vault/documents');
    return ((r['documents'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> healthVaultUpload({
    required String title,
    required String category,
    String? description,
    String? documentDate,
    String? doctorName,
    String? hospitalName,
    List<String>? tags,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? fileType,
  }) =>
      _send('POST', '/api/health-vault/documents', body: {
        'title': title,
        'category': category,
        if (description != null) 'description': description,
        if (documentDate != null) 'document_date': documentDate,
        if (doctorName != null) 'doctor_name': doctorName,
        if (hospitalName != null) 'hospital_name': hospitalName,
        if (tags != null) 'tags': tags,
        if (fileUrl != null) 'file_url': fileUrl,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (fileType != null) 'file_type': fileType,
      });

  Future<void> healthVaultDelete(String docId) =>
      _send('DELETE', '/api/health-vault/documents/$docId');

  Future<Map<String, dynamic>?> healthVaultSettings() async {
    final r = await _send('GET', '/api/health-vault/settings');
    return r['settings'] as Map<String, dynamic>?;
  }

  Future<void> healthVaultSetPassword(String hash) =>
      _send('POST', '/api/health-vault/settings/password',
          body: {'vault_password_hash': hash});

  Future<List<Map<String, dynamic>>> healthVaultContacts() async {
    final r = await _send('GET', '/api/health-vault/contacts');
    return ((r['contacts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> healthVaultAddContact(
          {required String name,
          required String phone,
          String relationship = 'Other',
          bool isPrimary = false}) =>
      _send('POST', '/api/health-vault/contacts', body: {
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'is_primary': isPrimary
      });

  Future<void> healthVaultDeleteContact(String contactId) =>
      _send('DELETE', '/api/health-vault/contacts/$contactId');

  Future<Map<String, dynamic>?> healthVaultProfile() async {
    final r = await _send('GET', '/api/health-vault/profile');
    return r['profile'] as Map<String, dynamic>?;
  }

  Future<void> healthVaultUpdateProfile(Map<String, dynamic> updates) =>
      _send('PATCH', '/api/health-vault/profile', body: updates);

  Future<List<Map<String, dynamic>>> healthVaultScans() async {
    final r = await _send('GET', '/api/health-vault/scans');
    return ((r['scans'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> healthVaultDeleteScan(String scanId) =>
      _send('DELETE', '/api/health-vault/scans/$scanId');

  Future<List<Map<String, dynamic>>> healthVaultSymptomChecks() async {
    final r = await _send('GET', '/api/health-vault/symptom-checks');
    return ((r['checks'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> healthVaultAlerts() async {
    final r = await _send('GET', '/api/health-vault/alerts');
    return ((r['alerts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> healthVaultCreateAlert({
    required String alertType,
    required double latitude,
    required double longitude,
    String address = '',
    String title = '',
  }) =>
      _send('POST', '/api/health-vault/alerts', body: {
        'alert_type': alertType,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'title': title,
      });

  /// Used by the assistant stream and connectivity probe.
  http.Client get raw => _http;

  Future<int> pingMs() async {
    final sw = Stopwatch()..start();
    await _http.get(uri('/health')).timeout(const Duration(seconds: 5));
    return sw.elapsedMilliseconds;
  }
}

class SosResult {
  const SosResult(this.eventId, this.roomId);
  final String eventId, roomId;
}
// Jeevan sync: 2026-11-13
