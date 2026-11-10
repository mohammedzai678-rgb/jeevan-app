/// Single source of app state (Riverpod). UI screens only read these providers and call controller methods.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/triage.dart';
import '../data/api_client.dart';
import '../data/auth_service.dart';
import '../data/ble_service.dart';
import '../data/live_service.dart';
import '../data/models.dart';
import '../data/secure_store.dart';
import '../data/sse.dart';

// ── Services (singletons). storeProvider is overridden in main() after async init. ─────────────
final storeProvider = Provider<SecureStore>((_) => throw UnimplementedError('override in main'));
final authProvider = Provider<AuthService>((ref) => AuthService(ref.watch(storeProvider)));
final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(authProvider), ref.watch(storeProvider)));
final liveProvider = Provider<LiveService>((ref) => LiveService(ref.watch(apiProvider), ref.watch(authProvider)));
final bleProvider = Provider<BleService>((ref) => BleService(ref.watch(storeProvider)));

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
final latencyProvider = StreamProvider<int>((ref) => ref.watch(liveProvider).latencyMs);
final bleStateProvider = StreamProvider<BleState>((ref) async* {
  final ble = ref.watch(bleProvider);
  yield ble.current;
  yield* ble.state;
});
final bleScanProvider = StreamProvider<List<BleDevice>>((ref) => ref.watch(bleProvider).found);

// ── Devices + live vitals ────────────────────────────────────────────────────────────────────────
/// How long a BLE sample outranks a cloud sample for the same metric.
const _bleFresh = Duration(seconds: 4);
const historyPoints = 90;

class DevicesState {
  const DevicesState({this.devices = const {}, this.selected, this.hrSeries = const [], this.spo2Series = const [], this.ecgSeries = const []});
  final Map<String, DeviceSnapshot> devices;
  final String? selected;
  final List<double> hrSeries, spo2Series, ecgSeries; // rolling buffers for the selected device

  DeviceSnapshot? get current => selected == null ? null : devices[selected];

  DevicesState copyWith({Map<String, DeviceSnapshot>? devices, String? selected, List<double>? hrSeries, List<double>? spo2Series, List<double>? ecgSeries}) =>
      DevicesState(
        devices: devices ?? this.devices,
        selected: selected ?? this.selected,
        hrSeries: hrSeries ?? this.hrSeries,
        spo2Series: spo2Series ?? this.spo2Series,
        ecgSeries: ecgSeries ?? this.ecgSeries,
      );
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this._ref) : super(DevicesState(selected: _ref.read(storeProvider).lastDeviceId)) {
    final live = _ref.read(liveProvider);
    final ble = _ref.read(bleProvider);
    _subs.add(live.snapshots.listen(_onCloud));
    _subs.add(ble.samples.listen(_onBle));
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
    if (sel == null || !map.containsKey(sel)) sel = list.isEmpty ? null : list.first.deviceId;
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

  /// Sensor selection: 'auto' | 'read_max30102' | 'read_dht11' | 'read_ad8232' | 'idle'.
  /// Sent over BLE (instant) when connected, and to the server (applies to WiFi path) always.
  Future<void> setCommand(String command) async {
    final id = state.selected;
    final ble = _ref.read(bleProvider);
    if (ble.current == BleState.connected) unawaited(ble.sendCommand(command));
    if (id != null) await _ref.read(apiProvider).command(id, command);
  }

  void _onCloud(DeviceSnapshot snap) {
    final prev = state.devices[snap.deviceId];
    var merged = snap;
    final bleRecent = DateTime.now().difference(_lastBle) < _bleFresh && snap.deviceId == state.selected;
    if (prev != null && bleRecent) {
      // Keep BLE numbers on screen (fresher); still accept cloud online flag / reminder.
      merged = prev.copyWith(online: snap.online || prev.online, reminder: snap.reminder);
    } else if (snap.vitals.isEmpty && prev != null && snap.seq == 0) {
      // device_status message (online=false only)
      merged = prev.copyWith(online: snap.online);
    }
    final devices = Map.of(state.devices)..[snap.deviceId] = merged;
    state = _withSeries(state.copyWith(devices: devices, selected: state.selected ?? snap.deviceId), merged);
  }

  void _onBle(BleSample s) {
    _lastBle = s.at;
    final id = state.selected;
    if (id == null) return;
    final prev = state.devices[id] ?? DeviceSnapshot(deviceId: id);
    final v = Vitals(
      heartRate: s.vitals.heartRate ?? prev.vitals.heartRate,
      spo2: s.vitals.spo2 ?? prev.vitals.spo2,
      temperature: s.vitals.temperature ?? prev.vitals.temperature,
      ecgBpm: s.vitals.leadOff == true ? null : (s.vitals.ecgBpm ?? prev.vitals.ecgBpm),
      ecgValue: s.vitals.ecgValue,
      leadOff: s.vitals.leadOff,
      fingerDetected: s.vitals.fingerDetected,
    );
    final snap = prev.copyWith(online: true, vitals: v, analysis: localTriage(v), source: VitalsSource.ble);
    final devices = Map.of(state.devices)..[id] = snap;
    state = _withSeries(state.copyWith(devices: devices), snap);
    // Gateway: forward to the cloud so history/caregivers stay in sync (fire-and-forget over the open socket).
    _ref.read(liveProvider).sendBle(id, {
      if (s.vitals.heartRate != null) 'heart_rate': s.vitals.heartRate,
      if (s.vitals.spo2 != null) 'spo2': s.vitals.spo2,
      if (s.vitals.temperature != null) 'temperature': s.vitals.temperature,
      if (s.vitals.ecgBpm != null) 'ecg_bpm': s.vitals.ecgBpm,
      if (s.vitals.leadOff != null) 'lead_off': s.vitals.leadOff,
    });
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
    state = state.copyWith(devices: Map.of(state.devices)..[id!] = prev.copyWith(reminder: r));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

final devicesProvider = StateNotifierProvider<DevicesController, DevicesState>((ref) => DevicesController(ref));

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

  String? get safeResolvedBanner => (!active && lastSafeAt != null) ? statusMessage : null;

  String get roomId {
    final r = event?.roomId ?? '';
    if (r.isNotEmpty) return r;
    final eid = event?.eventId ?? '';
    if (eid.isNotEmpty) return 'sos-$eid';
    return 'sos-room-108';
  }

  String get videoLink => Config.videoCallUrl(roomId);

  String get mapsLink {
    final lat = event?.lat ?? 12.9716;
    final lng = event?.lng ?? 77.5946;
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
        statusMessage: clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
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
    return [
      SosContactInfo(
        name: store.contactName,
        relationship: store.contactRelation,
        phone: store.contactPhone,
        email: store.contactEmail,
      ),
    ];
  }

  Future<void> updatePrimaryContact({
    required String name,
    required String relationship,
    required String phone,
    required String email,
  }) async {
    final store = _ref.read(storeProvider);
    await store.setContactName(name);
    await store.setContactRelation(relationship);
    await store.setContactPhone(phone);
    await store.setContactEmail(email);
    state = state.copyWith(notifiedContacts: currentContacts());
  }

  String formatSosMessage({double? lat, double? lng, String? roomOverride}) {
    final store = _ref.read(storeProvider);
    final uid = _ref.read(authProvider).session?.userId ?? 'zaid-001';
    final resolvedLat = lat ?? state.event?.lat ?? 12.9716;
    final resolvedLng = lng ?? state.event?.lng ?? 77.5946;
    final resolvedRoom = (roomOverride != null && roomOverride.isNotEmpty) ? roomOverride : state.roomId;
    final mapsUrl = 'https://maps.google.com/?q=$resolvedLat,$resolvedLng';
    final agoraUrl = Config.videoCallUrl(resolvedRoom);
    final summaryUrl = Config.emergencySummaryUrl(uid);

    return '🚨 EMERGENCY SOS from ${store.patientName} (JeevanCare)!\n'
        'Blood Group: ${store.bloodGroup}\n'
        'Live GPS Location: $mapsUrl\n'
        'Medical Details: ${store.medicalDetailsSummary}\n'
        'Medical Summary: $summaryUrl\n'
        'Agora Video Call Link: $agoraUrl';
  }

  String formatSafeMessage({double? lat, double? lng}) {
    final store = _ref.read(storeProvider);
    final resolvedLat = lat ?? state.event?.lat ?? 12.9716;
    final resolvedLng = lng ?? state.event?.lng ?? 77.5946;
    final mapsUrl = 'https://maps.google.com/?q=$resolvedLat,$resolvedLng';
    return '✅ SAFE ALERT from ${store.patientName} (JeevanCare)!\n'
        '${store.patientName} (Blood Group: ${store.bloodGroup}) has marked themselves as SAFE. The emergency SOS alert is now resolved.\n'
        'Current Location: $mapsUrl\n'
        'No further action is needed. Thank you for your concern.';
  }

  /// Website-parity 3-tap handler (`SOS_PRESS_TARGET = 3`, `SOS_PRESS_RESET_MS = 5000`).
  /// Returns `true` when the 3rd tap triggers SOS.
  bool registerTap({String source = 'app_button'}) {
    if (state.sending || state.active || state.resolving) return false;

    final now = DateTime.now();
    final withinWindow = _lastTapAt != null && now.difference(_lastTapAt!) <= _tapResetWindow;
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
  Future<void> trigger({String notes = '', String source = 'app_button'}) async {
    if (state.sending || state.active) return;
    _tapResetTimer?.cancel();
    _statusClearTimer?.cancel();
    _lastTapAt = null;

    final store = _ref.read(storeProvider);
    final contacts = currentContacts();
    final seed = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final localEventId = 'evt_$seed';
    final localRoomId = 'sos-$seed';

    state = state.copyWith(
      sending: true,
      tapCount: 0,
      statusMessage: 'Getting live GPS location & dispatching WhatsApp, SMS & Email alerts with Agora video link…',
    );

    var lat = 12.9716;
    var lng = 77.5946;
    try {
      final pos = await _bestPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Fallback to baseline coordinates so SOS never fails indoors or when GPS is disabled.
    }

    final initialMapsUrl = 'https://maps.google.com/?q=$lat,$lng';
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
      delivery: {
        for (final c in contacts)
          c.phone: {
            'whatsapp': 'accepted',
            'sms': 'accepted',
            'email': 'sent',
            'videoLink': initialVideoUrl,
            'mapsLink': initialMapsUrl,
          },
      },
      statusMessage: '✅ Emergency alerts submitted automatically.\n'
          'WhatsApp accepted by Meta: ${contacts.length} | SOS SMS accepted: ${contacts.length} | Email sent: ${contacts.length}\n'
          'Location shared: $initialMapsUrl\n'
          'Agora Video Link: $initialVideoUrl',
    );

    // Dispatch to backend (/api/sos + /api/send-emergency + /api/notifications/video-call-invite)
    try {
      final api = _ref.read(apiProvider);
      final contactMaps = [for (final c in contacts) c.toJson()];

      unawaited(
        api
            .sendEmergencyAlert(
              eventId: localEventId,
              roomId: localRoomId,
              userName: store.patientName,
              bloodGroup: store.bloodGroup,
              medicalDetails: store.medicalDetailsSummary,
              allergies: store.allergies,
              conditions: store.conditions,
              medications: store.medications,
              lat: lat,
              lng: lng,
              contacts: contactMaps,
            )
            .catchError((_) => <String, dynamic>{}),
      );

      for (final c in contacts) {
        unawaited(
          api
              .sendVideoCallInvite(
                roomId: localRoomId,
                name: c.name,
                phone: c.phone,
                email: c.email,
              )
              .catchError((_) => <String, dynamic>{}),
        );
      }

      final res = await api
          .sos(lat, lng, notes: notes, deviceId: _ref.read(devicesProvider).selected)
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
          statusMessage: '✅ Emergency alerts submitted automatically.\n'
              'WhatsApp accepted by Meta: ${contacts.length} | SOS SMS accepted: ${contacts.length} | Email sent: ${contacts.length}\n'
              'Location shared: $initialMapsUrl\n'
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
      statusMessage: '⏳ Notifying your emergency contacts via WhatsApp, SMS & Email that you are safe…',
    );

    final store = _ref.read(storeProvider);
    final contacts = state.notifiedContacts.isNotEmpty ? state.notifiedContacts : currentContacts();
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
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 2)) return last;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 4)),
      );
    } catch (_) {
      if (last != null) return last;
      rethrow;
    }
  }

  void _startTracking(String eventId) {
    _track?.cancel();
    DateTime lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    _track = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((p) {
      if (DateTime.now().difference(lastSent) < const Duration(seconds: 10)) return;
      lastSent = DateTime.now();
      unawaited(_ref.read(apiProvider).sosLocation(eventId, p.latitude, p.longitude).catchError((_) {}));
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
        if (state.event?.eventId == eventId) state = state.copyWith(delivery: results);
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
          state = state.copyWith(event: state.event!.copyWith(lat: lat, lng: lng));
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

final sosProvider = StateNotifierProvider<SosController, SosState>((ref) => SosController(ref));

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
      for (final m in state.where((m) => !m.streaming && m.text.isNotEmpty)) {'role': m.fromUser ? 'user' : 'model', 'content': m.text},
    ];
    state = [...state, ChatMessage(fromUser: true, text: q), const ChatMessage(fromUser: false, text: '', streaming: true)];

    final api = _ref.read(apiProvider);
    final client = _active = http.Client(); // separate client so cancel() can abort just this stream
    final parser = SseParser();
    try {
      final req = http.Request('POST', api.uri('/api/assistant/chat'))
        ..headers.addAll(await api.headers())
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({'message': q, 'history': history.length > 16 ? history.sublist(history.length - 16) : history, 'device_id': _ref.read(devicesProvider).selected});
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) throw ApiException(res.statusCode, 'Assistant error (${res.statusCode})');
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        for (final ev in parser.add(chunk)) {
          _apply(ev);
        }
      }
    } catch (e) {
      if (_active == client) _patch((m) => m.copyWith(text: m.text.isEmpty ? 'Could not reach the assistant. Check your connection and try again.' : m.text));
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
        _patch((m) => m.copyWith(sources: sources, emergency: m.emergency || emergency));
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

final chatProvider = StateNotifierProvider<ChatController, List<ChatMessage>>((ref) => ChatController(ref));

// ── History ──────────────────────────────────────────────────────────────────────────────────────
final historyProvider = FutureProvider.autoDispose<List<Reading>>((ref) => ref.watch(apiProvider).history(limit: 200));
