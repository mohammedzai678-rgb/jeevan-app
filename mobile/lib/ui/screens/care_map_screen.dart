import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'video_call_screen.dart';

/// Nearby Emergency Hospitals, TomTom Live Traffic ETA & Telemedicine Routing.
class CareMapScreen extends ConsumerStatefulWidget {
  const CareMapScreen({super.key});

  @override
  ConsumerState<CareMapScreen> createState() => _CareMapScreenState();
}

class _CareMapScreenState extends ConsumerState<CareMapScreen> {
  static const double _defaultLat = 12.9716;
  static const double _defaultLon = 77.5946;

  double _lat = _defaultLat;
  double _lon = _defaultLon;
  bool _usingFallbackGps = false;

  int _radius = 7000;
  bool _loadingFacilities = true;
  String? _error;
  List<CareFacility> _facilities = const [];

  CareFacility? _selected;
  EmergencyRouteInfo? _route;
  bool _loadingRoute = false;
  String _travelMode = 'driving';

  @override
  void initState() {
    super.initState();
    _initLocationAndLoad();
  }

  Future<void> _initLocationAndLoad() async {
    setState(() {
      _loadingFacilities = true;
      _error = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _usingFallbackGps = true;
      } else {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _lat = last.latitude;
          _lon = last.longitude;
          _usingFallbackGps = false;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        _lat = pos.latitude;
        _lon = pos.longitude;
        _usingFallbackGps = false;
      }
    } catch (_) {
      _usingFallbackGps = true;
    }
    await _loadFacilities();
  }

  Future<void> _loadFacilities() async {
    if (!mounted) return;
    setState(() {
      _loadingFacilities = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiProvider).nearbyFacilities(_lat, _lon, radius: _radius);
      if (!mounted) return;
      setState(() {
        _facilities = list;
        _loadingFacilities = false;
      });
      if (list.isNotEmpty) {
        final keep = _selected != null
            ? list.where((f) => f.id == _selected!.id).firstOrNull
            : null;
        await _selectFacility(keep ?? list.first);
      } else {
        setState(() {
          _selected = null;
          _route = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingFacilities = false;
      });
    }
  }

  Future<void> _selectFacility(CareFacility facility) async {
    setState(() {
      _selected = facility;
      _loadingRoute = true;
    });
    try {
      final route = await ref.read(apiProvider).emergencyRoute(
            originLat: _lat,
            originLon: _lon,
            destLat: facility.lat,
            destLon: facility.lon,
          );
      if (!mounted || _selected?.id != facility.id) return;
      setState(() {
        _route = route;
        _loadingRoute = false;
      });
    } catch (_) {
      if (!mounted || _selected?.id != facility.id) return;
      setState(() => _loadingRoute = false);
    }
  }

  Future<void> _openNavigation(CareFacility f) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${f.lat},${f.lon}&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not launch turn-by-turn navigation.', error: true);
    }
  }

  Future<void> _callHospital(String phone) async {
    final cleaned = phone.trim();
    if (cleaned.isEmpty) {
      showSnack(context, 'No direct phone listed; dialing emergency 108.', error: false);
    }
    final uri = Uri.parse('tel:${cleaned.isEmpty ? '108' : cleaned}');
    if (!await launchUrl(uri)) {
      if (mounted) showSnack(context, 'Could not open phone dialer.', error: true);
    }
  }

  void _openTelemedicine(CareFacility f) {
    final slug = f.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final channelId = 'consult-${slug.isEmpty ? 'er' : (slug.length > 16 ? slug.substring(0, 16) : slug)}';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoCallScreen(
          channelId: channelId,
          title: f.name,
        ),
      ),
    );
  }

  void _handleRadarTap(Offset localPos, Size size) {
    if (_facilities.isEmpty) return;
    final maxDist = _computeMaxRadiusMeters();
    CareFacility? hit;
    double bestDist = 28.0;
    for (final f in _facilities) {
      final pt = _projectPoint(
        lat: f.lat,
        lon: f.lon,
        originLat: _lat,
        originLon: _lon,
        maxDistMeters: maxDist,
        size: size,
      );
      final d = (pt - localPos).distance;
      if (d < bestDist) {
        bestDist = d;
        hit = f;
      }
    }
    if (hit != null) {
      _selectFacility(hit);
    }
  }

  double _computeMaxRadiusMeters() {
    double maxD = _radius.toDouble();
    for (final f in _facilities) {
      final d = (f.distanceMeters ?? 0).toDouble();
      if (d > maxD) maxD = d;
    }
    return maxD * 1.12;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: canPop
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Palette.text),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('🗺️ Emergency Route & TomTom Traffic'),
              actions: [
                IconButton(
                  tooltip: 'Refresh GPS & Hospitals',
                  onPressed: _loadingFacilities ? null : _initLocationAndLoad,
                  icon: const Icon(Icons.my_location_rounded, color: Palette.teal),
                ),
                const SizedBox(width: 6),
              ],
            )
          : null,
      body: RefreshIndicator(
        color: Palette.teal,
        onRefresh: _initLocationAndLoad,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
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
                    child: const Text('🗺️', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Route',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'TomTom Live Traffic ETA & Hospital Routing',
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh GPS & Hospitals',
                    onPressed: _loadingFacilities ? null : _initLocationAndLoad,
                    icon: const Icon(Icons.my_location_rounded, color: Palette.teal),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            // ── Travel Mode Switcher (Vertical Wrap — Zero Horizontal Scroll) ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [
                  (id: 'driving', label: '🚗 Driving'),
                  (id: 'biking', label: '🚲 Two-Wheeler'),
                  (id: 'walking', label: '🚶 Walking'),
                ])
                  ChoiceChip(
                    selected: _travelMode == m.id,
                    showCheckmark: false,
                    selectedColor: Palette.redLight,
                    backgroundColor: Palette.surface,
                    side: BorderSide(
                      color: _travelMode == m.id ? Palette.red : Palette.outline,
                    ),
                    label: Text(
                      m.label,
                      style: TextStyle(
                        color: _travelMode == m.id ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    onSelected: (_) {
                      setState(() => _travelMode = m.id);
                      if (_selected != null) _selectFacility(_selected!);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Location & Radius Selector (Wrap — Never Overflows) ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Palette.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Palette.teal.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _usingFallbackGps ? Icons.location_searching_rounded : Icons.gps_fixed_rounded,
                        color: Palette.teal,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_lat.toStringAsFixed(4)}, ${_lon.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Palette.teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in const [
                      (label: '3 km', meters: 3000),
                      (label: '7 km', meters: 7000),
                      (label: '15 km', meters: 15000),
                    ])
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          r.label,
                          style: TextStyle(
                            color: _radius == r.meters ? Palette.teal : Palette.textDim,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: _radius == r.meters,
                        selectedColor: Palette.teal.withValues(alpha: 0.16),
                        backgroundColor: Palette.surface,
                        side: BorderSide(
                          color: _radius == r.meters ? Palette.teal : Palette.outline,
                        ),
                        onSelected: (sel) {
                          if (!sel || _radius == r.meters) return;
                          setState(() => _radius = r.meters);
                          _loadFacilities();
                        },
                      ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Interactive TomTom Emergency Radar & Route Canvas ───────────────
            GlassCard(
              padding: const EdgeInsets.all(14),
              color: const Color(0xFF0D1729),
              borderColor: Palette.teal.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.radar_rounded, color: Palette.teal, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'TOMTOM EMERGENCY RADAR & LIVE TRAFFIC',
                          style: TextStyle(
                            color: Palette.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Text(
                        '${_facilities.length} found',
                        style: const TextStyle(
                          color: Palette.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 230,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = Size(constraints.maxWidth, 230);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _handleRadarTap(d.localPosition, size),
                          child: CustomPaint(
                            size: size,
                            painter: _TomTomRadarPainter(
                              originLat: _lat,
                              originLon: _lon,
                              maxDistMeters: _computeMaxRadiusMeters(),
                              facilities: _facilities,
                              selected: _selected,
                              route: _route,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _LegendDot(color: Palette.red, label: '24×7 Emergency'),
                      _LegendDot(color: Palette.teal, label: 'Hospital / Clinic'),
                      _LegendDot(color: Palette.blue, label: 'TomTom Route'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Selected Facility Live Traffic Route Card ────────────────────────
            if (_selected != null) ...[
              _buildSelectedRouteCard(_selected!),
              const SizedBox(height: 18),
            ],

            // ── Nearby Facilities List ───────────────────────────────────────────
            SectionHeader(
              'Nearby Medical Facilities',
              action: _loadingFacilities
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                    )
                  : null,
            ),

            if (_error != null)
              EmptyState(
                Icons.cloud_off_rounded,
                'Could Not Load Nearby Hospitals',
                _error!,
                action: FilledButton.icon(
                  onPressed: _loadFacilities,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              )
            else if (!_loadingFacilities && _facilities.isEmpty)
              EmptyState(
                Icons.local_hospital_outlined,
                'No Facilities in ${(_radius / 1000).round()} km Radius',
                'Try expanding the search radius to 15 km.',
                action: FilledButton.icon(
                  onPressed: () {
                    setState(() => _radius = 15000);
                    _loadFacilities();
                  },
                  icon: const Icon(Icons.zoom_out_map_rounded),
                  label: const Text('Search 15 km Radius'),
                ),
              )
            else
              for (final f in _facilities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildFacilityTile(f),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedRouteCard(CareFacility f) {
    final r = _route;
    final distKm = ((r?.distanceMeters ?? f.distanceMeters ?? 0) / 1000.0).toStringAsFixed(1);
    final etaMin = r != null ? math.max(1, (r.travelTimeSeconds / 60).round()) : null;
    final delaySec = r?.trafficDelaySeconds ?? 0;
    final delayMin = (delaySec / 60).round();

    final Color delayColor = delayMin >= 5
        ? Palette.red
        : delayMin >= 1
            ? Palette.amber
            : Palette.green;
    final String delayLabel = delayMin >= 1 ? '+$delayMin min traffic' : 'Clear traffic';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      color: Palette.surfaceHi,
      borderColor: Palette.teal.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (f.emergency ? Palette.red : Palette.teal).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  f.emergency ? Icons.emergency_rounded : Icons.local_hospital_rounded,
                  color: f.emergency ? Palette.red : Palette.teal,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.name,
                      style: const TextStyle(
                        color: Palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      f.address.isNotEmpty
                          ? f.address
                          : '${f.lat.toStringAsFixed(4)}, ${f.lon.toStringAsFixed(4)}',
                      style: const TextStyle(color: Palette.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Palette.blue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Palette.blue.withValues(alpha: 0.4)),
                ),
                child: Text(
                  (r?.source ?? f.source).toUpperCase(),
                  style: const TextStyle(
                    color: Palette.blue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Live ETA & Traffic metrics bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.outline),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_rounded, color: Palette.teal, size: 18),
                const SizedBox(width: 8),
                Text(
                  '$distKm km',
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFeatures: kTabular,
                  ),
                ),
                const SizedBox(width: 14),
                const Icon(Icons.schedule_rounded, color: Palette.blue, size: 18),
                const SizedBox(width: 6),
                if (_loadingRoute)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                  )
                else
                  Text(
                    etaMin != null ? '$etaMin min ETA' : '-- min ETA',
                    style: const TextStyle(
                      color: Palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFeatures: kTabular,
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: delayColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: delayColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    delayLabel,
                    style: TextStyle(
                      color: delayColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action buttons: Turn-by-Turn Navigation + Call Hospital
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: Palette.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _openNavigation(f),
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Start Turn-by-Turn'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.text,
                  side: const BorderSide(color: Palette.outline),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _callHospital(f.phone),
                icon: const Icon(Icons.call_rounded, size: 18, color: Palette.green),
                label: Text(f.phone.isNotEmpty ? 'Call' : '108'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Agora Telemedicine Consult button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.blue,
                side: BorderSide(color: Palette.blue.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _openTelemedicine(f),
              icon: const Icon(Icons.videocam_rounded, size: 18, color: Palette.blue),
              label: const Text('Start Agora Telemedicine Consult'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityTile(CareFacility f) {
    final isSelected = _selected?.id == f.id;
    final distKm = f.distanceMeters != null ? '${(f.distanceMeters! / 1000).toStringAsFixed(1)} km' : '';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      color: isSelected ? Palette.surfaceHi : Palette.surface,
      borderColor: isSelected ? Palette.teal : Palette.outline,
      onTap: () => _selectFacility(f),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (f.emergency ? Palette.red : Palette.teal).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              f.emergency ? Icons.local_hospital_rounded : Icons.medical_services_outlined,
              color: f.emergency ? Palette.red : Palette.teal,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (f.emergency)
                      const Text(
                        'ER / TRAUMA',
                        style: TextStyle(
                          color: Palette.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    if (f.open24x7)
                      const Text(
                        '24×7 OPEN',
                        style: TextStyle(
                          color: Palette.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    if (f.address.isNotEmpty)
                      Text(
                        f.address,
                        style: const TextStyle(color: Palette.textDim, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (distKm.isNotEmpty)
                Text(
                  distKm,
                  style: const TextStyle(
                    color: Palette.teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: kTabular,
                  ),
                ),
              const SizedBox(height: 4),
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.chevron_right_rounded,
                color: isSelected ? Palette.teal : Palette.textDim,
                size: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Offset _projectPoint({
  required double lat,
  required double lon,
  required double originLat,
  required double originLon,
  required double maxDistMeters,
  required Size size,
}) {
  final center = Offset(size.width / 2, size.height / 2);
  final radiusPx = math.min(size.width, size.height) * 0.44;
  final cosLat = math.cos(originLat * math.pi / 180.0);
  final dxMeters = (lon - originLon) * 111320.0 * cosLat;
  final dyMeters = -(lat - originLat) * 111320.0;
  final scale = radiusPx / (maxDistMeters <= 0 ? 1.0 : maxDistMeters);
  final px = (center.dx + dxMeters * scale).clamp(12.0, size.width - 12.0);
  final py = (center.dy + dyMeters * scale).clamp(12.0, size.height - 12.0);
  return Offset(px, py);
}

class _TomTomRadarPainter extends CustomPainter {
  _TomTomRadarPainter({
    required this.originLat,
    required this.originLon,
    required this.maxDistMeters,
    required this.facilities,
    required this.selected,
    required this.route,
  });

  final double originLat;
  final double originLon;
  final double maxDistMeters;
  final List<CareFacility> facilities;
  final CareFacility? selected;
  final EmergencyRouteInfo? route;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.44;

    // Radar rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Palette.outline.withValues(alpha: 0.75);

    for (final frac in const [0.33, 0.66, 1.0]) {
      canvas.drawCircle(center, maxR * frac, ringPaint);
    }

    // Crosshairs
    final axisPaint = Paint()
      ..strokeWidth = 0.8
      ..color = Palette.outline.withValues(alpha: 0.5);
    canvas.drawLine(Offset(center.dx - maxR, center.dy), Offset(center.dx + maxR, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxR), Offset(center.dx, center.dy + maxR), axisPaint);

    // Active route polyline
    if (selected != null) {
      final routePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.blue;

      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7.0
        ..strokeCap = StrokeCap.round
        ..color = Palette.blue.withValues(alpha: 0.22);

      final path = Path();
      final pts = route?.points ?? const [];
      if (pts.length >= 2) {
        for (var i = 0; i < pts.length; i++) {
          final p = _projectPoint(
            lat: pts[i].lat,
            lon: pts[i].lon,
            originLat: originLat,
            originLon: originLon,
            maxDistMeters: maxDistMeters,
            size: size,
          );
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
      } else {
        final destPt = _projectPoint(
          lat: selected!.lat,
          lon: selected!.lon,
          originLat: originLat,
          originLon: originLon,
          maxDistMeters: maxDistMeters,
          size: size,
        );
        path
          ..moveTo(center.dx, center.dy)
          ..lineTo(destPt.dx, destPt.dy);
      }
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, routePaint);
    }

    // Facility pins
    for (final f in facilities) {
      final isSel = selected?.id == f.id;
      final pt = _projectPoint(
        lat: f.lat,
        lon: f.lon,
        originLat: originLat,
        originLon: originLon,
        maxDistMeters: maxDistMeters,
        size: size,
      );
      final pinColor = f.emergency ? Palette.red : Palette.teal;
      if (isSel) {
        canvas.drawCircle(
          pt,
          13,
          Paint()..color = pinColor.withValues(alpha: 0.28),
        );
        canvas.drawCircle(
          pt,
          9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = Colors.white,
        );
      }
      canvas.drawCircle(pt, isSel ? 7.0 : 5.5, Paint()..color = pinColor);
    }

    // User location marker at center
    canvas.drawCircle(center, 11, Paint()..color = Palette.teal.withValues(alpha: 0.25));
    canvas.drawCircle(center, 6, Paint()..color = Colors.white);
    canvas.drawCircle(center, 4, Paint()..color = Palette.teal);
  }

  @override
  bool shouldRepaint(covariant _TomTomRadarPainter oldDelegate) =>
      oldDelegate.originLat != originLat ||
      oldDelegate.originLon != originLon ||
      oldDelegate.maxDistMeters != maxDistMeters ||
      oldDelegate.facilities != facilities ||
      oldDelegate.selected != selected ||
      oldDelegate.route != route;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: Palette.textDim, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
