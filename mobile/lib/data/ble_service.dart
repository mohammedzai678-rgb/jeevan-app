import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/config.dart';
import 'models.dart';
import 'secure_store.dart';

enum BleState { off, idle, scanning, connecting, connected }

class BleDevice {
  const BleDevice(this.id, this.name, this.rssi);
  final String id, name;
  final int rssi;
}

/// A sample received straight from the watch over Bluetooth (no network involved).
class BleSample {
  BleSample(this.vitals, this.at);
  final Vitals vitals;
  final DateTime at;
}

/// Direct phone<->watch link. Typical notify latency is ~30-80 ms vs hundreds of ms through WiFi+cloud.
/// Protocol (see firmware_ble/jeevan_ble.h):
///   vitals notify : {"hr":78,"spo2":98,"t":36.8,"ecg":72,"lo":0,"f":1,"v":1234}
///   event  notify : {"e":"sos"} | {"e":"med_ack"}
///   command write : ASCII "auto" | "read_max30102" | "read_dht11" | "read_ad8232" | "idle"
class BleService {
  BleService(this._store);
  final SecureStore _store;

  final _state = StreamController<BleState>.broadcast();
  final _samples = StreamController<BleSample>.broadcast();
  final _events = StreamController<String>.broadcast();
  final _found = StreamController<List<BleDevice>>.broadcast();

  Stream<BleState> get state => _state.stream;
  Stream<BleSample> get samples => _samples.stream;
  Stream<String> get events => _events.stream; // 'sos' | 'med_ack'
  Stream<List<BleDevice>> get found => _found.stream;
  BleState current = BleState.idle;
  String? connectedName;

  BluetoothDevice? _dev;
  BluetoothCharacteristic? _cmd;
  StreamSubscription<List<int>>? _vSub, _eSub;
  StreamSubscription<BluetoothConnectionState>? _cSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _wantConnected = false;
  final _buf = StringBuffer();

  void _set(BleState s) {
    current = s;
    _state.add(s);
  }

  Future<bool> get supported async => await FlutterBluePlus.isSupported;

  Future<void> scan() async {
    if (!await supported) return;
    _set(BleState.scanning);
    final seen = <String, BleDevice>{};
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        seen[r.device.remoteId.str] = BleDevice(r.device.remoteId.str, r.device.platformName.isEmpty ? 'Jeevan device' : r.device.platformName, r.rssi);
      }
      _found.add(seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(Config.bleService)],
      timeout: const Duration(seconds: 8),
      androidScanMode: AndroidScanMode.lowLatency,
    );
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    if (current == BleState.scanning) _set(BleState.idle);
  }

  Future<void> connect(String remoteId) async {
    _wantConnected = true;
    _set(BleState.connecting);
    final dev = BluetoothDevice.fromId(remoteId);
    _dev = dev;
    await _cSub?.cancel();
    _cSub = dev.connectionState.listen((s) async {
      if (s == BluetoothConnectionState.disconnected) {
        _teardownChars();
        connectedName = null;
        if (_wantConnected) {
          _set(BleState.connecting);
          // Auto-heal: the watch walks out of range and comes back.
          unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
            if (_wantConnected) {
              try {
                await dev.connect(autoConnect: false, timeout: const Duration(seconds: 10));
              } catch (_) {}
            }
          }));
        } else {
          _set(BleState.idle);
        }
      }
    });
    try {
      await dev.connect(autoConnect: false, timeout: const Duration(seconds: 12));
      await _discover(dev);
      await _store.setLastBleId(remoteId);
    } catch (e) {
      _set(BleState.idle);
      rethrow;
    }
  }

  Future<void> _discover(BluetoothDevice dev) async {
    try {
      await dev.requestMtu(185); // room for the full JSON in one notification
    } catch (_) {}
    final services = await dev.discoverServices();
    final svc = services.firstWhere((s) => s.uuid == Guid(Config.bleService), orElse: () => throw StateError('Jeevan service not found'));
    for (final c in svc.characteristics) {
      if (c.uuid == Guid(Config.bleVitalsChar)) {
        await c.setNotifyValue(true);
        _vSub = c.lastValueStream.listen(_onVitalsChunk);
      } else if (c.uuid == Guid(Config.bleEventChar)) {
        await c.setNotifyValue(true);
        _eSub = c.lastValueStream.listen(_onEvent);
      } else if (c.uuid == Guid(Config.bleCommandChar)) {
        _cmd = c;
      }
    }
    connectedName = dev.platformName.isEmpty ? 'Jeevan device' : dev.platformName;
    _set(BleState.connected);
  }

  // Notifications can be split across packets if the MTU was not negotiated: reassemble on newline.
  void _onVitalsChunk(List<int> bytes) {
    if (bytes.isEmpty) return;
    _buf.write(utf8.decode(bytes, allowMalformed: true));
    var s = _buf.toString();
    int nl;
    while ((nl = s.indexOf('\n')) >= 0 || _looksComplete(s)) {
      final line = nl >= 0 ? s.substring(0, nl) : s;
      s = nl >= 0 ? s.substring(nl + 1) : '';
      _parseVitals(line.trim());
      if (s.isEmpty) break;
    }
    _buf
      ..clear()
      ..write(s);
  }

  bool _looksComplete(String s) => s.startsWith('{') && s.endsWith('}');

  void _parseVitals(String line) {
    if (line.isEmpty) return;
    try {
      final j = jsonDecode(line) as Map<String, dynamic>;
      int? i(String k) => j[k] is num && (j[k] as num) > 0 ? (j[k] as num).toInt() : null;
      final t = j['t'] is num && (j['t'] as num) > 0 ? (j['t'] as num).toDouble() : null;
      _samples.add(BleSample(
        Vitals(
          heartRate: i('hr'),
          spo2: i('spo2'),
          temperature: t,
          ecgBpm: i('ecg'),
          leadOff: j['lo'] == 1 || j['lo'] == true,
          fingerDetected: j['f'] == 1 || j['f'] == true,
        ),
        DateTime.now(),
      ));
    } catch (_) {
      // drop malformed frame
    }
  }

  void _onEvent(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final e = j['e'];
      if (e is String) _events.add(e);
    } catch (_) {}
  }

  Future<void> sendCommand(String command) async {
    final c = _cmd;
    if (c == null) return;
    await c.write(utf8.encode(command), withoutResponse: false);
  }

  /// Reconnect to the last-paired watch (called on app start / foreground).
  Future<void> autoConnect() async {
    final id = _store.lastBleId;
    if (id == null || current == BleState.connected || current == BleState.connecting) return;
    if (!await supported) return;
    try {
      await connect(id);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    await _store.setLastBleId(null);
    await _dev?.disconnect();
    _teardownChars();
    connectedName = null;
    _set(BleState.idle);
  }

  void _teardownChars() {
    _vSub?.cancel();
    _eSub?.cancel();
    _vSub = _eSub = null;
    _cmd = null;
    _buf.clear();
  }
}
