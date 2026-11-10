import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

class WalkingStickScreen extends ConsumerStatefulWidget {
  const WalkingStickScreen({super.key});

  @override
  ConsumerState<WalkingStickScreen> createState() => _WalkingStickScreenState();
}

class _WalkingStickScreenState extends ConsumerState<WalkingStickScreen> {
  Timer? _pollTimer;
  bool _loading = true;
  bool _busyAction = false;
  String? _error;

  Map<String, dynamic> _status = const {};
  bool _geofenceDirty = false;
  bool _geofenceEnabled = true;
  double _radiusM = 250.0;
  double _centerLat = 12.9716;
  double _centerLng = 77.5946;
  String _geofenceLabel = 'Home Safety Zone';

  @override
  void initState() {
    super.initState();
    unawaited(_fetchStatus());
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_busyAction) {
        unawaited(_fetchStatus(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
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
      final geo = (res['geofence'] as Map?)?.cast<String, dynamic>() ?? const {};
      setState(() {
        _status = res;
        _loading = false;
        _error = null;
        if (!_geofenceDirty && geo.isNotEmpty) {
          _geofenceEnabled = geo['enabled'] == true;
          _radiusM = ((geo['radius_m'] as num?)?.toDouble() ?? 250.0).clamp(50.0, 1000.0);
          _centerLat = (geo['center_lat'] as num?)?.toDouble() ?? 12.9716;
          _centerLng = (geo['center_lng'] as num?)?.toDouble() ?? 77.5946;
          _geofenceLabel = (geo['label'] as String?)?.trim().isNotEmpty == true
              ? geo['label'] as String
              : 'Home Safety Zone';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _status.isEmpty) {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _saveGeofence() async {
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
      if (mounted) showSnack(context, 'Failed to save geofence: $e', error: true);
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
          _centerLat = lat;
          _centerLng = lng;
        }
      }
      await _fetchStatus(silent: true);
      if (mounted) {
        final msg = (res['message'] as String?) ??
            'Walking stick GPS synchronized with VitaWatch.';
        showSnack(context, msg);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Sync with VitaWatch failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _runSimulation(String label, Map<String, dynamic> payload) async {
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
    if (contact || (cm >= 0 && cm <= 15)) return Palette.red;
    if (cm > 15 && cm <= 50) return Palette.amber;
    if (cm > 50) return Palette.teal;
    return Palette.green;
  }

  String _formatCm(double cm) {
    if (cm < 0) return '>200 cm';
    if (cm < 10) return '${cm.toStringAsFixed(1)} cm';
    return '${cm.round()} cm';
  }

  Color _geofenceColor(String status) {
    switch (status.toLowerCase()) {
      case 'breached':
        return Palette.red;
      case 'warning':
        return Palette.amber;
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
    final deviceId = (_status['device_id'] as String?) ?? 'esp32_walking_stick_01';
    final data = (_status['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    final leftCm = (data['left_cm'] as num?)?.toDouble() ?? -1.0;
    final frontCm = (data['front_cm'] as num?)?.toDouble() ?? -1.0;
    final rightCm = (data['right_cm'] as num?)?.toDouble() ?? -1.0;

    final leftContact = data['left_contact'] == true;
    final frontContact = data['front_contact'] == true;
    final rightContact = data['right_contact'] == true;
    final anyContact = leftContact || frontContact || rightContact;

    final guidance = (data['guidance'] as String?) ?? 'clear';
    final ldrRaw = (data['ldr_raw'] as num?)?.toInt() ?? 500;
    final lightOn = data['light_on'] == true;
    final rssi = (data['rssi'] as num?)?.toInt() ?? -60;
    final lat = (data['lat'] as num?)?.toDouble() ?? 12.9716;
    final lng = (data['lng'] as num?)?.toDouble() ?? 77.5946;
    final address = (data['address'] as String?) ?? 'MG Road, Bangalore, Karnataka';
    final trackingMode = (data['tracking_mode'] as String?) ?? 'simulated';
    final geofenceStatus = (data['geofence_status'] as String?) ?? 'safe';

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
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh Telemetry',
                    onPressed: _busyAction ? null : () => _fetchStatus(),
                    icon: const Icon(Icons.refresh_rounded, color: Palette.text),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // Top Telemetry Link Banner
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: online ? Palette.teal.withValues(alpha: 0.55) : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: (online ? Palette.teal : Palette.blue).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.elderly_rounded,
                          color: online ? Palette.teal : Palette.blue,
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
                              'Mode: ${trackingMode.toUpperCase()} • RSSI $rssi dBm • Auto-poll 3s',
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (online ? Palette.green : Palette.amber).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (online ? Palette.green : Palette.amber).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          online ? 'ONLINE' : 'STANDBY / SIM',
                          style: TextStyle(
                            color: online ? Palette.green : Palette.amber,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: Palette.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$address (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 12,
                              fontFeatures: kTabular,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    const Icon(Icons.error_outline_rounded, color: Palette.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Palette.text, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // 1. Visual 3-Zone Ultrasonic Obstacle Radar
            SectionHeader(
              '3-Zone Ultrasonic Obstacle Radar',
              action: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (anyContact ? Palette.red : Palette.teal).withValues(alpha: 0.14),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              borderColor: lightOn ? Palette.amber.withValues(alpha: 0.6) : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: (lightOn ? Palette.amber : Palette.blue).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          lightOn ? Icons.highlight_rounded : Icons.wb_sunny_rounded,
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
                              lightOn ? 'Night Headlight ACTIVE' : 'Daylight Standby Mode',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'LDR Sensor Raw: $ldrRaw / 1023',
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              lightOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                              size: 14,
                              color: lightOn ? Palette.amber : Palette.textDim,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              lightOn ? 'LIGHT ON' : 'LIGHT OFF',
                              style: TextStyle(
                                color: lightOn ? Palette.amber : Palette.textDim,
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
                      value: (ldrRaw / 1023.0).clamp(0.0, 1.0),
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
                        '${((ldrRaw / 1023.0) * 100).clamp(0, 100).round()}% Lum',
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      decoration: BoxDecoration(color: geoColor, shape: BoxShape.circle),
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
                        child: Icon(Icons.radar_rounded, color: geoColor, size: 24),
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
                              'Center: ${_centerLat.toStringAsFixed(4)}, ${_centerLng.toStringAsFixed(4)}',
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Palette.blue,
                            side: BorderSide(color: Palette.blue.withValues(alpha: 0.45)),
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
            const SectionHeader('Hardware Telemetry Simulator (Instant Demo)'),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Inject live ESP32 #2 ultrasonic & geofence states into the cloud hub:',
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
                          'light_on': false,
                          'guidance': 'clear',
                          'lat': _centerLat,
                          'lng': _centerLng,
                          'code': 'clear_path',
                          'priority': 1,
                          'message': 'All 3 ultrasonic zones clear — normal daylight walking.',
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
                          'light_on': false,
                          'guidance': 'Obstacle 25cm ahead — veer left or right',
                          'lat': _centerLat,
                          'lng': _centerLng,
                          'code': 'front_obstacle',
                          'priority': 2,
                          'message': 'Front ultrasonic cone detected obstacle at 25 cm.',
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
                            'light_on': true,
                            'guidance': 'Immediate left contact (3cm) — step right! Night LED ON',
                            'lat': _centerLat,
                            'lng': _centerLng,
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
                        onTap: () => _runSimulation('Simulate Geofence Breach', {
                          'left_cm': 95,
                          'front_cm': 130,
                          'right_cm': 110,
                          'ldr_raw': 490,
                          'light_on': false,
                          'guidance': 'Safe-Zone perimeter breached — caregiver alerted',
                          'lat': _centerLat + 0.015,
                          'lng': _centerLng + 0.015,
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
                final msg = (ev['message'] as String?) ?? 'Stick telemetry event';
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
        color: emphasized ? Palette.surfaceHi : Palette.bg.withValues(alpha: 0.55),
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
