import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'models.dart';

enum LinkState { offline, connecting, online }

sealed class LiveEvent {}

class SosIncoming extends LiveEvent {
  SosIncoming(this.event);
  final SosEvent event;
}

class SosDelivery extends LiveEvent {
  SosDelivery(this.eventId, this.results);
  final String eventId;
  final Map<String, dynamic> results;
}

class SosResolved extends LiveEvent {
  SosResolved(this.eventId);
  final String eventId;
}

class SosLocationUpdate extends LiveEvent {
  SosLocationUpdate(this.eventId, this.lat, this.lng);
  final String eventId;
  final double lat, lng;
}

class ReminderChanged extends LiveEvent {
  ReminderChanged(this.reminder);
  final Reminder reminder;
}

/// Persistent WebSocket with auto-reconnect (exponential backoff + jitter) and live RTT measurement.
/// The server pushes every sample the instant the watch posts it, so there is no polling anywhere.
class LiveService {
  LiveService(this._api, this._auth);
  final ApiClient _api;
  final AuthService _auth;

  final _devices = StreamController<DeviceSnapshot>.broadcast();
  final _events = StreamController<LiveEvent>.broadcast();
  final _link = StreamController<LinkState>.broadcast();
  final _latency = StreamController<int>.broadcast();

  Stream<DeviceSnapshot> get snapshots => _devices.stream;
  Stream<LiveEvent> get events => _events.stream;
  Stream<LinkState> get link => _link.stream;
  Stream<int> get latencyMs => _latency.stream;
  LinkState state = LinkState.offline;

  WebSocketChannel? _ch;
  Timer? _pinger;
  bool _running = false;
  int _attempt = 0;
  bool _forceRefresh = false;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_loop());
  }

  Future<void> stop() async {
    _running = false;
    _pinger?.cancel();
    await _ch?.sink.close();
    _set(LinkState.offline);
  }

  /// Phone acts as BLE gateway: forward watch samples so the server (and any other viewer) stays in sync.
  void sendBle(String deviceId, Map<String, dynamic> vitals) =>
      _send({'type': 'ble_vitals', 'device_id': deviceId, 'vitals': vitals});

  void sendCommand(String deviceId, String command) => _send({'type': 'command', 'device_id': deviceId, 'command': command});

  void _send(Map<String, dynamic> m) {
    if (state == LinkState.online) _ch?.sink.add(jsonEncode(m));
  }

  void _set(LinkState s) {
    state = s;
    _link.add(s);
  }

  Future<void> _loop() async {
    while (_running) {
      final token = await _auth.accessToken(force: _forceRefresh);
      _forceRefresh = false;
      if (token == null) {
        _set(LinkState.offline);
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      _set(LinkState.connecting);
      final done = Completer<void>();
      try {
        final ch = IOWebSocketChannel.connect(
          _api.wsUri,
          headers: {'Authorization': 'Bearer $token'}, // header, never the URL (URLs end up in logs)
          pingInterval: const Duration(seconds: 20),
          connectTimeout: const Duration(seconds: 8),
        );
        _ch = ch;
        await ch.ready;
        _attempt = 0;
        _set(LinkState.online);
        _pinger?.cancel();
        _pinger = Timer.periodic(const Duration(seconds: 4), (_) => _send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch}));
        _send({'type': 'ping', 't': DateTime.now().millisecondsSinceEpoch});
        ch.stream.listen(
          _onMessage,
          onDone: () => done.isCompleted ? null : done.complete(),
          onError: (_) => done.isCompleted ? null : done.complete(),
          cancelOnError: true,
        );
        await done.future;
      } catch (e) {
        // 401/403 at upgrade means our token is bad: refresh before the next attempt.
        final msg = e.toString();
        if (msg.contains('403') || msg.contains('401')) _forceRefresh = true;
      } finally {
        _pinger?.cancel();
        _set(LinkState.offline);
      }
      if (!_running) break;
      _attempt++;
      final backoff = Duration(milliseconds: (500 * (1 << (_attempt.clamp(0, 5)))) + (DateTime.now().millisecond % 300));
      await Future<void>.delayed(backoff);
    }
  }

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final data = (m['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    switch (m['type']) {
      case 'vitals':
        _devices.add(DeviceSnapshot.fromJson(data));
      case 'device_status':
        _devices.add(DeviceSnapshot(deviceId: '${data['device_id']}', online: false));
      case 'pong':
        final t = m['t'];
        if (t is int) _latency.add(DateTime.now().millisecondsSinceEpoch - t);
      case 'sos':
        _events.add(SosIncoming(SosEvent.fromJson(data)));
      case 'sos_delivery':
        _events.add(SosDelivery('${data['event_id']}', (data['results'] as Map?)?.cast<String, dynamic>() ?? {}));
      case 'sos_resolved':
        _events.add(SosResolved('${data['event_id']}'));
      case 'sos_location':
        final loc = (data['location'] as Map?)?.cast<String, dynamic>() ?? {};
        _events.add(SosLocationUpdate('${data['event_id']}', (loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()));
      case 'reminder':
        _events.add(ReminderChanged(Reminder.fromJson(data)));
    }
  }
}
