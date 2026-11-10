import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Always-visible Emergency QR.
///
/// * `hero: true`  → crimson gradient showpiece (Dashboard).
/// * default / `compact: true` → quiet white card (SOS, Health Vault, Profile).
///
/// The QR is a real, scannable code that encodes `<webBaseUrl>/emergency/<userId>`
/// (same URL as the website's EmergencyQRWidget). Tapping opens the
/// first-responder medical summary.
class EmergencyQrCard extends ConsumerWidget {
  const EmergencyQrCard({
    super.key,
    this.patientName = 'zaid',
    this.bloodGroup = 'A+',
    this.dob = '14 May 1999',
    this.allergies = const ['Penicillin', 'Sulfa drugs'],
    this.conditions = const ['Mild asthma'],
    this.medications = const ['Salbutamol inhaler (PRN)', 'Cetirizine 10 mg'],
    this.emergencyContactName = 'Family contact',
    this.emergencyContactRelation = 'Parent / Guardian',
    this.emergencyContactPhone = '+91 98765 43210',
    this.compact = false,
    this.hero = false,
  });

  final String patientName;
  final String bloodGroup;
  final String dob;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;
  final String emergencyContactName;
  final String emergencyContactRelation;
  final String emergencyContactPhone;
  final bool compact;
  final bool hero;

  void _open(BuildContext context, String url) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmergencySummaryScreen(
          patientName: patientName,
          bloodGroup: bloodGroup,
          dob: dob,
          allergies: allergies,
          conditions: conditions,
          medications: medications,
          emergencyContactName: emergencyContactName,
          emergencyContactRelation: emergencyContactRelation,
          emergencyContactPhone: emergencyContactPhone,
          summaryUrl: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(sessionProvider).valueOrNull?.userId ?? 'zaid-001';
    final url = '${Config.webBaseUrl}/emergency/$uid';
    return hero ? _hero(context, url) : _light(context, url);
  }

  // ── Dashboard showpiece ──────────────────────────────────────────────────
  Widget _hero(BuildContext context, String url) {
    return GestureDetector(
      onTap: () => _open(context, url),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0505D), Palette.redDark],
          ),
          boxShadow: [
            BoxShadow(
              color: Palette.red.withValues(alpha: 0.34),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Soft decorative rings
              Positioned(
                right: -50,
                top: -60,
                child: _Ring(size: 190, alpha: 0.10),
              ),
              Positioned(
                right: -20,
                bottom: -80,
                child: _Ring(size: 170, alpha: 0.08),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2_rounded, size: 14, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'EMERGENCY QR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            patientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.water_drop_rounded, size: 15, color: Color(0xFFFFD5D9)),
                              const SizedBox(width: 4),
                              Text(
                                'Blood type $bloodGroup',
                                style: const TextStyle(
                                  color: Color(0xFFFFE3E5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'View medical summary',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: url,
                        size: 112,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF111827),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF111827),
                        ),
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quiet card for other pages ───────────────────────────────────────────
  Widget _light(BuildContext context, String url) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _open(context, url),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Palette.outline),
            ),
            child: QrImageView(
              data: url,
              size: compact ? 76 : 92,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF111827)),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMERGENCY QR',
                  style: TextStyle(
                    color: Palette.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$patientName · $bloodGroup',
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Scan or tap to open your medical summary',
                  style: TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.35),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Palette.textMuted),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: alpha), width: 26),
      ),
    );
  }
}

/// First-responder medical summary (mirrors the website's EmergencySummaryPage).
class EmergencySummaryScreen extends StatelessWidget {
  const EmergencySummaryScreen({
    super.key,
    required this.patientName,
    required this.bloodGroup,
    required this.dob,
    required this.allergies,
    required this.conditions,
    required this.medications,
    required this.emergencyContactName,
    required this.emergencyContactRelation,
    required this.emergencyContactPhone,
    required this.summaryUrl,
  });

  final String patientName;
  final String bloodGroup;
  final String dob;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;
  final String emergencyContactName;
  final String emergencyContactRelation;
  final String emergencyContactPhone;
  final String summaryUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical summary'),
        actions: [
          IconButton(
            tooltip: 'Copy link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: summaryUrl));
              if (context.mounted) showSnack(context, 'Link copied');
            },
            icon: const Icon(Icons.link_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Palette.redLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.emergency_rounded, size: 18, color: Palette.red),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'For emergency first responders',
                    style: TextStyle(
                      color: Palette.redDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Palette.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        patientName.isNotEmpty ? patientName[0].toUpperCase() : 'Z',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            'Born $dob',
                            style: const TextStyle(color: Palette.textDim, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Palette.red,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        bloodGroup,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Palette.outline),
                  ),
                  child: QrImageView(
                    data: summaryUrl,
                    size: 176,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF111827),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.warning_amber_rounded,
            title: 'Allergies',
            color: Palette.red,
            items: allergies,
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.favorite_border_rounded,
            title: 'Conditions',
            color: Palette.blue,
            items: conditions,
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.medication_outlined,
            title: 'Medications',
            color: Palette.teal,
            items: medications,
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const IconChip(Icons.contacts_rounded, color: Palette.purple),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        emergencyContactName,
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$emergencyContactRelation · $emergencyContactPhone',
                        style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Palette.green,
                    minimumSize: const Size(46, 46),
                  ),
                  onPressed: () => launchUrl(
                    Uri(scheme: 'tel', path: emergencyContactPhone.replaceAll(' ', '')),
                  ),
                  icon: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconChip(icon, color: color, size: 36),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Palette.tint(color, 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
