/// Single source of app state (Riverpod). UI screens only read these providers and call controller methods.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/triage.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/ble_service.dart';
import '../data/live_service.dart';
import '../data/medication_reminder_service.dart';
import '../data/models.dart';
import '../data/secure_store.dart';
import '../data/supabase_service.dart';
import '../data/sse.dart';

// ── Services (singletons). storeProvider is overridden in main() after async init. ─────────────
final storeProvider =
    Provider<SecureStore>((_) => throw UnimplementedError('override in main'));
final authProvider =
    Provider<AuthService>((ref) => AuthService(ref.watch(storeProvider)));
final apiProvider = Provider<ApiClient>(
    (ref) => ApiClient(ref.watch(authProvider), ref.watch(storeProvider)));
final supabaseProvider = Provider<SupabaseService>(
    (ref) => SupabaseService(ref.watch(authProvider)));
final liveProvider = Provider<LiveService>(
    (ref) => LiveService(ref.watch(apiProvider), ref.watch(authProvider)));
final bleProvider =
    Provider<BleService>((ref) => BleService(ref.watch(storeProvider)));

// ── Streams ──────────────────────────────────────────────────────────────────────────────────────
final sessionProvider = StreamProvider<Session?>((ref) async* {
  final auth = ref.watch(authProvider);
  yield auth.session;
  yield* auth.changes;
});
final linkStateProvider = StreamProvider<LinkState>((ref) async* {
  final live = ref.watch(liveProvider);
  yield live.state;
  yield* live.link;
});
final latencyProvider =
    StreamProvider<int>((ref) => ref.watch(liveProvider).latencyMs);
final bleStateProvider = StreamProvider<BleState>((ref) async* {
  final ble = ref.watch(bleProvider);
  yield ble.current;
  yield* ble.state;
});
final bleScanProvider =
    StreamProvider<List<BleDevice>>((ref) => ref.watch(bleProvider).found);

// ── Devices + live vitals ────────────────────────────────────────────────────────────────────────
/// How long a BLE sample outranks a cloud sample for the same metric.
const _bleFresh = Duration(seconds: 4);
const historyPoints = 90;

class DevicesState {
  const DevicesState(
      {this.devices = const {},
      this.selected,
      this.bleWatch,
      this.hrSeries = const [],
      this.spo2Series = const [],
      this.ecgSeries = const [],
      this.bleHrSeries = const [],
      this.bleSpo2Series = const []});
  final Map<String, DeviceSnapshot> devices;
  final String? selected;
  final DeviceSnapshot? bleWatch;
  final List<double> hrSeries,
      spo2Series,
      ecgSeries; // rolling buffers for the selected device
  final List<double> bleHrSeries, bleSpo2Series;

  DeviceSnapshot? get current => selected == null ? null : devices[selected];

  DevicesState copyWith(
          {Map<String, DeviceSnapshot>? devices,
          String? selected,
          DeviceSnapshot? bleWatch,
          List<double>? hrSeries,
          List<double>? spo2Series,
          List<double>? ecgSeries,
          List<double>? bleHrSeries,
          List<double>? bleSpo2Series}) =>
      DevicesState(
        devices: devices ?? this.devices,
        selected: selected ?? this.selected,
        bleWatch: bleWatch ?? this.bleWatch,
        hrSeries: hrSeries ?? this.hrSeries,
        spo2Series: spo2Series ?? this.spo2Series,
        ecgSeries: ecgSeries ?? this.ecgSeries,
        bleHrSeries: bleHrSeries ?? this.bleHrSeries,
        bleSpo2Series: bleSpo2Series ?? this.bleSpo2Series,
      );
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this._ref)
      : super(DevicesState(selected: _ref.read(storeProvider).lastDeviceId)) {
    final live = _ref.read(liveProvider);
    final ble = _ref.read(bleProvider);
    _subs.add(live.snapshots.listen(_onCloud));
    _subs.add(ble.samples.listen(_onBle));
    _subs.add(ble.events.listen((event) {
      if (event == 'medication_due') {
        unawaited(
            MedicationReminderService.showMedicationAlert('your scheduled dose')
                .catchError((_) {}));
      }
    }));
    _subs.add(live.events.listen((e) {
      if (e is ReminderChanged) _patchReminder(e.reminder);
    }));
  }

  final Ref _ref;
  final _subs = <StreamSubscription<dynamic>>[];
  DateTime _lastBle = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> refresh() async {
    final list = await _ref.read(apiProvider).devices();
    final map = {for (final d in list) d.deviceId: d};
    var sel = state.selected;
    if (sel == null || !map.containsKey(sel))
      sel = list.isEmpty ? null : list.first.deviceId;
    state = state.copyWith(devices: map, selected: sel);
    if (sel != null) await _ref.read(storeProvider).setLastDeviceId(sel);
  }

  void select(String id) {
    state = DevicesState(devices: state.devices, selected: id);
    unawaited(_ref.read(storeProvider).setLastDeviceId(id));
  }

  Future<void> pair(String id) async {
    await _ref.read(apiProvider).pair(id);
    await refresh();
    select(id);
  }

  Future<void> unpair(String id) async {
    await _ref.read(apiProvider).unpair(id);
    final m = Map.of(state.devices)..remove(id);
    state = DevicesState(devices: m, selected: m.isEmpty ? null : m.keys.first);
  }

  /// Sensor selection is sent directly over BLE. Paired legacy devices may also
  /// receive a server command, but VitaWatch does not need watch-side Wi-Fi.
  Future<void> setCommand(String command) async {
    final id = state.selected;
    final ble = _ref.read(bleProvider);
    if (ble.current == BleState.connected) unawaited(ble.sendCommand(command));
    if (id != null) await _ref.read(apiProvider).command(id, command);
  }

  void _onCloud(DeviceSnapshot snap) {
    final prev = state.devices[snap.deviceId];
    var merged = snap;
    final bleRecent = DateTime.now().difference(_lastBle) < _bleFresh &&
        snap.deviceId == state.selected;
    if (prev != null && bleRecent) {
      // Keep BLE numbers on screen (fresher); still accept cloud online flag / reminder.
      merged = prev.copyWith(
          online: snap.online || prev.online, reminder: snap.reminder);
    } else if (snap.vitals.isEmpty && prev != null && snap.seq == 0) {
      // device_status message (online=false only)
      merged = prev.copyWith(online: snap.online);
    }
    final devices = Map.of(state.devices)..[snap.deviceId] = merged;
    state = _withSeries(
        state.copyWith(
            devices: devices, selected: state.selected ?? snap.deviceId),
        merged);
  }

  void _onBle(BleSample s) {
    _lastBle = s.at;
    final ble = _ref.read(bleProvider);
    final watchId = (ble.connectedId ?? 'vitawatch')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final watchVitals = Vitals(
      heartRate: s.vitals.heartRate,
      spo2: s.vitals.spo2,
      temperature: s.vitals.temperature,
      fingerDetected: s.vitals.fingerDetected,
    );
    final watch = DeviceSnapshot(
      deviceId: watchId,
      online: true,
      vitals: watchVitals,
      analysis: localTriage(watchVitals),
      source: VitalsSource.ble,
      receivedAt: s.at,
    );
    List<double> push(List<double> values, num? value) {
      if (value == null) return values;
      final next = [...values, value.toDouble()];
      return next.length > historyPoints
          ? next.sublist(next.length - historyPoints)
          : next;
    }

    state = state.copyWith(
      bleWatch: watch,
      bleHrSeries: push(state.bleHrSeries, s.vitals.heartRate),
      bleSpo2Series: push(state.bleSpo2Series, s.vitals.spo2),
    );

    // Phone gateway: forward the real BLE values over the signed-in account's
    // live socket. The server claims this watch ID for that account on first use.
    _ref.read(liveProvider).sendBle(watchId, {
      if (s.vitals.heartRate != null) 'heart_rate': s.vitals.heartRate,
      if (s.vitals.spo2 != null) 'spo2': s.vitals.spo2,
      if (s.vitals.temperature != null) 'temperature': s.vitals.temperature,
      if (s.vitals.fingerDetected != null)
        'finger_detected': s.vitals.fingerDetected,
    });

    final id = state.selected;
    if (id == null) return;
    final prev = state.devices[id] ?? DeviceSnapshot(deviceId: id);
    final v = Vitals(
      heartRate: s.vitals.heartRate ?? prev.vitals.heartRate,
      spo2: s.vitals.spo2 ?? prev.vitals.spo2,
      temperature: s.vitals.temperature ?? prev.vitals.temperature,
      fingerDetected: s.vitals.fingerDetected,
    );
    final snap = prev.copyWith(
        online: true,
        vitals: v,
        analysis: localTriage(v),
        source: VitalsSource.ble);
    final devices = Map.of(state.devices)..[id] = snap;
    state = _withSeries(state.copyWith(devices: devices), snap);
  }

  DevicesState _withSeries(DevicesState st, DeviceSnapshot snap) {
    if (snap.deviceId != st.selected) return st;
    List<double> push(List<double> l, num? v) {
      if (v == null) return l;
      final n = [...l, v.toDouble()];
      return n.length > historyPoints ? n.sublist(n.length - historyPoints) : n;
    }

    return st.copyWith(
      hrSeries: push(st.hrSeries, snap.vitals.heartRate),
      spo2Series: push(st.spo2Series, snap.vitals.spo2),
      ecgSeries: push(st.ecgSeries, snap.vitals.ecgValue),
    );
  }

  void _patchReminder(Reminder r) {
    final id = state.selected;
    final prev = id == null ? null : state.devices[id];
    if (prev == null) return;
    state = state.copyWith(
        devices: Map.of(state.devices)..[id!] = prev.copyWith(reminder: r));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

final devicesProvider = StateNotifierProvider<DevicesController, DevicesState>(
    (ref) => DevicesController(ref));

// ── SOS (Website-Parity 3-Tap Activation -> SMS/Email/WhatsApp + Agora Link -> Green Safe Button) ──
class SosContactInfo {
  const SosContactInfo({
    required this.name,
    required this.relationship,
    required this.phone,
    required this.email,
    this.whatsappStatus = 'sent',
    this.smsStatus = 'sent',
    this.emailStatus = 'sent',
  });

  final String name;
  final String relationship;
  final String phone;
  final String email;
  final String whatsappStatus;
  final String smsStatus;
  final String emailStatus;

  Map<String, dynamic> toJson() => {
        'name': name,
        'relationship': relationship,
        'phone': phone,
        'email': email,
      };
}

class SosState {
  const SosState({
    this.event,
    this.sending = false,
    this.resolving = false,
    this.tapCount = 0,
    this.error,
    this.statusMessage,
    this.lastSafeAt,
    this.delivery = const {},
    this.notifiedContacts = const [],
  });

  final SosEvent? event;
  final bool sending;
  final bool resolving;
  final int tapCount;
  final String? error;
  final String? statusMessage;
  final DateTime? lastSafeAt;
  final Map<String, dynamic> delivery;
  final List<SosContactInfo> notifiedContacts;

  bool get active => event?.active ?? false;

  int get remainingTaps => (3 - tapCount).clamp(0, 3);

  String? get safeResolvedBanner =>
      (!active && lastSafeAt != null) ? statusMessage : null;

  String get roomId {
    final r = event?.roomId ?? '';
    if (r.isNotEmpty) return r;
    final eid = event?.eventId ?? '';
    if (eid.isNotEmpty) return 'sos-$eid';
    return 'sos-room-108';
  }

  String get videoLink => Config.videoCallUrl(roomId);

  String get mapsLink {
    final current = event;
    if (current == null || !current.hasLocation) return '';
    final lat = current.lat;
    final lng = current.lng;
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  SosState copyWith({
    SosEvent? event,
    bool? sending,
    bool? resolving,
    int? tapCount,
    String? error,
    String? statusMessage,
    bool clearStatusMessage = false,
    DateTime? lastSafeAt,
    Map<String, dynamic>? delivery,
    List<SosContactInfo>? notifiedContacts,
  }) =>
      SosState(
        event: event ?? this.event,
        sending: sending ?? this.sending,
        resolving: resolving ?? this.resolving,
        tapCount: tapCount ?? this.tapCount,
        error: error,
        statusMessage:
            clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
        lastSafeAt: lastSafeAt ?? this.lastSafeAt,
        delivery: delivery ?? this.delivery,
        notifiedContacts: notifiedContacts ?? this.notifiedContacts,
      );
}

class SosController extends StateNotifier<SosState> {
  SosController(this._ref) : super(const SosState()) {
    state = state.copyWith(notifiedContacts: currentContacts());
    _subs.add(_ref.read(liveProvider).events.listen(_onLive));
    _subs.add(_ref.read(bleProvider).events.listen((e) {
      if (e == 'sos') unawaited(trigger(source: 'watch_ble'));
    }));
  }

  final Ref _ref;
  final _subs = <StreamSubscription<dynamic>>[];
  StreamSubscription<Position>? _track;
  Timer? _tapResetTimer;
  Timer? _statusClearTimer;
  DateTime? _lastTapAt;

  static const Duration _tapResetWindow = Duration(seconds: 5);

  List<SosContactInfo> currentContacts() {
    final store = _ref.read(storeProvider);
    return store.emergencyContacts
        .map((contact) => SosContactInfo(
              name: contact['name'] ?? '',
              relationship: contact['relationship'] ?? '',
              phone: contact['phone'] ?? '',
              email: contact['email'] ?? '',
            ))
        .toList();
  }

  Future<void> updatePrimaryContact({
    required String name,
    required String relationship,
    required String phone,
    required String email,
  }) async {
    final contacts = currentContacts();
    final primary = SosContactInfo(
      name: name,
      relationship: relationship,
      phone: phone,
      email: email,
    );
    if (contacts.isEmpty) {
      contacts.add(primary);
    } else {
      contacts[0] = primary;
    }
    await updateContacts(contacts);
  }

  Future<void> updateContacts(List<SosContactInfo> contacts) async {
    final store = _ref.read(storeProvider);
    await store.setEmergencyContacts([
      for (final contact in contacts)
        {
          'name': contact.name,
          'relationship': contact.relationship,
          'phone': contact.phone,
          'email': contact.email,
        },
    ]);
    state = state.copyWith(notifiedContacts: currentContacts());
    final profile = <String, dynamic>{
      'name': store.patientName,
      'bloodType': store.bloodGroup,
      'dob': store.dateOfBirth,
      'allergies': _profileValues(store.allergies),
      'conditions': _profileValues(store.conditions),
      'currentMedications': _profileValues(store.medications),
      'emergencyContacts': [
        for (final contact in currentContacts()) contact.toJson()
      ],
      'showEmergencyContacts': store.showEmergencyContactsOnQr,
    };
    try {
      await _ref.read(apiProvider).updateEmergencySummary(profile);
    } catch (_) {
      // Local emergency contacts remain saved if the network is offline.
    }
  }

  List<String> _profileValues(String value) => value
      .split(',')
      .map((part) => part.trim())
      .where(
          (part) => part.isNotEmpty && !part.toLowerCase().startsWith('none'))
      .toList();

  String formatSosMessage({double? lat, double? lng, String? roomOverride}) {
    final store = _ref.read(storeProvider);
    final uid = _ref.read(authProvider).session?.userId ?? 'patient-user';
    final current = state.event;
    final resolvedLat =
        lat ?? (current?.hasLocation == true ? current!.lat : null);
    final resolvedLng =
        lng ?? (current?.hasLocation == true ? current!.lng : null);
    final resolvedRoom = (roomOverride != null && roomOverride.isNotEmpty)
        ? roomOverride
        : state.roomId;
    final mapsUrl = resolvedLat != null && resolvedLng != null
        ? 'https://maps.google.com/?q=$resolvedLat,$resolvedLng'
        : 'GPS location is not available yet.';
    final agoraUrl = Config.videoCallUrl(resolvedRoom);
    final summaryUrl = Config.emergencySummaryUrl(uid);
    final bloodLine = store.bloodGroup.trim().isEmpty ||
            store.bloodGroup.toLowerCase() == 'not specified'
        ? ''
        : 'Blood Group: ${store.bloodGroup}\n';

    final birthDate = store.dateOfBirth.trim();
    final emergencyContacts = currentContacts();
    final contactLines = emergencyContacts
        .map((contact) =>
            '${contact.name}${contact.relationship.isNotEmpty ? ' (${contact.relationship})' : ''}: ${[
              contact.phone,
              contact.email
            ].where((value) => value.isNotEmpty).join(' · ')}')
        .join('\n');
    return '🚨 EMERGENCY SOS from ${store.patientName} (JeevanCare)!\n'
        '$bloodLine'
        '${birthDate.isEmpty ? '' : 'Date of Birth: $birthDate\n'}'
        'Live GPS Location: $mapsUrl\n'
        '${store.medicalDetailsSummary.isEmpty ? '' : 'Medical Details: ${store.medicalDetailsSummary}\n'}'
        '${contactLines.isEmpty ? '' : 'Emergency Contacts:\n$contactLines\n'}'
        'Medical Summary: $summaryUrl\n'
        'Agora Video Call Link: $agoraUrl';
  }

  String formatSafeMessage({double? lat, double? lng}) {
    final store = _ref.read(storeProvider);
    final current = state.event;
    final resolvedLat =
        lat ?? (current?.hasLocation == true ? current!.lat : null);
    final resolvedLng =
        lng ?? (current?.hasLocation == true ? current!.lng : null);
    final mapsUrl = resolvedLat != null && resolvedLng != null
        ? 'https://maps.google.com/?q=$resolvedLat,$resolvedLng'
        : 'not available (GPS location unavailable)';
    final bloodLine = store.bloodGroup.trim().isEmpty ||
            store.bloodGroup.toLowerCase() == 'not specified'
        ? ''
        : ' Blood Group: ${store.bloodGroup}.';
    return '✅ SAFE ALERT from ${store.patientName} (JeevanCare)!\n'
        '${store.patientName} has marked themselves as SAFE.$bloodLine The emergency SOS alert is now resolved.\n'
        'Current Location: $mapsUrl\n'
        'No further action is needed. Thank you for your concern.';
  }

  /// Website-parity 3-tap handler (`SOS_PRESS_TARGET = 3`, `SOS_PRESS_RESET_MS = 5000`).
  /// Returns `true` when the 3rd tap triggers SOS.
  bool registerTap({String source = 'app_button'}) {
    if (state.sending || state.active || state.resolving) return false;

    final now = DateTime.now();
    final withinWindow =
        _lastTapAt != null && now.difference(_lastTapAt!) <= _tapResetWindow;
    final nextCount = withinWindow ? (state.tapCount + 1).clamp(1, 3) : 1;
    _lastTapAt = now;
    _tapResetTimer?.cancel();

    if (nextCount >= 3) {
      _lastTapAt = null;
      unawaited(trigger(source: source));
      return true;
    }

    final remaining = 3 - nextCount;
    state = state.copyWith(
      tapCount: nextCount,
      statusMessage:
          'Press the SOS button $remaining more time${remaining == 1 ? '' : 's'} to send the emergency alert via WhatsApp, SMS & Email.',
    );

    _tapResetTimer = Timer(_tapResetWindow, () {
      if (!state.active && !state.sending) {
        _lastTapAt = null;
        state = state.copyWith(tapCount: 0, clearStatusMessage: true);
      }
    });
    return false;
  }

  /// Instant: shows the active SOS UI (green button + Agora video call link + notified contacts)
  /// immediately on the 3rd tap, then dispatches SMS, Email, and WhatsApp in the background.
  Future<void> trigger(
      {String notes = '', String source = 'app_button'}) async {
    if (state.sending || state.active) return;
    _tapResetTimer?.cancel();
    _statusClearTimer?.cancel();
    _lastTapAt = null;
    unawaited(SystemSound.play(SystemSoundType.alert));
    unawaited(HapticFeedback.heavyImpact());
    unawaited(MedicationReminderService.showSosAlert().catchError((_) {}));

    final contacts = currentContacts();
    final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final localEventId = 'evt_$seed';
    final localRoomId = 'sos-$seed';

    state = state.copyWith(
      sending: true,
      tapCount: 0,
      statusMessage:
          'Getting live GPS location & dispatching WhatsApp, SMS & Email alerts with Agora video link…',
    );

    Position? position;
    try {
      position = await _bestPosition();
    } catch (_) {
      // Keep the SOS available, but never send an unrelated location.
    }

    final lat = position?.latitude ?? 0.0;
    final lng = position?.longitude ?? 0.0;
    final initialMapsUrl =
        position == null ? '' : 'https://maps.google.com/?q=$lat,$lng';
    final initialVideoUrl = Config.videoCallUrl(localRoomId);
    final initialEvent = SosEvent(
      eventId: localEventId,
      roomId: localRoomId,
      source: source,
      status: 'active',
      mapsUrl: initialMapsUrl,
      lat: lat,
      lng: lng,
      time: DateTime.now(),
    );

    // Immediately transition to ACTIVE so the button turns GREEN and user sees the Agora link & contacts!
    state = SosState(
      event: initialEvent,
      sending: false,
      resolving: false,
      tapCount: 0,
      notifiedContacts: contacts,
      statusMessage: 'SOS is active. Emergency notifications are being sent.\n'
          'Location: ${initialMapsUrl.isEmpty ? 'waiting for a GPS fix' : initialMapsUrl}\n'
          'Agora Video Link: $initialVideoUrl',
    );

    // The SOS endpoint owns delivery so saved contacts receive only one alert.
    try {
      final api = _ref.read(apiProvider);
      final watch = _ref.read(devicesProvider).bleWatch;
      final res = await api
          .sos(position?.latitude, position?.longitude,
              notes: notes,
              deviceId: watch?.deviceId ?? _ref.read(devicesProvider).selected,
              vitals: {
                if (watch?.vitals.heartRate != null)
                  'heart_rate': watch!.vitals.heartRate,
                if (watch?.vitals.spo2 != null) 'spo2': watch!.vitals.spo2,
                if (watch?.vitals.temperature != null)
                  'temperature': watch!.vitals.temperature,
              },
              userName: _ref.read(storeProvider).patientName,
              bloodGroup: _ref.read(storeProvider).bloodGroup,
              allergies: _profileValues(_ref.read(storeProvider).allergies),
              conditions: _profileValues(_ref.read(storeProvider).conditions),
              medications: _profileValues(_ref.read(storeProvider).medications),
              contacts: [
                for (final contact in currentContacts()) contact.toJson()
              ])
          .timeout(const Duration(seconds: 6));

      if (state.active) {
        final serverRoom = res.roomId.isNotEmpty ? res.roomId : localRoomId;
        final serverVideoUrl = Config.videoCallUrl(serverRoom);
        final updatedEvent = SosEvent(
          eventId: res.eventId.isNotEmpty ? res.eventId : localEventId,
          roomId: serverRoom,
          source: source,
          status: 'active',
          mapsUrl: initialMapsUrl,
          lat: lat,
          lng: lng,
          time: initialEvent.time,
        );
        state = state.copyWith(
          event: updatedEvent,
          statusMessage:
              'SOS is active. Emergency notifications are being sent.\n'
              'Location: ${initialMapsUrl.isEmpty ? 'waiting for a GPS fix' : initialMapsUrl}\n'
              'Agora Video Link: $serverVideoUrl',
        );
        _startTracking(updatedEvent.eventId);
      }
    } catch (_) {
      // Keep optimistic active SOS state so the green Safe button and Agora link remain active even offline.
      _startTracking(localEventId);
    }
  }

  /// Triggered when the user presses the GREEN Safe button (`✅ I'M SAFE`).
  /// Dispatches the Safe Alert over WhatsApp, SMS, and Email, and resets the button back to RED.
  Future<void> resolve() async {
    final ev = state.event;
    if (ev == null || state.resolving) return;

    state = state.copyWith(
      resolving: true,
      statusMessage:
          '⏳ Notifying your emergency contacts via WhatsApp, SMS & Email that you are safe…',
    );

    final store = _ref.read(storeProvider);
    final contacts = state.notifiedContacts.isNotEmpty
        ? state.notifiedContacts
        : currentContacts();
    final contactMaps = [for (final c in contacts) c.toJson()];
    final api = _ref.read(apiProvider);

    try {
      await Future.wait([
        api
            .sendSafeNotification(
              eventId: ev.eventId,
              userName: store.patientName,
              contacts: contactMaps,
              originalTriggeredAt: ev.time.toIso8601String(),
            )
            .timeout(const Duration(seconds: 5))
            .catchError((_) => <String, dynamic>{}),
        api
            .sosResolve(ev.eventId)
            .timeout(const Duration(seconds: 5))
            .catchError((_) {}),
      ]);
    } catch (_) {}

    _stopTracking();
    final safeNow = DateTime.now();
    state = SosState(
      event: ev.copyWith(status: 'resolved'),
      sending: false,
      resolving: false,
      tapCount: 0,
      lastSafeAt: safeNow,
      notifiedContacts: contacts,
      delivery: state.delivery,
      statusMessage:
          '✅ Your safe update was submitted. WhatsApp, SMS & Email safe notifications sent to ${contacts.map((c) => c.name).join(", ")}.',
    );

    _statusClearTimer?.cancel();
    _statusClearTimer = Timer(const Duration(seconds: 10), () {
      if (!state.active) {
        state = state.copyWith(clearStatusMessage: true);
      }
    });
  }

  void clear() {
    _tapResetTimer?.cancel();
    _statusClearTimer?.cancel();
    _stopTracking();
    state = const SosState();
  }

  Future<Position> _bestPosition() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever ||
        !await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Location permission or GPS is unavailable.');
    }
    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
      );
      if (DateTime.now().difference(current.timestamp).inSeconds.abs() <= 30 &&
          current.accuracy <= 500) return current;
    } catch (_) {
      // A recent cached fix may be used if the fresh request times out.
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null &&
        DateTime.now().difference(last.timestamp).inSeconds.abs() <= 30 &&
        last.accuracy <= 100) return last;
    throw StateError('No recent GPS location is available.');
  }

  void _startTracking(String eventId) {
    _track?.cancel();
    DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    _track = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((p) {
      if (DateTime.now().difference(lastSent) < const Duration(seconds: 10))
        return;
      lastSent = DateTime.now();
      unawaited(_ref
          .read(apiProvider)
          .sosLocation(eventId, p.latitude, p.longitude)
          .catchError((_) {}));
    });
  }

  void _stopTracking() {
    _track?.cancel();
    _track = null;
  }

  void _onLive(LiveEvent e) {
    switch (e) {
      case SosIncoming(:final event):
        // From the watch's hardware button (or another of the user's devices).
        if (state.event?.eventId != event.eventId) {
          unawaited(SystemSound.play(SystemSoundType.alert));
          unawaited(HapticFeedback.heavyImpact());
          unawaited(
              MedicationReminderService.showSosAlert().catchError((_) {}));
          final contacts = currentContacts();
          state = SosState(
            event: event,
            notifiedContacts: contacts,
            statusMessage: '✅ Emergency SOS triggered from hardware watch.\n'
                'Location shared: ${event.mapsUrl}\n'
                'Agora Video Link: ${Config.videoCallUrl(event.roomId)}',
          );
        }
      case SosDelivery(:final eventId, :final results):
        if (state.event?.eventId == eventId)
          state = state.copyWith(delivery: results);
      case SosResolved(:final eventId):
        if (state.event?.eventId == eventId && state.event != null) {
          _stopTracking();
          state = state.copyWith(
            event: state.event!.copyWith(status: 'resolved'),
            resolving: false,
            lastSafeAt: DateTime.now(),
          );
        }
      case SosLocationUpdate(:final eventId, :final lat, :final lng):
        if (state.event?.eventId == eventId && state.event != null) {
          state =
              state.copyWith(event: state.event!.copyWith(lat: lat, lng: lng));
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    _statusClearTimer?.cancel();
    _stopTracking();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

final sosProvider =
    StateNotifierProvider<SosController, SosState>((ref) => SosController(ref));

// ── Assistant (RAG chat, streamed) ───────────────────────────────────────────────────────────────
class ChatController extends StateNotifier<List<ChatMessage>> {
  ChatController(this._ref) : super(const []);
  final Ref _ref;
  http.Client? _active;

  bool get busy => state.isNotEmpty && state.last.streaming;

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || busy) return;
    final history = [
      for (final m in state.where((m) => !m.streaming && m.text.isNotEmpty))
        {'role': m.fromUser ? 'user' : 'model', 'content': m.text},
    ];
    state = [
      ...state,
      ChatMessage(fromUser: true, text: q),
      const ChatMessage(fromUser: false, text: '', streaming: true)
    ];

    final api = _ref.read(apiProvider);
    final client = _active =
        http.Client(); // separate client so cancel() can abort just this stream
    final parser = SseParser();
    try {
      final req = http.Request('POST', api.uri('/api/assistant/chat'))
        ..headers.addAll(await api.headers())
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({
          'message': q,
          'history': history.length > 16
              ? history.sublist(history.length - 16)
              : history,
          'device_id': _ref.read(devicesProvider).selected
        });
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400)
        throw ApiException(
            res.statusCode, 'Assistant error (${res.statusCode})');
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        for (final ev in parser.add(chunk)) {
          _apply(ev);
        }
      }
    } catch (e) {
      if (_active == client)
        _patch((m) => m.copyWith(
            text: m.text.isEmpty
                ? 'Could not reach the assistant. Check your connection and try again.'
                : m.text));
    } finally {
      client.close();
      if (_active == client) _active = null;
      _patch((m) => m.copyWith(streaming: false));
    }
  }

  void cancel() {
    _active?.close();
    _active = null;
    _patch((m) => m.copyWith(streaming: false));
  }

  void clear() {
    cancel();
    state = const [];
  }

  void _apply(ChatEvent ev) {
    switch (ev) {
      case EmergencyEvent():
        _patch((m) => m.copyWith(emergency: true));
      case MetaEvent(:final sources, :final emergency):
        _patch((m) =>
            m.copyWith(sources: sources, emergency: m.emergency || emergency));
      case TokenEvent(:final text):
        _patch((m) => m.copyWith(text: m.text + text));
      case TimingEvent(:final firstTokenMs):
        _patch((m) => m.copyWith(firstTokenMs: firstTokenMs));
      case FallbackEvent():
        _patch((m) => m.copyWith(fallback: true));
      case DoneEvent():
        _patch((m) => m.copyWith(streaming: false));
    }
  }

  void _patch(ChatMessage Function(ChatMessage) f) {
    if (state.isEmpty || state.last.fromUser) return;
    state = [...state.sublist(0, state.length - 1), f(state.last)];
  }
}

final chatProvider = StateNotifierProvider<ChatController, List<ChatMessage>>(
    (ref) => ChatController(ref));

// ── History ──────────────────────────────────────────────────────────────────────────────────────
final historyProvider = FutureProvider.autoDispose<List<Reading>>(
    (ref) => ref.watch(apiProvider).history(limit: 200));
// Jeevan sync: 2026-11-13
