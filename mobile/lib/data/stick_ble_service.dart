import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/config.dart';
import 'secure_store.dart';

enum StickBleState { idle, scanning, connecting, connected }

class StickBleDevice {
  const StickBleDevice(this.id, this.name, this.rssi);

  final String id;
  final String name;
  final int rssi;
}

/// Direct phone link for the separate walking-stick ESP32.
/// It shares the VitaWatch GATT layout, but connects only to Jeevan-Stick.
class StickBleService {
  StickBleService(this._store);

  final SecureStore _store;
  final _state = StreamController<StickBleState>.broadcast();
  final _found = StreamController<List<StickBleDevice>>.broadcast();
  final _telemetry = StreamController<Map<String, dynamic>>.broadcast();

  Stream<StickBleState> get state => _state.stream;
  Stream<List<StickBleDevice>> get found => _found.stream;
  Stream<Map<String, dynamic>> get telemetry => _telemetry.stream;

  StickBleState current = StickBleState.idle;
  String? connectedName;
  String? connectedId;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _command;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _telemetrySub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _wantConnected = false;
  bool _linkEstablished = false;
  bool _reconnectQueued = false;
  final StringBuffer _buffer = StringBuffer();

  void _set(StickBleState value) {
    current = value;
    _state.add(value);
  }

  Future<bool> get supported async => FlutterBluePlus.isSupported;

  Future<void> scan() async {
    if (!await supported)
      throw StateError('Bluetooth LE is not supported on this phone.');
    _set(StickBleState.scanning);
    final seen = <String, StickBleDevice>{};
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : result.advertisementData.advName;
        if (!name.toLowerCase().contains('stick')) continue;
        seen[result.device.remoteId.str] = StickBleDevice(
          result.device.remoteId.str,
          name,
          result.rssi,
        );
      }
      _found
          .add(seen.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(Config.bleService)],
      timeout: const Duration(seconds: 10),
      androidScanMode: AndroidScanMode.lowLatency,
    );
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    if (current == StickBleState.scanning) _set(StickBleState.idle);
  }

  Future<void> connect(String remoteId) async {
    _wantConnected = true;
    _linkEstablished = false;
    _set(StickBleState.connecting);
    final device = BluetoothDevice.fromId(remoteId);
    _device = device;
    await _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((value) {
      if (value != BluetoothConnectionState.disconnected) return;
      _teardownCharacteristics();
      connectedName = null;
      connectedId = null;
      if (_wantConnected && _linkEstablished) {
        _linkEstablished = false;
        _set(StickBleState.connecting);
        _scheduleReconnect(device);
      } else if (!_wantConnected) {
        _set(StickBleState.idle);
      }
    });
    try {
      await device
          .connect(autoConnect: false, timeout: const Duration(seconds: 12))
          .timeout(const Duration(seconds: 15));
      await _discover(device).timeout(const Duration(seconds: 20));
      await _store.setLastStickBleId(remoteId);
      _linkEstablished = true;
    } catch (_) {
      _wantConnected = false;
      _linkEstablished = false;
      _reconnectQueued = false;
      try {
        await device.disconnect().timeout(const Duration(seconds: 4));
      } catch (_) {}
      _teardownCharacteristics();
      connectedName = null;
      connectedId = null;
      _set(StickBleState.idle);
      rethrow;
    }
  }

  void _scheduleReconnect(BluetoothDevice device) {
    if (_reconnectQueued) return;
    _reconnectQueued = true;
    unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
      _reconnectQueued = false;
      if (!_wantConnected) return;
      try {
        await device
            .connect(autoConnect: false, timeout: const Duration(seconds: 10))
            .timeout(const Duration(seconds: 12));
        await _discover(device).timeout(const Duration(seconds: 20));
        _linkEstablished = true;
      } catch (_) {
        _wantConnected = false;
        _linkEstablished = false;
        _teardownCharacteristics();
        connectedName = null;
        connectedId = null;
        _set(StickBleState.idle);
      }
    }));
  }

  Future<void> _discover(BluetoothDevice device) async {
    try {
      await device.requestMtu(100).timeout(const Duration(seconds: 5));
    } catch (_) {}
    final services = await device.discoverServices().timeout(
          const Duration(seconds: 12),
          onTimeout: () =>
              throw TimeoutException('Stick BLE service discovery timed out'),
        );
    final service = services.firstWhere(
      (item) => item.uuid == Guid(Config.bleService),
      orElse: () => throw StateError('Jeevan stick BLE service not found'),
    );
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid == Guid(Config.bleVitalsChar)) {
        await characteristic.setNotifyValue(true).timeout(
              const Duration(seconds: 6),
              onTimeout: () => throw TimeoutException(
                  'Stick telemetry notification setup timed out'),
            );
        _telemetrySub =
            characteristic.lastValueStream.listen(_onTelemetryChunk);
      } else if (characteristic.uuid == Guid(Config.bleCommandChar)) {
        _command = characteristic;
      }
    }
    if (_telemetrySub == null || _command == null) {
      throw StateError(
          'Stick BLE service is missing telemetry or command characteristics');
    }
    connectedName =
        device.platformName.isNotEmpty ? device.platformName : 'Jeevan-Stick';
    connectedId = device.remoteId.str;
    _set(StickBleState.connected);
  }

  void _teardownCharacteristics() {
    unawaited(_telemetrySub?.cancel());
    _telemetrySub = null;
    _command = null;
    _buffer.clear();
  }

  void _onTelemetryChunk(List<int> bytes) {
    if (bytes.isEmpty) return;
    _buffer.write(utf8.decode(bytes, allowMalformed: true));
    var content = _buffer.toString();
    int newline;
    while ((newline = content.indexOf('\n')) >= 0 ||
        (content.startsWith('{') && content.endsWith('}'))) {
      final line = newline >= 0 ? content.substring(0, newline) : content;
      content = newline >= 0 ? content.substring(newline + 1) : '';
      try {
        final decoded = jsonDecode(line.trim());
        if (decoded is Map) {
          _telemetry.add(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // Ignore malformed notification packets and keep scanning for the next frame.
      }
      if (content.isEmpty) break;
    }
    _buffer
      ..clear()
      ..write(content);
  }

  Future<void> sendCommand(String command) async {
    final characteristic = _command;
    if (characteristic == null)
      throw StateError('Walking stick is not connected over Bluetooth.');
    await characteristic.write(utf8.encode(command), withoutResponse: false);
  }

  Future<void> autoConnect() async {
    final id = _store.lastStickBleId;
    if (id == null ||
        current == StickBleState.connected ||
        current == StickBleState.connecting) return;
    if (!await supported) return;
    try {
      await connect(id);
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _linkEstablished = false;
    await _store.setLastStickBleId(null);
    try {
      await _device?.disconnect();
    } catch (_) {}
    await _connectionSub?.cancel();
    _connectionSub = null;
    _teardownCharacteristics();
    connectedName = null;
    connectedId = null;
    _set(StickBleState.idle);
  }

  Future<void> dispose() async {
    await disconnect();
    await _scanSub?.cancel();
    await _state.close();
    await _found.close();
    await _telemetry.close();
  }
}
