import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/emergency_qr_card.dart';
import '../widgets/map_gesture_layer.dart';
import '../widgets/map_tile_image.dart';
import 'video_call_screen.dart';

/// Emergency SOS screen matching website `SOSPage.tsx` & `SOSFab.tsx`.
/// - Tap 3 times within 5 seconds:
///   1. Sends SMS, Email, and WhatsApp with Live GPS + Agora Video Call Link
///   2. Redirects to this Emergency SOS page (`/sos`)
///   3. Turns the SOS button GREEN (`✅ I'M SAFE`)
/// - Tap the GREEN button:
///   1. Sends the "I am Safe" alert via SMS, Email, and WhatsApp
///   2. Resets the SOS button back to RED
class SosActiveScreen extends ConsumerStatefulWidget {
  const SosActiveScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SosActiveScreen> createState() => _SosActiveScreenState();
}

class _SosActiveScreenState extends ConsumerState<SosActiveScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  Timer? _clock;
  Duration _elapsed = Duration.zero;
  String _selectedPoiCategory = 'all';
  double? _sosMapCenterLat;
  double? _sosMapCenterLng;
  int _sosMapZoom = 13;
  bool _loadingNearbyFacilities = false;
  String? _nearbyLocationKey;
  List<CareFacility> _nearbyFacilities = const [];

  static const double _sosSize = 172;

  static const _nationalNumbers = <({
    IconData icon,
    String number,
    String label,
    Color color,
  })>[
    (
      icon: Icons.local_hospital_rounded,
      number: '112',
      label: 'Ambulance',
      color: Palette.red
    ),
    (
      icon: Icons.local_police_rounded,
      number: '100',
      label: 'Police',
      color: Palette.blue
    ),
    (
      icon: Icons.local_fire_department_rounded,
      number: '101',
      label: 'Fire',
      color: Palette.orange
    ),
    (
      icon: Icons.shield_rounded,
      number: '1091',
      label: 'Women',
      color: Palette.purple
    ),
    (
      icon: Icons.emergency_rounded,
      number: '108',
      label: 'Disaster',
      color: Palette.teal
    ),
  ];

  static const _poiFilters = <({String id, String label})>[
    (id: 'all', label: 'All nearby'),
    (id: 'hospital', label: 'Hospitals & clinics'),
    (id: 'emergency', label: 'Emergency care'),
  ];

  @override
  void initState() {
    super.initState();
    _syncElapsed();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _syncElapsed();
    });
  }

  void _syncElapsed() {
    final ev = ref.read(sosProvider).event;
    if (ev == null) {
      if (_elapsed != Duration.zero) {
        setState(() => _elapsed = Duration.zero);
      }
      return;
    }
    final diff = DateTime.now().difference(ev.time);
    setState(() => _elapsed = diff.isNegative ? Duration.zero : diff);
  }

  Future<void> _loadNearbyFacilities(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _loadingNearbyFacilities = true);
    try {
      final facilities = await ref
          .read(apiProvider)
          .nearbyFacilities(lat, lng, radius: 5000)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      setState(() {
        _nearbyFacilities = facilities.take(8).toList();
        _loadingNearbyFacilities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nearbyFacilities = const [];
        _loadingNearbyFacilities = false;
      });
    }
  }

  bool _isEmergencyFacility(CareFacility facility) =>
      facility.emergency ||
      facility.type.toLowerCase().contains('emergency') ||
      facility.name.toLowerCase().contains('emergency');

  List<CareFacility> _filteredFacilities() {
    if (_selectedPoiCategory == 'emergency') {
      return _nearbyFacilities.where(_isEmergencyFacility).toList();
    }
    if (_selectedPoiCategory == 'hospital') {
      return _nearbyFacilities
          .where((facility) => !_isEmergencyFacility(facility))
          .toList();
    }
    return _nearbyFacilities;
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  String _cleanDigits(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '91$digits';
    return digits;
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number.replaceAll(' ', ''));
    if (!await launchUrl(uri)) {
      if (mounted)
        showSnack(context, 'Could not launch dialer for $number', error: true);
    }
  }

  Future<void> _openWhatsAppWithSos(
      SosContactInfo contact, double lat, double lng) async {
    final msg = ref.read(sosProvider.notifier).formatSosMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    final encoded = Uri.encodeComponent(msg);
    final digits = _cleanDigits(contact.phone);
    if (digits.isEmpty) {
      if (mounted)
        showSnack(context, 'Add a phone number for this contact first.');
      return;
    }
    final uri = Uri.parse('https://wa.me/$digits?text=$encoded');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open WhatsApp.', error: true);
    }
  }

  Future<void> _openSmsWithSos(
      SosContactInfo contact, double lat, double lng) async {
    final msg = ref.read(sosProvider.notifier).formatSosMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    final cleanPhone = contact.phone.replaceAll(' ', '');
    if (cleanPhone.trim().isEmpty) {
      if (mounted)
        showSnack(context, 'Add a phone number for this contact first.');
      return;
    }
    final uri = Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(msg)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open SMS app.', error: true);
    }
  }

  Future<void> _openEmailWithSos(
      SosContactInfo contact, double lat, double lng) async {
    if (contact.email.trim().isEmpty) {
      if (mounted)
        showSnack(context, 'Add an email address for this contact first.');
      return;
    }
    final msg = ref.read(sosProvider.notifier).formatSosMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    final subject = Uri.encodeComponent(
        '🚨 EMERGENCY SOS Alert — JeevanCare (Agora Video Call Link Inside)');
    final body = Uri.encodeComponent(msg);
    final uri =
        Uri.parse('mailto:${contact.email}?subject=$subject&body=$body');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open Email app.', error: true);
    }
  }

  Future<void> _openWhatsAppWithSafe(
      SosContactInfo contact, double lat, double lng) async {
    final msg = ref.read(sosProvider.notifier).formatSafeMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    final encoded = Uri.encodeComponent(msg);
    final digits = _cleanDigits(contact.phone);
    final uri = Uri.parse('https://wa.me/$digits?text=$encoded');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open WhatsApp.', error: true);
    }
  }

  Future<void> _openSmsWithSafe(
      SosContactInfo contact, double lat, double lng) async {
    final msg = ref.read(sosProvider.notifier).formatSafeMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    final cleanPhone = contact.phone.replaceAll(' ', '');
    final uri = Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(msg)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open SMS app.', error: true);
    }
  }

  Future<void> _openMaps(double lat, double lng) async {
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted)
        showSnack(context, 'Could not open Google Maps.', error: true);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not open link.', error: true);
    }
  }

  void _onHeroButtonTap() {
    final sos = ref.read(sosProvider);
    HapticFeedback.heavyImpact();
    if (sos.active) {
      if (!sos.resolving) {
        _markSafeAndCancel();
      }
      return;
    }
    if (sos.sending) return;
    ref.read(sosProvider.notifier).registerTap();
  }

  Future<void> _markSafeAndCancel() async {
    final sos = ref.read(sosProvider);
    if (sos.resolving) return;
    unawaited(HapticFeedback.heavyImpact());
    await ref.read(sosProvider.notifier).resolve();
    if (mounted && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openEditContactDialog(SosContactInfo current) async {
    final nameCtrl = TextEditingController(text: current.name);
    final relCtrl = TextEditingController(text: current.relationship);
    final phoneCtrl = TextEditingController(text: current.phone);
    final emailCtrl = TextEditingController(text: current.email);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('✏️ Edit Emergency Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: relCtrl,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.people_alt_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile / WhatsApp Number (+91)',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Contact'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final rel = relCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final email = emailCtrl.text.trim();
    nameCtrl.dispose();
    relCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();

    if (saved == true && mounted) {
      await ref.read(sosProvider.notifier).updatePrimaryContact(
            name: name.isEmpty ? current.name : name,
            relationship: rel.isEmpty ? current.relationship : rel,
            phone: phone.isEmpty ? current.phone : phone,
            email: email.isEmpty ? current.email : email,
          );
      if (mounted) {
        showSnack(context,
            'Emergency contact updated for SOS SMS, Email & WhatsApp!');
      }
    }
  }

  void _openInAppAgoraCall(String roomId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoCallScreen(
          channelId: roomId.isNotEmpty ? roomId : 'sos-room-108',
          title: 'SOS Emergency Video Call',
        ),
      ),
    );
  }

  String _sosCaption(SosState sos) {
    if (sos.active) {
      return sos.resolving ? 'SENDING SAFE…' : 'TAP TO SEND SAFE';
    }
    if (sos.sending) return 'ALERTING…';
    if (sos.tapCount == 0) return 'PRESS 3X';
    return '${sos.remainingTaps} MORE';
  }

  Widget _sosHero(SosState sos) {
    const box = _sosSize + 72;
    final isGreen = sos.active;
    final primaryColor = isGreen ? const Color(0xFF10B981) : Palette.red;
    final darkColor = isGreen ? const Color(0xFF059669) : Palette.redDark;

    return Center(
      child: Column(
        children: [
          SizedBox(
            width: box,
            height: box,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Two soft concentric pulse rings (Red when idle, Emerald Green when active)
                for (final phase in const [0.0, 0.5])
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) {
                      final t = (_pulse.value + phase) % 1.0;
                      final d = _sosSize + 72 * t;
                      return Container(
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryColor.withValues(alpha: 0.14 * (1 - t)),
                        ),
                      );
                    },
                  ),
                GestureDetector(
                  onTap: _onHeroButtonTap,
                  onLongPress: () {
                    if (!sos.active && !sos.sending) {
                      HapticFeedback.heavyImpact();
                      ref.read(sosProvider.notifier).trigger();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: _sosSize,
                    height: _sosSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primaryColor, darkColor],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.38),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isGreen) ...[
                          const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "I'M SAFE",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              height: 1.05,
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              height: 1.05,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _sosCaption(sos),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3-Tap Progress Indicator (Matches website SOSPage.tsx & SOSFab.tsx)
          if (!sos.active && sos.tapCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Palette.redLight,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Palette.red.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < sos.tapCount
                            ? Palette.red
                            : Palette.red.withValues(alpha: 0.25),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap ${sos.remainingTaps} more time${sos.remainingTaps > 1 ? 's' : ''} within 5s to send SOS!',
                    style: const TextStyle(
                      color: Palette.red,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (sos.active) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.45)),
              ),
              child: const Text(
                '🟢 SOS Active — Tap the Green button above to send "I\'m Safe" alert',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF047857),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activePill(String roomId) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.tint(Palette.red),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Palette.red, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                'SOS ACTIVE · ${_fmtDuration(_elapsed)}',
                style: const TextStyle(
                  color: Palette.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.tint(Palette.teal),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_rounded, size: 14, color: Palette.teal),
              const SizedBox(width: 5),
              Text(
                'AGORA ROOM: $roomId',
                style: const TextStyle(
                  color: Palette.teal,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Website-parity Automatic Delivery Summary + Safe & Agora Action Bar
  /// (Matches `SOSPage.tsx` lines 354-418)
  Widget _buildActiveDispatchSummary(SosState sos, double lat, double lng) {
    final store = ref.read(storeProvider);
    final uid = ref.read(authProvider).session?.userId ?? '';
    final roomId = sos.roomId;
    final videoLink =
        sos.videoLink.isNotEmpty ? sos.videoLink : Config.videoCallUrl(roomId);
    final mapsLink = sos.mapsLink;
    final summaryLink = uid.isEmpty ? '' : Config.emergencySummaryUrl(uid);

    return GlassCard(
      color: const Color(0xFFFEF2F2),
      borderColor: Palette.red.withValues(alpha: 0.28),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Primary Green Safe Button + Join Agora Video Call Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: sos.resolving ? null : _markSafeAndCancel,
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
              sos.resolving
                  ? 'Sending Safe Alert via SMS, Email & WhatsApp…'
                  : "✅ I'm Safe — Send Safe Alert & Cancel SOS",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () => _openInAppAgoraCall(roomId),
            icon: const Icon(Icons.videocam_rounded, size: 20),
            label: Text(
              '🎥 Join Agora Video Call ($roomId)',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(height: 14),

          // Automatic Delivery Status Box (Matches SOSPage.tsx `statusMessage` box)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sos.statusMessage ??
                            '✅ Emergency alerts submitted automatically — WhatsApp accepted | SOS SMS accepted | Email sent',
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                // 1. Blood Group row
                if (store.bloodGroup.toLowerCase() != 'not specified')
                  Row(
                    children: [
                      const Icon(Icons.bloodtype_rounded,
                          size: 16, color: Palette.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Blood Group: ${store.bloodGroup} (Patient: ${store.patientName})',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                // 2. Live GPS Location row
                InkWell(
                  onTap: mapsLink.isEmpty ? null : () => _openMaps(lat, lng),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 15, color: Palette.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Live Location: ${mapsLink.isEmpty ? 'GPS location unavailable' : mapsLink}',
                          style: TextStyle(
                            color: mapsLink.isEmpty
                                ? Palette.textDim
                                : Palette.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration: mapsLink.isEmpty
                                ? TextDecoration.none
                                : TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // 3. Medical Details & Summary Link row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medical_information_rounded,
                        size: 15, color: Palette.purple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (store.medicalDetailsSummary.isNotEmpty)
                            Text(
                              'Medical Details: ${store.medicalDetailsSummary}',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 2),
                          InkWell(
                            onTap: summaryLink.isEmpty
                                ? null
                                : () => _openUrl(summaryLink),
                            child: Text(
                              summaryLink.isEmpty
                                  ? 'Medical Summary: save your profile to create a QR link'
                                  : 'Medical Summary: $summaryLink',
                              style: const TextStyle(
                                color: Palette.purple,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 4. Agora Video Call Link row
                InkWell(
                  onTap: () => _openUrl(videoLink),
                  child: Row(
                    children: [
                      const Icon(Icons.videocam_rounded,
                          size: 15, color: Palette.teal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Agora Video Call Link: $videoLink',
                          style: const TextStyle(
                            color: Palette.teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Safe Alert Resolved Banner (Shown after pressing the Green `I'M SAFE` button)
  Widget _buildSafeResolvedBanner(SosState sos, double lat, double lng) {
    final primaryContact = sos.notifiedContacts.isNotEmpty
        ? sos.notifiedContacts.first
        : const SosContactInfo(
            name: '',
            relationship: '',
            phone: '',
            email: '',
          );

    return GlassCard(
      color: const Color(0xFFECFDF5),
      borderColor: const Color(0xFF10B981).withValues(alpha: 0.45),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF059669), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SAFE STATUS UPDATED',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sos.safeResolvedBanner ??
                          (primaryContact.phone.isEmpty &&
                                  primaryContact.email.isEmpty
                              ? 'You marked yourself safe. Add emergency contacts in Profile to share future alerts.'
                              : '✅ Safe status sent to ${primaryContact.name.isEmpty ? primaryContact.phone : primaryContact.name}.'),
                      style: const TextStyle(
                        color: Color(0xFF047857),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF047857),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: primaryContact.phone.trim().isEmpty
                    ? null
                    : () => _openWhatsAppWithSafe(primaryContact, lat, lng),
                icon: const Icon(Icons.chat_rounded,
                    size: 15, color: Color(0xFF059669)),
                label: const Text(
                  '💬 Send Safe on WhatsApp',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Palette.blue,
                  side: BorderSide(color: Palette.blue.withValues(alpha: 0.4)),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: primaryContact.phone.trim().isEmpty
                    ? null
                    : () => _openSmsWithSafe(primaryContact, lat, lng),
                icon: const Icon(Icons.sms_rounded,
                    size: 15, color: Palette.blue),
                label: const Text(
                  '📱 Send Safe SMS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dedicated Agora Emergency Video Call Link Card (Shows Room ID + Link + Copy + Join)
  Widget _buildAgoraVideoLinkCard(SosState sos) {
    final roomId = sos.roomId;
    final videoLink =
        sos.videoLink.isNotEmpty ? sos.videoLink : Config.videoCallUrl(roomId);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: Palette.teal.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Palette.tint(Palette.teal),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.videocam_rounded,
                    color: Palette.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Agora Emergency Video Call Link',
                      style: TextStyle(
                        color: Palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Included automatically in SOS SMS, Email & WhatsApp (Room: $roomId)',
                      style: const TextStyle(
                        color: Palette.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.surfaceHi,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Palette.outline),
            ),
            child: SelectableText(
              videoLink,
              style: const TextStyle(
                color: Palette.teal,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                fontFeatures: kTabular,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => _openInAppAgoraCall(roomId),
                icon: const Icon(Icons.videocam_rounded, size: 16),
                label: const Text(
                  'Join Video Call',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: videoLink));
                  if (mounted) {
                    showSnack(
                        context, 'Agora Video Call Link copied to clipboard!');
                  }
                },
                icon: const Icon(Icons.copy_rounded,
                    size: 15, color: Palette.teal),
                label: const Text(
                  'Copy Agora Link',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => _openUrl(videoLink),
                icon: const Icon(Icons.open_in_new_rounded,
                    size: 15, color: Palette.blue),
                label: const Text(
                  'Open Web Room',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Website-parity "Alert Sent To / Share Alert Manually" Card
  /// Shows to whom the SOS message (with Agora Video Call link) was sent + 1-tap WhatsApp, SMS, Email & Call buttons.
  Widget _buildNotifiedContactsCard(SosState sos, double lat, double lng) {
    final contacts = sos.notifiedContacts;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📨 Alert Sent To (Emergency Contacts)',
                      style: TextStyle(
                        color: Palette.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Recipients of SMS, Email & WhatsApp with Live GPS + Agora Video Call Link',
                      style: TextStyle(color: Palette.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (contacts.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openEditContactDialog(contacts.first),
                  icon: const Icon(Icons.edit_rounded, size: 15),
                  label: const Text('Edit',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < contacts.length; i++) ...[
            if (i > 0) const Divider(height: 20),
            _buildSingleContactRecipientRow(contacts[i], sos, lat, lng),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleContactRecipientRow(
    SosContactInfo c,
    SosState sos,
    double lat,
    double lng,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surfaceHi,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.tint(Palette.purple),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : 'F',
                  style: const TextStyle(
                    color: Palette.purple,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
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
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Palette.tint(Palette.purple),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c.relationship,
                            style: const TextStyle(
                              color: Palette.purple,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (c.phone.trim().isNotEmpty) '📱 ${c.phone}',
                        if (c.email.trim().isNotEmpty) '✉️ ${c.email}',
                      ].join('  •  '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Palette.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: kTabular,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Delivery Channel Status Badges
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _statusChip(
                label: sos.active
                    ? '✅ WhatsApp Dispatched'
                    : (sos.safeResolvedBanner != null
                        ? '✅ Safe WhatsApp Sent'
                        : '💬 WhatsApp Ready'),
                color: const Color(0xFF059669),
              ),
              _statusChip(
                label: sos.active
                    ? '✅ SMS Dispatched'
                    : (sos.safeResolvedBanner != null
                        ? '✅ Safe SMS Sent'
                        : '📱 SMS Ready'),
                color: Palette.blue,
              ),
              _statusChip(
                label: sos.active
                    ? '✅ Email Dispatched'
                    : (sos.safeResolvedBanner != null
                        ? '✅ Safe Email Sent'
                        : '📧 Email Ready'),
                color: Palette.purple,
              ),
              _statusChip(
                label: '🎥 Agora Video Link Attached',
                color: Palette.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1-Tap Manual / Direct Share Buttons (Matches SOSPage.tsx: WhatsApp, SMS, Email, Call)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: c.phone.trim().isEmpty
                    ? null
                    : () => _openWhatsAppWithSos(c, lat, lng),
                icon: const Icon(Icons.chat_rounded, size: 15),
                label: const Text(
                  '💬 WhatsApp',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Palette.blue,
                  side: BorderSide(color: Palette.blue.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: c.phone.trim().isEmpty
                    ? null
                    : () => _openSmsWithSos(c, lat, lng),
                icon: const Icon(Icons.sms_rounded,
                    size: 15, color: Palette.blue),
                label: const Text(
                  '📱 SMS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Palette.purple,
                  side:
                      BorderSide(color: Palette.purple.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: c.email.trim().isEmpty
                    ? null
                    : () => _openEmailWithSos(c, lat, lng),
                icon: const Icon(Icons.email_rounded,
                    size: 15, color: Palette.purple),
                label: const Text(
                  '📧 Email',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Palette.red,
                  side: BorderSide(color: Palette.red.withValues(alpha: 0.45)),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: c.phone.trim().isEmpty ? null : () => _dial(c.phone),
                icon: const Icon(Icons.call_rounded,
                    size: 15, color: Palette.red),
                label: const Text(
                  '📞 Call',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Dispatched SOS Message Payload Card (Shows the exact message text including the Agora Video Call Link)
  Widget _buildSosMessagePreviewCard(double lat, double lng) {
    final msg = ref.read(sosProvider.notifier).formatSosMessage(
        lat: lat == 0 && lng == 0 ? null : lat,
        lng: lat == 0 && lng == 0 ? null : lng);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '📝 Dispatched SOS Message Payload',
                  style: TextStyle(
                    color: Palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: msg));
                  if (mounted) {
                    showSnack(
                        context, 'Full SOS message (with Agora link) copied!');
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                label: const Text('Copy Message',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Palette.surfaceHi,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Palette.outline),
            ),
            child: SelectableText(
              msg,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosLocationMap(double latitude, double longitude) {
    _sosMapCenterLat ??= latitude;
    _sosMapCenterLng ??= longitude;
    final centerLatitude = _sosMapCenterLat!;
    final centerLongitude = _sosMapCenterLng!;
    final zoom = _sosMapZoom;
    const height = 160.0;
    final tileCount = 1 << zoom;
    double worldX(double lon) => (lon + 180) / 360 * tileCount * 256;
    double worldY(double lat) {
      final safeLat = lat.clamp(-85.0511, 85.0511).toDouble();
      final radians = safeLat * math.pi / 180;
      return (1 -
              math.log(math.tan(radians) + 1 / math.cos(radians)) / math.pi) /
          2 *
          tileCount *
          256;
    }

    final centerWorldX = worldX(centerLongitude);
    final centerWorldY = worldY(centerLatitude);
    final centerTileX = (centerWorldX / 256).floor();
    final centerTileY = (centerWorldY / 256).floor();
    final fractionX = centerWorldX - centerTileX * 256;
    final fractionY = centerWorldY - centerTileY * 256;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(builder: (context, constraints) {
          final horizontalRadius = (constraints.maxWidth / 512).ceil();
          final centerX = constraints.maxWidth / 2;
          final centerY = height / 2;
          final tiles = <Widget>[];
          for (var dx = -horizontalRadius; dx <= horizontalRadius; dx++) {
            for (var dy = -1; dy <= 1; dy++) {
              final x =
                  ((centerTileX + dx) % tileCount + tileCount) % tileCount;
              final y = centerTileY + dy;
              if (y < 0 || y >= tileCount) continue;
              final left = centerX + dx * 256 - fractionX;
              final top = centerY + dy * 256 - fractionY;
              tiles.add(Positioned(
                left: left,
                top: top,
                width: 256,
                height: 256,
                child: MapTileImage(zoom: zoom, x: x, y: y),
              ));
            }
          }
          Offset pointOffset(double lat, double lon) => Offset(
                centerX + worldX(lon) - centerWorldX,
                centerY + worldY(lat) - centerWorldY,
              );
          final user = pointOffset(latitude, longitude);
          final visiblePois = _filteredFacilities();
          final poiDots = visiblePois.map((poi) {
            final point = pointOffset(poi.lat, poi.lon);
            if (point.dx < -8 ||
                point.dy < -8 ||
                point.dx > constraints.maxWidth + 8 ||
                point.dy > height + 8) {
              return const SizedBox.shrink();
            }
            return Positioned(
              left: point.dx - 5,
              top: point.dy - 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isEmergencyFacility(poi) ? Palette.red : Palette.teal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3),
                  ],
                ),
              ),
            );
          });
          return MapGestureLayer(
            onPan: (delta) {
              if (delta.distance < 0.5) return;
              final worldSize = tileCount * 256.0;
              final nextX = centerWorldX - delta.dx;
              final nextY = (centerWorldY - delta.dy).clamp(0.0, worldSize);
              setState(() {
                _sosMapCenterLng = nextX / worldSize * 360 - 180;
                final n = math.pi * (1 - 2 * nextY / worldSize);
                _sosMapCenterLat =
                    math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
              });
            },
            onZoom: (delta) => setState(
                () => _sosMapZoom = (_sosMapZoom + delta).clamp(4, 19)),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                const Positioned.fill(
                    child: ColoredBox(color: Color(0xFFE8EDF0))),
                ...tiles,
                ...poiDots,
                Positioned(
                  left: user.dx - 7,
                  top: user.dy - 7,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Palette.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Column(children: [
                    _sosMapControl(
                        Icons.add_rounded,
                        () => setState(() =>
                            _sosMapZoom = (_sosMapZoom + 1).clamp(4, 19))),
                    const SizedBox(height: 4),
                    _sosMapControl(
                        Icons.remove_rounded,
                        () => setState(() =>
                            _sosMapZoom = (_sosMapZoom - 1).clamp(4, 19))),
                  ]),
                ),
                const Positioned(
                  right: 6,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white70),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      child: Text('© OpenStreetMap • TomTom backup',
                          style:
                              TextStyle(fontSize: 9, color: Palette.textDim)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _sosMapControl(IconData icon, VoidCallback onTap) => Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 19, color: Palette.text),
          ),
        ),
      );

  Widget _numberTile(
      ({IconData icon, String number, String label, Color color}) n) {
    return SizedBox(
      width: 96,
      child: GlassCard(
        padding:
            const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.md),
        onTap: () => _dial(n.number),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconChip(n.icon, color: n.color, size: 40),
            const SizedBox(height: Gap.sm),
            Text(
              n.number,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: kTabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              n.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Palette.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 40,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Palette.tint(color),
        fixedSize: Size(size, size),
        minimumSize: Size(size, size),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, color: color, size: size * 0.45),
    );
  }

  Widget _filterChips() {
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        for (final f in _poiFilters)
          ChoiceChip(
            selected: _selectedPoiCategory == f.id,
            showCheckmark: false,
            onSelected: (_) => setState(() => _selectedPoiCategory = f.id),
            label: Text(
              f.label,
              style: TextStyle(
                color:
                    _selectedPoiCategory == f.id ? Palette.red : Palette.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            selectedColor: Palette.redLight,
            backgroundColor: Palette.surface,
            side: BorderSide(
              color: _selectedPoiCategory == f.id
                  ? Palette.red.withValues(alpha: 0.45)
                  : Palette.outline,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sos = ref.watch(sosProvider);
    final store = ref.watch(storeProvider);
    final ev = sos.event;
    final hasLocation = ev?.hasLocation == true;
    final lat = ev?.lat ?? 0.0;
    final lng = ev?.lng ?? 0.0;
    if (hasLocation) {
      final key = '${lat.toStringAsFixed(3)}:${lng.toStringAsFixed(3)}';
      if (_nearbyLocationKey != key) {
        _nearbyLocationKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadNearbyFacilities(lat, lng));
        });
      }
    }
    final filteredPois = _filteredFacilities();

    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, Gap.lg, 20, Gap.xl),
      children: [
        // 1. Title (+ active pill)
        if (sos.active) ...[
          const PageTitle(
            'Emergency SOS Active',
            subtitle:
                'SMS, Email & WhatsApp sent with your Live GPS & Agora Video Call Link',
          ),
          const SizedBox(height: Gap.sm),
          _activePill(sos.roomId),
        ] else
          const PageTitle(
            'Emergency SOS',
            subtitle:
                'Tap 3 times within 5 seconds to send SMS, Email & WhatsApp with Agora Video Link',
          ),
        const SizedBox(height: Gap.lg),

        // 2. Hero SOS (Red) / I'm Safe (Green) Circle Button
        _sosHero(sos),
        const SizedBox(height: Gap.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.my_location_rounded,
                size: 14, color: Palette.textMuted),
            const SizedBox(width: 6),
            Text(
              hasLocation
                  ? 'Live GPS: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}'
                  : 'Live GPS: waiting for a current location',
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: kTabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),

        // 3. Active Emergency Dispatch Summary OR Safe Alert Resolved Banner
        if (sos.active) ...[
          _buildActiveDispatchSummary(sos, lat, lng),
          const SizedBox(height: Gap.lg),
        ] else if (sos.safeResolvedBanner != null) ...[
          _buildSafeResolvedBanner(sos, lat, lng),
          const SizedBox(height: Gap.lg),
        ],

        // 4. Agora Emergency Video Call Link Card (Always visible so user can see/copy/join the Agora link)
        _buildAgoraVideoLinkCard(sos),
        const SizedBox(height: Gap.lg),

        // 5. "Alert Sent To" — Notified Emergency Contacts & 1-Tap WhatsApp / SMS / Email / Call
        _buildNotifiedContactsCard(sos, lat, lng),
        const SizedBox(height: Gap.lg),

        // 6. Dispatched SOS Message Preview (including Agora Video Call Link)
        _buildSosMessagePreviewCard(lat, lng),
        const SizedBox(height: Gap.xl),

        // 7. Call for help (National Helplines)
        const SectionHeader('Quick-Dial Emergency Helplines'),
        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            for (final n in _nationalNumbers) _numberTile(n),
          ],
        ),
        const SizedBox(height: Gap.xl),

        // 8. Medical QR
        EmergencyQrCard(
          compact: true,
          patientName: store.patientName,
          bloodGroup: store.bloodGroup,
          dob: store.dateOfBirth,
          allergies: store.allergies
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          conditions: store.conditions
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          medications: store.medications
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          emergencyContactName: store.contactName,
          emergencyContactRelation: store.contactRelation,
          emergencyContactPhone: store.contactPhone,
          emergencyContacts: store.emergencyContacts,
          showEmergencyContacts: store.showEmergencyContactsOnQr,
        ),
        const SizedBox(height: Gap.xl),

        // 9. Nearby help
        const SectionHeader('Nearby Emergency Help'),
        _filterChips(),
        const SizedBox(height: Gap.md),
        if (hasLocation)
          _buildSosLocationMap(lat, lng)
        else
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: const Text(
              'Nearby services will load when a current GPS location is available. No default location is shown.',
              style: TextStyle(color: Palette.textDim, fontSize: 13),
            ),
          ),
        const SizedBox(height: Gap.md),
        GlassCard(
          padding:
              const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.xs),
          child: Column(
            children: [
              if (_loadingNearbyFacilities)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                )
              else if (!hasLocation || filteredPois.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No nearby hospitals or clinics are available for this location.',
                    style: TextStyle(color: Palette.textDim, fontSize: 13),
                  ),
                )
              else
                for (var i = 0; i < filteredPois.length; i++) ...[
                  if (i > 0) const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.md),
                    child: Row(
                      children: [
                        IconChip(Icons.local_hospital_rounded,
                            color: _isEmergencyFacility(filteredPois[i])
                                ? Palette.red
                                : Palette.teal,
                            size: 40),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                filteredPois[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${((filteredPois[i].distanceMeters ?? 0) / 1000).toStringAsFixed(1)} km · ${filteredPois[i].type}',
                                style: const TextStyle(
                                  color: Palette.textDim,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: kTabular,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (filteredPois[i].phone.isNotEmpty)
                          _circleIconButton(
                            icon: Icons.call_rounded,
                            color: _isEmergencyFacility(filteredPois[i])
                                ? Palette.red
                                : Palette.teal,
                            tooltip: 'Call ${filteredPois[i].phone}',
                            size: 36,
                            onPressed: () => _dial(filteredPois[i].phone),
                          ),
                        const SizedBox(width: Gap.sm),
                        _circleIconButton(
                          icon: Icons.directions_rounded,
                          color: Palette.blue,
                          tooltip: 'Directions',
                          size: 36,
                          onPressed: () => _openMaps(
                              filteredPois[i].lat, filteredPois[i].lon),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: Palette.bg, child: list);
    }
    return Scaffold(
      backgroundColor: Palette.bg,
      appBar: AppBar(),
      body: list,
    );
  }
}
// Jeevan sync: 2026-11-13
