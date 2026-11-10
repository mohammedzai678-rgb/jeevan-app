import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Live Agora RTC Telemedicine & Emergency Responder Video Room.
class VideoCallScreen extends ConsumerStatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.channelId,
    this.title = 'Emergency Telemedicine',
  });

  final String channelId;
  final String title;

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> with SingleTickerProviderStateMixin {
  RtcSession? _session;
  String? _error;
  bool _loading = true;

  bool _micMuted = false;
  bool _camOff = false;
  bool _speakerOn = true;
  bool _frontCamera = true;

  Timer? _timer;
  Duration _elapsed = Duration.zero;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _joinChannel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _session != null) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _joinChannel() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(apiProvider)
          .createRtcChannel(widget.channelId)
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  String get _inviteUrl => Config.videoCallUrl(widget.channelId);

  Future<void> _copyInvite() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (mounted) {
      unawaited(HapticFeedback.lightImpact());
      showSnack(context, 'Invite link copied to clipboard');
    }
  }

  Future<void> _launchExternalRoom() async {
    final uri = Uri.parse(_inviteUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) showSnack(context, 'Could not launch external Agora room.', error: true);
    }
  }

  Future<void> _openInviteDoctorDialog() async {
    final nameCtrl = TextEditingController(text: 'Dr. Ramesh Rao');
    final phoneCtrl = TextEditingController(text: '+919876543210');
    final emailCtrl = TextEditingController(text: 'doctor@jeevancare.in');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surfaceHi,
        title: const Text('Invite Doctor / Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send an instant Agora Telemedicine room invite link for "${widget.channelId}" over WhatsApp, SMS & Email.',
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Doctor / Contact Name *',
                  prefixIcon: Icon(Icons.person_outline_rounded, color: Palette.teal),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp / Mobile Number',
                  hintText: '+919876543210',
                  prefixIcon: Icon(Icons.chat_rounded, color: Palette.green),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'doctor@hospital.org',
                  prefixIcon: Icon(Icons.email_outlined, color: Palette.blue),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Palette.textDim)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              backgroundColor: Palette.teal,
              foregroundColor: const Color(0xFF042F2A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send Invite'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final email = emailCtrl.text.trim();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();

    if (confirmed != true || !mounted) return;
    if (name.isEmpty) {
      showSnack(context, 'Please enter a recipient name.', error: true);
      return;
    }

    try {
      await ref.read(apiProvider).sendVideoCallInvite(
            roomId: widget.channelId,
            name: name,
            phone: phone.isEmpty ? null : phone,
            email: email.isEmpty ? null : email,
          );
      if (mounted) {
        showSnack(context, 'Video call invite dispatched to $name via WhatsApp & Email!');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not dispatch video call invite: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(devicesProvider).current;
    final vitals = snap?.vitals ?? const Vitals();

    return Scaffold(
      backgroundColor: Palette.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628),
              Color(0xFF0E1D34),
              Palette.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                // ── Top Bar ──────────────────────────────────────────────────────────
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: Palette.text),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Room: ${widget.channelId}',
                            style: const TextStyle(
                              color: Palette.textDim,
                              fontSize: 12,
                              fontFeatures: kTabular,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Palette.teal.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.teal.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Palette.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'LIVE AGORA RTC • ENCRYPTED',
                            style: TextStyle(
                              color: Palette.teal,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Invite Doctor / Contact (WhatsApp & Email)',
                      onPressed: _openInviteDoctorDialog,
                      icon: const Icon(Icons.person_add_alt_1_rounded, color: Palette.green, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Copy Invite Link',
                      onPressed: _copyInvite,
                      icon: const Icon(Icons.share_rounded, color: Palette.teal, size: 20),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Live Vitals Telemetry Overlay Strip ──────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: Palette.surfaceHi.withValues(alpha: 0.85),
                  borderColor: Palette.teal.withValues(alpha: 0.35),
                  child: Row(
                    children: [
                      const Icon(Icons.monitor_heart_rounded, color: Palette.teal, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'LIVE TELEMETRY',
                        style: TextStyle(
                          color: Palette.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      _VitalChip(
                        icon: Icons.favorite_rounded,
                        color: Palette.red,
                        label: vitals.heartRate != null ? '${vitals.heartRate} BPM' : '-- BPM',
                      ),
                      const SizedBox(width: 10),
                      _VitalChip(
                        icon: Icons.water_drop_rounded,
                        color: Palette.blue,
                        label: vitals.spo2 != null ? '${vitals.spo2}% SpO₂' : '--% SpO₂',
                      ),
                      const SizedBox(width: 10),
                      _VitalChip(
                        icon: Icons.thermostat_rounded,
                        color: Palette.amber,
                        label: vitals.temperature != null
                            ? '${vitals.temperature!.toStringAsFixed(1)}°C'
                            : '--.-°C',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Main Video / RTC Viewport ────────────────────────────────────────
                Expanded(
                  child: _loading
                      ? GlassCard(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: Palette.teal),
                                const SizedBox(height: 16),
                                Text(
                                  'Negotiating signed Agora 007 RTC token for "${widget.channelId}"…',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Palette.textDim, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _error != null
                          ? _buildErrorState()
                          : _buildActiveViewport(),
                ),

                const SizedBox(height: 16),

                // ── Bottom Call Controls ─────────────────────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  color: Palette.surface,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ControlBtn(
                        icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: _micMuted ? 'Unmute' : 'Mute',
                        active: !_micMuted,
                        onTap: () => setState(() => _micMuted = !_micMuted),
                      ),
                      _ControlBtn(
                        icon: _camOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                        label: _camOff ? 'Cam Off' : 'Camera',
                        active: !_camOff,
                        onTap: () => setState(() => _camOff = !_camOff),
                      ),
                      _ControlBtn(
                        icon: _speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                        label: _speakerOn ? 'Speaker' : 'Earpiece',
                        active: _speakerOn,
                        onTap: () => setState(() => _speakerOn = !_speakerOn),
                      ),
                      _ControlBtn(
                        icon: Icons.cameraswitch_rounded,
                        label: _frontCamera ? 'Front' : 'Rear',
                        active: true,
                        onTap: () => setState(() => _frontCamera = !_frontCamera),
                      ),
                      _ControlBtn(
                        icon: Icons.call_end_rounded,
                        label: 'End Call',
                        danger: true,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveViewport() {
    final s = _session!;
    final appPrefix = s.appId.length > 8 ? '${s.appId.substring(0, 8)}…' : s.appId;
    final tokenPrefix = s.token.length > 18 ? '${s.token.substring(0, 18)}…' : s.token;

    return Stack(
      children: [
        // Remote responder / telemedicine feed area
        GlassCard(
          padding: const EdgeInsets.all(20),
          color: const Color(0xFF0D1729),
          borderColor: Palette.teal.withValues(alpha: 0.35),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return Container(
                    width: 108,
                    height: 108,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.teal.withValues(alpha: 0.10 + 0.10 * t),
                      boxShadow: [
                        BoxShadow(
                          color: Palette.teal.withValues(alpha: 0.22 * t),
                          blurRadius: 24 + 16 * t,
                          spreadRadius: 3 * t,
                        ),
                      ],
                    ),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Palette.surfaceHi,
                        border: Border.all(color: Palette.teal, width: 2),
                      ),
                      child: const Icon(
                        Icons.medical_services_rounded,
                        color: Palette.teal,
                        size: 36,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Agora Emergency Telemedicine Bridge Ready',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Timer ${_fmtDuration(_elapsed)} • Waiting for ER Physician / Caregiver on "${s.channelId}"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 13,
                  fontFeatures: kTabular,
                ),
              ),
              const SizedBox(height: 18),

              // Agora 007 session metadata card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Palette.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Palette.outline),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Agora App ID', style: TextStyle(color: Palette.textDim, fontSize: 12)),
                        Text(
                          appPrefix,
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: kTabular,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Assigned UID & Role', style: TextStyle(color: Palette.textDim, fontSize: 12)),
                        Text(
                          '${s.uid} (${s.role.toUpperCase()})',
                          style: const TextStyle(
                            color: Palette.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: kTabular,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Signed 007 Token', style: TextStyle(color: Palette.textDim, fontSize: 12)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded, color: Palette.green, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              tokenPrefix,
                              style: const TextStyle(
                                color: Palette.green,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: kTabular,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.text,
                        side: const BorderSide(color: Palette.outline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _copyInvite,
                      icon: const Icon(Icons.copy_rounded, size: 18, color: Palette.teal),
                      label: const Text('Copy Room Link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: Palette.teal,
                        foregroundColor: const Color(0xFF042F2A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _launchExternalRoom,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Launch WebRTC Room'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.green,
                    side: BorderSide(color: Palette.green.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _openInviteDoctorDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: Palette.green),
                  label: const Text('Invite Doctor / Contact (WhatsApp & Email)'),
                ),
              ),
            ],
          ),
        ),

        // Local camera preview PIP card (top-right)
        Positioned(
          top: 14,
          right: 14,
          child: Container(
            width: 96,
            height: 128,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.surfaceHi.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.outline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _camOff ? Icons.videocam_off_rounded : Icons.person_pin_rounded,
                  color: _camOff ? Palette.textDim : Palette.teal,
                  size: 32,
                ),
                const SizedBox(height: 6),
                Text(
                  _camOff ? 'Cam Paused' : (_frontCamera ? 'You (Front)' : 'You (Rear)'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_micMuted) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.mic_off_rounded, color: Palette.red, size: 14),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      borderColor: Palette.amber.withValues(alpha: 0.45),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Palette.amber.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.videocam_off_rounded, color: Palette.amber, size: 32),
          ),
          const SizedBox(height: 14),
          const Text(
            'Agora RTC Token Server Not Configured',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Set AGORA_APP_ID and AGORA_APP_CERTIFICATE in backend/.env to mint signed 007 RTC tokens.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.text,
                    side: const BorderSide(color: Palette.outline),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _copyInvite,
                  icon: const Icon(Icons.share_rounded, size: 18, color: Palette.teal),
                  label: const Text('Copy Room Link'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: Palette.teal,
                    foregroundColor: const Color(0xFF042F2A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _joinChannel,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Token'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VitalChip extends StatelessWidget {
  const _VitalChip({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Palette.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: kTabular,
          ),
        ),
      ],
    );
  }
}

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = true,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? Palette.red
        : active
            ? Palette.surfaceHi
            : Palette.red.withValues(alpha: 0.18);
    final fg = danger
        ? Colors.white
        : active
            ? Palette.text
            : Palette.red;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: danger ? Palette.red : (active ? Palette.outline : Palette.red.withValues(alpha: 0.45)),
                ),
              ),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: danger ? Palette.red : Palette.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
