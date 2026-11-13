import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/live_service.dart';
import '../../data/medication_reminder_service.dart';
import '../../data/stick_ble_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class WalkingStickScreen extends ConsumerStatefulWidget {
  const WalkingStickScreen({super.key});

  @override
  ConsumerState<WalkingStickScreen> createState() => _WalkingStickScreenState();
}

class _WalkingStickScreenState extends ConsumerState<WalkingStickScreen> {
  Timer? _pollTimer;
  Timer? _stickRelayTimer;
  StreamSubscription<LiveEvent>? _stickEvents;
  StreamSubscription<Position>? _phoneLocation;
  StreamSubscription<StickBleState>? _stickBleStateSub;
  StreamSubscription<List<StickBleDevice>>? _stickBleFoundSub;
  StreamSubscription<Map<String, dynamic>>? _stickBleTelemetrySub;
  bool _loading = true;
  bool _busyAction = false;
  bool _pairingStick = false;
  bool _stickPaired = true;
  bool _startingPhoneLocation = false;
  bool _stickRelayInFlight = false;
  Map<String, dynamic>? _pendingStickRelay;
  String? _error;
  String _personLocationStatus = 'Starting phone GPS…';
  StickBleState _stickBleState = StickBleState.idle;
  List<StickBleDevice> _stickBleDevices = const [];

  Map<String, dynamic> _status = const {};
  bool _geofenceDirty = false;
  bool _geofenceEnabled = false;
  double _radiusM = 250.0;
  double? _centerLat;
  double? _centerLng;
  String _geofenceLabel = 'Home Safety Zone';

  @override
  void initState() {
    super.initState();
    unawaited(_fetchStatus().then((_) => _startPhoneLocation()));
    final stickBle = ref.read(stickBleProvider);
    _stickBleState = stickBle.current;
    _stickBleStateSub = stickBle.state.listen((state) {
      final wasConnected = _stickBleState == StickBleState.connected;
      if (!mounted) return;
      setState(() => _stickBleState = state);
      if (state == StickBleState.idle && wasConnected) {
        unawaited(_fetchStatus(silent: true));
      }
    });
    _stickBleFoundSub = stickBle.found.listen((devices) {
      if (mounted) setState(() => _stickBleDevices = devices);
    });
    _stickBleTelemetrySub = stickBle.telemetry.listen(_onDirectStickTelemetry);
    unawaited(stickBle.autoConnect());
    _stickEvents = ref.read(liveProvider).events.listen((event) {
      if (!mounted || event is! StickChanged) return;
      _onStickSnapshot(event.snapshot);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_busyAction) {
        unawaited(_fetchStatus(silent: true));
      }
    });
  }

  String? _directionPrompt(Map<String, dynamic> snapshot) {
    if (snapshot['online'] != true) return null;
    final data =
        (snapshot['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final serverPrompt = data['voice_prompt'];
    final hasSensorData = const [
      'left_cm',
      'front_cm',
      'right_cm',
      'left_contact',
      'front_contact',
      'right_contact',
    ].any((key) => key.endsWith('_cm') ? data[key] is num : data[key] == true);
    if (!hasSensorData &&
        serverPrompt is String &&
        serverPrompt.trim().isNotEmpty) {
      return serverPrompt.trim();
    }
    double? cm(String key) {
      final value = data[key];
      if (value is! num) return null;
      final distance = value.toDouble();
      if (distance < -1) return null;
      return distance == -1 ? 401 : distance;
    }

    bool contact(String key) => data[key] == true;
    bool blocked(String key, String contactKey) =>
        contact(contactKey) || (cm(key) != null && cm(key)! <= 80);
    bool clear(String key, String contactKey) =>
        cm(key) != null && cm(key)! > 80 && !contact(contactKey);

    final leftBlocked = blocked('left_cm', 'left_contact');
    final frontBlocked = blocked('front_cm', 'front_contact');
    final rightBlocked = blocked('right_cm', 'right_contact');
    final leftClear = clear('left_cm', 'left_contact');
    final frontClear = clear('front_cm', 'front_contact');
    final rightClear = clear('right_cm', 'right_contact');

    if (frontBlocked) {
      if (leftClear && rightClear) {
        final leftDistance = cm('left_cm')!;
        final rightDistance = cm('right_cm')!;
        return leftDistance >= rightDistance
            ? 'Obstacle ahead. Go left.'
            : 'Obstacle ahead. Go right.';
      }
      if (leftClear) return 'Obstacle ahead. Go left.';
      if (rightClear) return 'Obstacle ahead. Go right.';
      return 'Stop. Turn back slowly.';
    }
    if (leftBlocked && rightBlocked) {
      return frontClear
          ? 'Both sides are blocked. Continue straight carefully.'
          : 'Stop. Turn back slowly.';
    }
    if (rightBlocked && !leftBlocked) {
      return leftClear
          ? 'Obstacle on your right. Go left.'
          : 'Stop. Turn back slowly.';
    }
    if (leftBlocked && !rightBlocked) {
      return rightClear
          ? 'Obstacle on your left. Go right.'
          : 'Stop. Turn back slowly.';
    }
    return null;
  }

  String _turnLightFor(Map<String, dynamic> data) {
    final direction = (data['recommended_direction'] ?? '').toString();
    if (direction == 'left' || direction == 'right') return direction;
    if (direction == 'stop') return 'hazard';
    final guidance = (data['voice_prompt'] ?? data['guidance'] ?? '')
        .toString()
        .toLowerCase();
    if (guidance.contains('go left')) return 'left';
    if (guidance.contains('go right')) return 'right';
    if (guidance.contains('stop')) return 'hazard';
    return 'off';
  }

  String? _pendingGuidance;
  int _matchingGuidanceFrames = 0;
  String? _lastAnnouncedGuidance;

  void _onStickSnapshot(Map<String, dynamic> snapshot,
      {bool markPaired = true}) {
    setState(() {
      _status = snapshot;
      _loading = false;
      _error = null;
      if (markPaired) _stickPaired = true;
    });
    _announceGuidance(snapshot);
  }

  void _onDirectStickTelemetry(Map<String, dynamic> telemetry) {
    if (!mounted) return;
    _queueStickTelemetryRelay(telemetry);
    final currentData = (_status['data'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    _onStickSnapshot(
      {
        ..._status,
        'online': true,
        'age_ms': 0,
        'link_mode': 'bluetooth',
        'data': {...currentData, ...telemetry},
      },
      markPaired: false,
    );
  }

  void _queueStickTelemetryRelay(Map<String, dynamic> telemetry) {
    _pendingStickRelay = Map<String, dynamic>.from(telemetry);
    if (!_stickPaired || _stickRelayInFlight || _stickRelayTimer != null)
      return;
    _stickRelayTimer = Timer(const Duration(seconds: 1), () {
      _stickRelayTimer = null;
      unawaited(_flushStickTelemetryRelay());
    });
  }

  Future<void> _flushStickTelemetryRelay() async {
    if (!mounted || !_stickPaired || _stickRelayInFlight) return;
    final telemetry = _pendingStickRelay;
    if (telemetry == null) return;
    _pendingStickRelay = null;
    _stickRelayInFlight = true;
    var retryDelay = const Duration(seconds: 1);
    try {
      await ref.read(apiProvider).relayStickBluetoothTelemetry(telemetry);
    } catch (_) {
      // Local Bluetooth readings and voice guidance keep working offline.
      retryDelay = const Duration(seconds: 5);
    } finally {
      _stickRelayInFlight = false;
      if (mounted && _pendingStickRelay != null && _stickRelayTimer == null) {
        _stickRelayTimer = Timer(retryDelay, () {
          _stickRelayTimer = null;
          unawaited(_flushStickTelemetryRelay());
        });
      }
    }
  }

  Future<void> _scanStickBluetooth() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      await ref.read(stickBleProvider).scan();
    } catch (error) {
      if (mounted)
        showSnack(context, 'Walking-stick Bluetooth scan failed: $error',
            error: true);
    }
  }

  Future<void> _connectStickBluetooth(String id) async {
    try {
      await ref.read(stickBleProvider).connect(id);
      if (mounted)
        showSnack(context, 'Walking stick connected over Bluetooth.');
    } catch (error) {
      if (mounted)
        showSnack(context, 'Walking-stick Bluetooth connection failed: $error',
            error: true);
    }
  }

  Future<void> _disconnectStickBluetooth() async {
    await ref.read(stickBleProvider).disconnect();
    if (mounted)
      showSnack(context, 'Walking stick disconnected from Bluetooth.');
  }

  Future<void> _testStickTurnLights() async {
    try {
      await ref.read(stickBleProvider).sendCommand('test_led');
      if (mounted)
        showSnack(context, 'Three turn-light test flashes sent to the stick.');
    } catch (error) {
      if (mounted)
        showSnack(context, 'Turn-light test failed: $error', error: true);
    }
  }

  void _announceGuidance(Map<String, dynamic> snapshot) {
    final prompt = _directionPrompt(snapshot);
    if (prompt == null) {
      _pendingGuidance = null;
      _matchingGuidanceFrames = 0;
      _lastAnnouncedGuidance = null;
      return;
    }
    if (_pendingGuidance == prompt) {
      _matchingGuidanceFrames++;
    } else {
      _pendingGuidance = prompt;
      _matchingGuidanceFrames = 1;
    }
    if (_matchingGuidanceFrames >= 2 && _lastAnnouncedGuidance != prompt) {
      _lastAnnouncedGuidance = prompt;
      unawaited(MedicationReminderService.speakPrompt(prompt));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _stickRelayTimer?.cancel();
    _stickEvents?.cancel();
    _stickBleStateSub?.cancel();
    _stickBleFoundSub?.cancel();
    _stickBleTelemetrySub?.cancel();
    _phoneLocation?.cancel();
    super.dispose();
  }

  Future<void> _startPhoneLocation({bool openSettingsIfNeeded = false}) async {
    if (_phoneLocation != null || _startingPhoneLocation || !mounted) return;
    if (!_stickPaired) {
      setState(() =>
          _personLocationStatus = 'Pair the stick to enable person location.');
      return;
    }
    _startingPhoneLocation = true;
    setState(() => _personLocationStatus = 'Checking phone location…');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _personLocationStatus =
              'Turn on phone Location to track the person.');
        }
        if (openSettingsIfNeeded) await Geolocator.openLocationSettings();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() =>
              _personLocationStatus = 'Allow Location in phone app settings.');
        }
        if (openSettingsIfNeeded) await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        if (mounted) {
          setState(() =>
              _personLocationStatus = 'Phone location permission is needed.');
        }
        return;
      }

      final initial = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _uploadPersonPosition(initial);
      if (!mounted) return;
      _phoneLocation = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (position) => unawaited(_uploadPersonPosition(position)),
        onError: (Object error) {
          if (mounted) {
            setState(() => _personLocationStatus = 'Phone GPS paused: $error');
          }
        },
      );
      setState(
          () => _personLocationStatus = 'Phone GPS is tracking the person.');
    } catch (error) {
      if (mounted) {
        setState(() => _personLocationStatus = 'Phone GPS unavailable: $error');
      }
    } finally {
      _startingPhoneLocation = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _uploadPersonPosition(Position position) async {
    try {
      final response = await ref.read(apiProvider).updateStickPersonLocation(
            lat: position.latitude,
            lng: position.longitude,
            accuracyM: position.accuracy.isFinite ? position.accuracy : null,
            speedKmh: position.speed.isFinite
                ? (position.speed * 3.6).clamp(0.0, 300.0).toDouble()
                : null,
            heading: position.heading.isFinite && position.heading >= 0
                ? position.heading.clamp(0.0, 360.0).toDouble()
                : null,
          );
      if (!mounted) return;
      final data = (response['data'] as Map?)?.cast<String, dynamic>();
      if (data != null) {
        setState(() {
          _status = {..._status, 'data': data};
          _personLocationStatus = 'Phone GPS is tracking the person.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _personLocationStatus =
            'Phone GPS active • cloud update failed: $error');
      }
    }
  }

  Future<void> _fetchStatus({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = _status.isEmpty;
        _error = null;
      });
    }
    try {
      final res = await ref.read(apiProvider).stickStatus();
      if (!mounted) return;
      final geo =
          (res['geofence'] as Map?)?.cast<String, dynamic>() ?? const {};
      setState(() {
        _status = res;
        _loading = false;
        _error = null;
        _stickPaired = true;
        if (!_geofenceDirty && geo.isNotEmpty) {
          _geofenceEnabled = geo['enabled'] == true;
          _radiusM = ((geo['radius_m'] as num?)?.toDouble() ?? 250.0)
              .clamp(50.0, 1000.0);
          _centerLat = (geo['center_lat'] as num?)?.toDouble();
          _centerLng = (geo['center_lng'] as num?)?.toDouble();
          _geofenceLabel = (geo['label'] as String?)?.trim().isNotEmpty == true
              ? geo['label'] as String
              : 'Home Safety Zone';
        }
      });
      _announceGuidance(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is ApiException &&
            e.status == 404 &&
            e.message.contains('not paired')) {
          _stickPaired = false;
          _error =
              'Pair the walking stick to this account to view its live data.';
        }
        if (!silent || _status.isEmpty) {
          _error ??= e.toString();
        }
      });
    }
  }

  Future<void> _saveGeofence() async {
    if (_geofenceEnabled && (_centerLat == null || _centerLng == null)) {
      showSnack(
          context, 'Set a safe-zone center from phone GPS or VitaWatch first.',
          error: true);
      return;
    }
    setState(() => _busyAction = true);
    try {
      await ref.read(apiProvider).updateStickGeofence(
            enabled: _geofenceEnabled,
            centerLat: _centerLat,
            centerLng: _centerLng,
            radiusM: _radiusM,
            label: _geofenceLabel,
          );
      _geofenceDirty = false;
      await _fetchStatus(silent: true);
      if (mounted) {
        showSnack(
          context,
          'Safe-Zone geofence saved (${_radiusM.round()}m • ${_geofenceEnabled ? "Active" : "Disabled"}).',
        );
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'Failed to save geofence: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _syncWithWatch() async {
    setState(() => _busyAction = true);
    try {
      final res = await ref.read(apiProvider).syncStickWithWatch();
      final loc = (res['location'] as Map?)?.cast<String, dynamic>();
      if (loc != null) {
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          setState(() {
            _centerLat = lat;
            _centerLng = lng;
            _geofenceDirty = true;
          });
        }
      }
      await _fetchStatus(silent: true);
      if (mounted) {
        final msg = (res['message'] as String?) ??
            'Walking stick GPS synchronized with VitaWatch.';
        showSnack(context, msg);
      }
    } catch (e) {
      if (mounted)
        showSnack(context, 'Sync with VitaWatch failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _usePhoneLocation() async {
    setState(() => _busyAction = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Turn on location services and try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Allow location access to set the safe-zone center.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _centerLat = position.latitude;
        _centerLng = position.longitude;
        _geofenceDirty = true;
      });
      await _uploadPersonPosition(position);
      unawaited(_startPhoneLocation());
      showSnack(context,
          'Phone GPS set as the safe-zone center. Save the geofence to apply it.');
    } catch (e) {
      if (mounted)
        showSnack(context, 'Could not get phone location: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _pairStick() async {
    setState(() => _pairingStick = true);
    try {
      await ref.read(apiProvider).pair('esp32_walking_stick_01');
      if (!mounted) return;
      setState(() => _stickPaired = true);
      await _fetchStatus();
      await _startPhoneLocation();
      if (mounted) showSnack(context, 'Walking stick paired to this account.');
    } catch (e) {
      if (mounted)
        showSnack(context, 'Could not pair walking stick: $e', error: true);
    } finally {
      if (mounted) setState(() => _pairingStick = false);
    }
  }

  Future<void> _runSimulation(
      String label, Map<String, dynamic> payload) async {
    setState(() => _busyAction = true);
    try {
      await ref.read(apiProvider).simulateStick(payload);
      await _fetchStatus(silent: true);
      if (mounted) {
        showSnack(context, 'Simulated: $label');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Simulation failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Color _zoneColor(double cm, bool contact) {
    if (cm <= -2 && !contact) return Palette.textDim;
    if (cm == -1 && !contact) return Palette.green;
    if (contact || (cm >= 0 && cm <= 15)) return Palette.red;
    if (cm > 15 && cm <= 50) return Palette.amber;
    if (cm > 50) return Palette.teal;
    return Palette.green;
  }

  String _formatCm(double cm) {
    if (cm <= -2) return 'NO DATA';
    if (cm == -1) return '>200 cm';
    if (cm < 10) return '${cm.toStringAsFixed(1)} cm';
    return '${cm.round()} cm';
  }

  Color _geofenceColor(String status) {
    switch (status.toLowerCase()) {
      case 'breached':
        return Palette.red;
      case 'warning':
        return Palette.amber;
      case 'disabled':
      case 'unconfigured':
        return Palette.textDim;
      default:
        return Palette.green;
    }
  }

  String _formatGuidance(String raw) {
    final clean = raw.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'clear') {
      return 'CLEAR PATH — SAFE TO PROCEED FORWARD';
    }
    return clean.replaceAll('_', ' ').toUpperCase();
  }

  String _formatTimestamp(dynamic rawMs) {
    final ms = (rawMs as num?)?.toInt();
    if (ms == null || ms <= 0) return 'Just now';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final online = _status['online'] == true;
    final stickBluetoothConnected = _stickBleState == StickBleState.connected;
    final stickBluetoothBusy = _stickBleState == StickBleState.scanning ||
        _stickBleState == StickBleState.connecting;
    final deviceId =
        (_status['device_id'] as String?) ?? 'esp32_walking_stick_01';
    final data = (_status['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    final leftCm = (data['left_cm'] as num?)?.toDouble() ?? -2.0;
    final frontCm = (data['front_cm'] as num?)?.toDouble() ?? -2.0;
    final rightCm = (data['right_cm'] as num?)?.toDouble() ?? -2.0;

    final leftContact = data['left_contact'] == true;
    final frontContact = data['front_contact'] == true;
    final rightContact = data['right_contact'] == true;
    final anyContact = leftContact || frontContact || rightContact;

    final guidance = (data['guidance'] as String?) ?? 'unknown';
    final turnLight = (data['turn_light'] as String?) ?? _turnLightFor(data);
    final ldrRaw = (data['ldr_raw'] as num?)?.toInt();
    final lightOn = data['light_on'] == true;
    final rssi = (data['rssi'] as num?)?.toInt();
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    final hasLocation = lat != null && lng != null;
    final trackingMode = (data['tracking_mode'] as String?) ?? 'unavailable';
    final address = (data['address'] as String?) ??
        (trackingMode == 'simulated'
            ? 'Simulated location'
            : 'GPS fix unavailable');
    final simulated = trackingMode == 'simulated';
    final geofenceStatus = (data['geofence_status'] as String?) ?? 'disabled';
    final demoLat = _centerLat ?? 12.9716;
    final demoLng = _centerLng ?? 77.5946;
    final ldrProgress = ((ldrRaw ?? 0) / 1023.0).clamp(0.0, 1.0);

    final rawEvents = (_status['latest_events'] as List?) ?? const [];
    final events = rawEvents
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList()
        .reversed
        .toList();

    final geoColor = _geofenceColor(geofenceStatus);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('Smart Walking Stick'),
              actions: [
                IconButton(
                  tooltip: 'Refresh Telemetry',
                  onPressed: _busyAction ? null : () => _fetchStatus(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      body: RefreshIndicator(
        color: Palette.teal,
        backgroundColor: Palette.surfaceHi,
        onRefresh: () => _fetchStatus(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          children: [
            if (!canPop) ...[
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Palette.redLight,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🦯', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart Walking Stick',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '3-Zone Ultrasonic Radar • Auto-Headlight • Geofence',
                          style:
                              TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh Telemetry',
                    onPressed: _busyAction ? null : () => _fetchStatus(),
                    icon:
                        const Icon(Icons.refresh_rounded, color: Palette.text),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Top Telemetry Link Banner
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: online && !simulated
                  ? Palette.teal.withValues(alpha: 0.55)
                  : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (online && !simulated
                                  ? Palette.teal
                                  : Palette.blue)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.elderly_rounded,
                          color: online && !simulated
                              ? Palette.teal
                              : Palette.blue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'ESP32 #2 • $deviceId',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Palette.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Mode: ${trackingMode.toUpperCase()} • RSSI ${rssi == null ? '--' : '$rssi dBm'} • Live updates',
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 12,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (simulated
                                  ? Palette.blue
                                  : online
                                      ? Palette.green
                                      : Palette.amber)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (simulated
                                    ? Palette.blue
                                    : online
                                        ? Palette.green
                                        : Palette.amber)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          simulated
                              ? 'SIMULATED'
                              : online
                                  ? 'ONLINE'
                                  : 'OFFLINE',
                          style: TextStyle(
                            color: simulated
                                ? Palette.blue
                                : online
                                    ? Palette.green
                                    : Palette.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 16, color: Palette.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasLocation
                                    ? '$address (${lat?.toStringAsFixed(5)}, ${lng?.toStringAsFixed(5)})'
                                    : 'Phone GPS fix unavailable',
                                style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 12,
                                  fontFeatures: kTabular,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _personLocationStatus,
                                style: const TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_phoneLocation == null && _stickPaired) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Enable phone GPS for person location',
                            onPressed: _startingPhoneLocation
                                ? null
                                : () => _startPhoneLocation(
                                    openSettingsIfNeeded: true),
                            icon: const Icon(Icons.gps_fixed_rounded,
                                color: Palette.teal),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SectionHeader(
              'Direct Bluetooth • Walking Stick',
              action: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (stickBluetoothConnected
                          ? Palette.green
                          : Palette.textDim)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  stickBluetoothConnected
                      ? 'CONNECTED'
                      : 'BLE ${_stickBleState.name.toUpperCase()}',
                  style: TextStyle(
                    color: stickBluetoothConnected
                        ? Palette.green
                        : Palette.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_connected_rounded,
                          color: Palette.teal, size: 22),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          stickBluetoothConnected
                              ? 'Live readings from ${ref.read(stickBleProvider).connectedName ?? 'Jeevan-Stick'}'
                              : stickBluetoothBusy
                                  ? 'Searching or connecting to Jeevan-Stick…'
                                  : 'Pair the stick directly for fast live readings.',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: stickBluetoothBusy || stickBluetoothConnected
                            ? null
                            : _scanStickBluetooth,
                        icon: const Icon(Icons.search_rounded, size: 16),
                        label: Text(_stickBleState == StickBleState.scanning
                            ? 'Scanning…'
                            : 'Scan'),
                      ),
                    ],
                  ),
                  if (stickBluetoothConnected) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testStickTurnLights,
                          icon: const Icon(Icons.flash_on_rounded, size: 16),
                          label: const Text('Test turn lights'),
                        ),
                        TextButton.icon(
                          onPressed: _disconnectStickBluetooth,
                          icon: const Icon(Icons.link_off_rounded, size: 16),
                          label: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  ] else if (_stickBleDevices.isNotEmpty) ...[
                    const Divider(height: 18),
                    for (final device in _stickBleDevices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.elderly_rounded,
                            color: Palette.teal),
                        title: Text(device.name),
                        subtitle: Text('${device.id} • ${device.rssi} dBm'),
                        trailing: FilledButton.tonal(
                          onPressed: stickBluetoothBusy
                              ? null
                              : () => _connectStickBluetooth(device.id),
                          child: const Text('Connect'),
                        ),
                      ),
                  ] else if (!stickBluetoothBusy) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Power on the stick ESP32 and tap Scan. The VitaWatch remains on its own Bluetooth connection.',
                      style: TextStyle(color: Palette.textDim, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(14),
                color: Palette.red.withValues(alpha: 0.10),
                borderColor: Palette.red.withValues(alpha: 0.45),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Palette.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style:
                            const TextStyle(color: Palette.text, fontSize: 13),
                      ),
                    ),
                    if (!_stickPaired) ...[
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _pairingStick ? null : _pairStick,
                        child: Text(_pairingStick ? 'Pairing…' : 'Pair stick'),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 1. Visual 3-Zone Ultrasonic Obstacle Radar
            SectionHeader(
              '3-Zone Ultrasonic Obstacle Radar',
              action: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (anyContact ? Palette.red : Palette.teal)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  anyContact ? 'CONTACT ALERT' : '3 HC-SR04 ACTIVE',
                  style: TextStyle(
                    color: anyContact ? Palette.red : Palette.teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.all(18),
              borderColor: anyContact
                  ? Palette.red.withValues(alpha: 0.65)
                  : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Voice / Haptic Guidance Banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: (anyContact
                              ? Palette.red
                              : (frontCm > 0 && frontCm <= 45)
                                  ? Palette.amber
                                  : Palette.teal)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (anyContact
                                ? Palette.red
                                : (frontCm > 0 && frontCm <= 45)
                                    ? Palette.amber
                                    : Palette.teal)
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          anyContact
                              ? Icons.warning_amber_rounded
                              : Icons.record_voice_over_rounded,
                          color: anyContact
                              ? Palette.red
                              : (frontCm > 0 && frontCm <= 45)
                                  ? Palette.amber
                                  : Palette.teal,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'HAPTIC & AUDIO GUIDANCE',
                                style: TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatGuidance(guidance),
                                style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (turnLight != 'off') ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Palette.amber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Palette.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            turnLight == 'left'
                                ? Icons.turn_left_rounded
                                : turnLight == 'right'
                                    ? Icons.turn_right_rounded
                                    : Icons.warning_amber_rounded,
                            color: Palette.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            turnLight == 'hazard'
                                ? 'TURN LIGHTS: BOTH • STOP'
                                : 'TURN LIGHT: ${turnLight.toUpperCase()}',
                            style: const TextStyle(
                              color: Palette.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // 3 Ultrasonic Zone Tiles (Left / Front / Right)
                  Row(
                    children: [
                      Expanded(
                        child: _RadarZoneTile(
                          direction: 'LEFT ZONE',
                          icon: Icons.turn_left_rounded,
                          cm: leftCm,
                          contact: leftContact,
                          color: _zoneColor(leftCm, leftContact),
                          formattedCm: _formatCm(leftCm),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RadarZoneTile(
                          direction: 'FRONT ZONE',
                          icon: Icons.straight_rounded,
                          cm: frontCm,
                          contact: frontContact,
                          color: _zoneColor(frontCm, frontContact),
                          formattedCm: _formatCm(frontCm),
                          emphasized: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RadarZoneTile(
                          direction: 'RIGHT ZONE',
                          icon: Icons.turn_right_rounded,
                          cm: rightCm,
                          contact: rightContact,
                          color: _zoneColor(rightCm, rightContact),
                          formattedCm: _formatCm(rightCm),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. LDR Ambient Light & Auto-Headlight Card
            const SectionHeader('Ambient Light (LDR) & Auto-Headlight'),
            GlassCard(
              padding: const EdgeInsets.all(18),
              borderColor: lightOn
                  ? Palette.amber.withValues(alpha: 0.6)
                  : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: (lightOn ? Palette.amber : Palette.blue)
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          lightOn
                              ? Icons.highlight_rounded
                              : Icons.wb_sunny_rounded,
                          color: lightOn ? Palette.amber : Palette.blue,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lightOn
                                  ? 'Night Headlight ACTIVE'
                                  : ldrRaw == null
                                      ? 'Light state unavailable'
                                      : 'Daylight Standby Mode',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'LDR Sensor Raw: ${ldrRaw ?? '--'} / 1023',
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 13,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (lightOn ? Palette.amber : Palette.surfaceHi)
                              .withValues(alpha: lightOn ? 0.20 : 1.0),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: lightOn ? Palette.amber : Palette.outline,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              lightOn
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              size: 14,
                              color: lightOn ? Palette.amber : Palette.textDim,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ldrRaw == null
                                  ? 'NO DATA'
                                  : lightOn
                                      ? 'LIGHT ON'
                                      : 'LIGHT OFF',
                              style: TextStyle(
                                color: ldrRaw == null
                                    ? Palette.textDim
                                    : lightOn
                                        ? Palette.amber
                                        : Palette.textDim,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: ldrRaw == null ? 0 : ldrProgress,
                      minHeight: 8,
                      backgroundColor: Palette.surfaceHi,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        lightOn ? Palette.amber : Palette.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '0 (Pitch Dark → Auto LED ON)',
                        style: TextStyle(color: Palette.textDim, fontSize: 11),
                      ),
                      Text(
                        ldrRaw == null
                            ? 'NO DATA'
                            : '${(ldrProgress * 100).round()}% Lum',
                        style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 11,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. Safe-Zone Geofence Card
            SectionHeader(
              'Safe-Zone Geofence Perimeter',
              action: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: geoColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: geoColor.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: geoColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      geofenceStatus.toUpperCase(),
                      style: TextStyle(
                        color: geoColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.all(18),
              borderColor: geofenceStatus == 'breached'
                  ? Palette.red.withValues(alpha: 0.65)
                  : geofenceStatus == 'warning'
                      ? Palette.amber.withValues(alpha: 0.55)
                      : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: geoColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.radar_rounded,
                            color: geoColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _geofenceLabel,
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _centerLat == null || _centerLng == null
                                  ? 'Center not set • use phone GPS or sync VitaWatch'
                                  : 'Center: ${_centerLat!.toStringAsFixed(5)}, ${_centerLng!.toStringAsFixed(5)}',
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 12,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _geofenceEnabled,
                        activeColor: Palette.teal,
                        onChanged: (v) {
                          if (v && (_centerLat == null || _centerLng == null)) {
                            showSnack(context,
                                'Set a safe-zone center from phone GPS or VitaWatch first.',
                                error: true);
                            return;
                          }
                          setState(() {
                            _geofenceEnabled = v;
                            _geofenceDirty = true;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Safe Perimeter Radius',
                        style: TextStyle(
                          color: Palette.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_radiusM.round()} meters',
                        style: const TextStyle(
                          color: Palette.teal,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Palette.teal,
                      inactiveTrackColor: Palette.surfaceHi,
                      thumbColor: Palette.teal,
                      overlayColor: Palette.teal.withValues(alpha: 0.16),
                    ),
                    child: Slider(
                      value: _radiusM.clamp(50.0, 1000.0),
                      min: 50.0,
                      max: 1000.0,
                      divisions: 19,
                      label: '${_radiusM.round()}m',
                      onChanged: _geofenceEnabled
                          ? (v) {
                              setState(() {
                                _radiusM = v;
                                _geofenceDirty = true;
                              });
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.teal,
                        side: BorderSide(
                            color: Palette.teal.withValues(alpha: 0.45)),
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _busyAction ? null : _usePhoneLocation,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Use phone GPS for safe-zone center'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Palette.blue,
                            side: BorderSide(
                                color: Palette.blue.withValues(alpha: 0.45)),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _busyAction ? null : _syncWithWatch,
                          icon: const Icon(Icons.watch_rounded, size: 18),
                          label: const Text('Sync GPS with VitaWatch'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _busyAction ? null : _saveGeofence,
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Save Geofence'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 4. Hardware Simulator Bar
            const SectionHeader('Demo Simulator • Not live hardware'),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Creates clearly marked sample telemetry for checking the screen and spoken turn prompts. It does not control the stick.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SimButton(
                        label: 'Clear Path',
                        icon: Icons.check_circle_outline_rounded,
                        color: Palette.green,
                        disabled: _busyAction,
                        onTap: () => _runSimulation('Clear Path', {
                          'left_cm': 140,
                          'front_cm': 185,
                          'right_cm': 150,
                          'ldr_raw': 640,
                          'guidance': 'clear',
                          'lat': _centerLat ?? demoLat,
                          'lng': _centerLng ?? demoLng,
                          'code': 'clear_path',
                          'priority': 1,
                          'message':
                              'All 3 ultrasonic zones clear — normal daylight walking.',
                        }),
                      ),
                      _SimButton(
                        label: 'Front Obstacle (25cm)',
                        icon: Icons.sensors_rounded,
                        color: Palette.amber,
                        disabled: _busyAction,
                        onTap: () => _runSimulation('Front Obstacle (25cm)', {
                          'left_cm': 115,
                          'front_cm': 25,
                          'right_cm': 95,
                          'ldr_raw': 510,
                          'guidance':
                              'Obstacle 25cm ahead — veer left or right',
                          'lat': _centerLat ?? demoLat,
                          'lng': _centerLng ?? demoLng,
                          'code': 'front_obstacle',
                          'priority': 2,
                          'message':
                              'Front ultrasonic cone detected obstacle at 25 cm.',
                        }),
                      ),
                      _SimButton(
                        label: 'Right Obstacle • Go Left',
                        icon: Icons.turn_left_rounded,
                        color: Palette.amber,
                        disabled: _busyAction,
                        onTap: () =>
                            _runSimulation('Right obstacle — go left', {
                          'left_cm': 130,
                          'front_cm': 120,
                          'right_cm': 25,
                          'ldr_raw': 520,
                          'ldr_threshold': 100,
                          'guidance': 'Obstacle on right — go left',
                          'lat': _centerLat ?? demoLat,
                          'lng': _centerLng ?? demoLng,
                          'code': 'right_obstacle',
                          'priority': 2,
                          'message':
                              'Right zone obstacle at 25 cm. Voice guidance: go left.',
                        }),
                      ),
                      _SimButton(
                        label: 'Left Obstacle • Go Right',
                        icon: Icons.turn_right_rounded,
                        color: Palette.amber,
                        disabled: _busyAction,
                        onTap: () =>
                            _runSimulation('Left obstacle — go right', {
                          'left_cm': 25,
                          'front_cm': 120,
                          'right_cm': 130,
                          'ldr_raw': 520,
                          'ldr_threshold': 100,
                          'guidance': 'Obstacle on left — go right',
                          'lat': _centerLat ?? demoLat,
                          'lng': _centerLng ?? demoLng,
                          'code': 'left_obstacle',
                          'priority': 2,
                          'message':
                              'Left zone obstacle at 25 cm. Voice guidance: go right.',
                        }),
                      ),
                      _SimButton(
                        label: 'Left Contact (3cm) + Night Headlight',
                        icon: Icons.highlight_rounded,
                        color: Palette.orange,
                        disabled: _busyAction,
                        onTap: () => _runSimulation(
                          'Left Contact (3cm) + Night Headlight',
                          {
                            'left_cm': 3,
                            'front_cm': 80,
                            'right_cm': 125,
                            'ldr_raw': 38,
                            'guidance':
                                'Immediate left contact (3cm) — step right! Night LED ON',
                            'lat': _centerLat ?? demoLat,
                            'lng': _centerLng ?? demoLng,
                            'code': 'left_contact_night',
                            'priority': 3,
                            'message':
                                'Left contact hazard (3cm) & low ambient light (LDR 38) — auto-headlight ON.',
                          },
                        ),
                      ),
                      _SimButton(
                        label: 'Simulate Geofence Breach',
                        icon: Icons.wrong_location_rounded,
                        color: Palette.red,
                        disabled: _busyAction,
                        onTap: () =>
                            _runSimulation('Simulate Geofence Breach', {
                          'left_cm': 95,
                          'front_cm': 130,
                          'right_cm': 110,
                          'ldr_raw': 490,
                          'guidance':
                              'Safe-Zone perimeter breached — caregiver alerted',
                          'lat': demoLat + 0.015,
                          'lng': demoLng + 0.015,
                          'code': 'geofence_breach',
                          'priority': 3,
                          'message':
                              'Safe Zone Alert: Walking stick exited designated Home Safety Zone!',
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 5. Recent Stick Events List
            SectionHeader(
              'Recent Stick Events',
              action: Text(
                '${events.length} logged',
                style: const TextStyle(color: Palette.textDim, fontSize: 12),
              ),
            ),
            if (_loading && events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: Palette.teal),
                ),
              )
            else if (events.isEmpty)
              const EmptyState(
                Icons.history_toggle_off_rounded,
                'No Stick Events Logged Yet',
                'Use the Hardware Simulator buttons above or walk with the ESP32 Smart Stick to record obstacle, headlight, and geofence events.',
              )
            else
              ...events.map((ev) {
                final priority = (ev['priority'] as num?)?.toInt() ?? 1;
                final source = (ev['source'] as String?) ?? 'stick';
                final code = (ev['code'] as String?) ?? 'event';
                final msg =
                    (ev['message'] as String?) ?? 'Stick telemetry event';
                final color = priority >= 3
                    ? Palette.red
                    : priority == 2
                        ? Palette.amber
                        : Palette.teal;

                IconData icon = Icons.sensors_rounded;
                if (source == 'geofence' || code.contains('geofence')) {
                  icon = Icons.wrong_location_rounded;
                } else if (source == 'light' || code.contains('night')) {
                  icon = Icons.highlight_rounded;
                } else if (source == 'collision' || code.contains('contact')) {
                  icon = Icons.warning_amber_rounded;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    borderColor: priority >= 3
                        ? Palette.red.withValues(alpha: 0.45)
                        : Palette.outline,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      code.toUpperCase(),
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTimestamp(ev['received_at']),
                                    style: const TextStyle(
                                      color: Palette.textDim,
                                      fontSize: 11,
                                      fontFeatures: kTabular,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                msg,
                                style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _RadarZoneTile extends StatelessWidget {
  const _RadarZoneTile({
    required this.direction,
    required this.icon,
    required this.cm,
    required this.contact,
    required this.color,
    required this.formattedCm,
    this.emphasized = false,
  });

  final String direction;
  final IconData icon;
  final double cm;
  final bool contact;
  final Color color;
  final String formattedCm;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color:
            emphasized ? Palette.surfaceHi : Palette.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: contact ? Palette.red : color.withValues(alpha: 0.45),
          width: contact ? 1.6 : 1.0,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            direction,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formattedCm,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFeatures: kTabular,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (contact ? Palette.red : color).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              contact
                  ? 'CONTACT!'
                  : (cm >= 0 && cm <= 45)
                      ? 'NEAR'
                      : 'CLEAR',
              style: TextStyle(
                color: contact ? Palette.red : color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimButton extends StatelessWidget {
  const _SimButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
