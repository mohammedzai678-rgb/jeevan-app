import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'care_map_screen.dart';
import 'clinical_tools_screen.dart';
import 'community_disaster_screen.dart';
import 'devices_screen.dart';
import 'history_screen.dart';
import 'medications_screen.dart';
import 'medikiosk_screen.dart';
import 'video_call_screen.dart';
import 'walking_stick_screen.dart';

/// Unified Ecosystem Hub: Live API & AI Engine Readiness + Full Feature Launcher Grid.
class ServicesHubScreen extends ConsumerStatefulWidget {
  const ServicesHubScreen({super.key});

  @override
  ConsumerState<ServicesHubScreen> createState() => _ServicesHubScreenState();
}

class _ServicesHubScreenState extends ConsumerState<ServicesHubScreen> {
  bool _loadingFeatures = true;
  String? _featuresError;
  Map<String, dynamic> _features = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadFeatures());
  }

  Future<void> _loadFeatures() async {
    if (!mounted) return;
    setState(() {
      _loadingFeatures = true;
      _featuresError = null;
    });
    try {
      final data = await ref.read(apiProvider).systemFeatures();
      if (!mounted) return;
      setState(() {
        _features = data;
        _loadingFeatures = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _featuresError = e.toString();
        _loadingFeatures = false;
      });
    }
  }

  void _open(Widget screen) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      ),
    );
  }

  List<({String label, bool active, String detail, IconData icon})> _buildEngineBadges() {
    final f = _features;
    final gemini = f['gemini'] == true;
    final openai = f['openai'] == true;
    final hf = f['huggingface'] == true;
    final tomtom = f['tomtom'] == true;
    final weather = f['openweather'] == true;
    final agora = f['agora'] == true;
    final brevoAny = (f['brevo_email'] == true) || (f['brevo_sms'] == true) || (f['brevo_whatsapp'] == true);
    final supabase = f['supabase'] == true;
    final ragChunks = (f['rag_chunks'] as num?)?.toInt() ?? 0;
    final ragDense = f['rag_dense'] == true;
    final ragRerank = f['rag_rerank'] == true;

    return [
      (
        label: 'Gemini',
        active: gemini,
        detail: gemini ? 'Live LLM' : 'Fallback',
        icon: Icons.auto_awesome_rounded,
      ),
      (
        label: 'OpenAI',
        active: openai,
        detail: openai ? 'Ready' : 'Standby',
        icon: Icons.psychology_rounded,
      ),
      (
        label: 'HuggingFace',
        active: hf,
        detail: hf ? 'Inference' : 'Local',
        icon: Icons.hub_rounded,
      ),
      (
        label: 'TomTom',
        active: tomtom,
        detail: tomtom ? 'Live Traffic' : 'OSM/Curated',
        icon: Icons.route_rounded,
      ),
      (
        label: 'OpenWeather',
        active: weather,
        detail: weather ? 'Live Radar' : 'Heuristic',
        icon: Icons.thunderstorm_rounded,
      ),
      (
        label: 'Agora RTC',
        active: agora,
        detail: agora ? '007 Token' : 'WebRTC Room',
        icon: Icons.videocam_rounded,
      ),
      (
        label: 'Brevo Email/SMS/WA',
        active: brevoAny,
        detail: brevoAny ? 'Multi-Channel' : 'In-App SOS',
        icon: Icons.notifications_active_rounded,
      ),
      (
        label: 'Supabase',
        active: supabase,
        detail: supabase ? 'Cloud DB' : 'In-Memory',
        icon: Icons.storage_rounded,
      ),
      (
        label: 'Hybrid RAG',
        active: ragChunks > 0 || ragDense || ragRerank,
        detail: '$ragChunks chunks',
        icon: Icons.menu_book_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final badges = _buildEngineBadges();
    final activeCount = badges.where((b) => b.active).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jeevan Ecosystem & Services Hub'),
        actions: [
          IconButton(
            tooltip: 'Refresh Engine Status',
            onPressed: _loadingFeatures ? null : _loadFeatures,
            icon: const Icon(Icons.refresh_rounded, color: Palette.teal),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: Palette.teal,
        onRefresh: _loadFeatures,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Live API & AI Engine Readiness Strip ───────────────────────────
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: Palette.teal.withOpacity(0.45),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Palette.surfaceHi,
                  Palette.surface,
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Palette.teal.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.dns_rounded, color: Palette.teal, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'API & AI ENGINE READINESS',
                              style: TextStyle(
                                color: Palette.teal,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Live integration status with resilient offline/curated fallbacks',
                              style: TextStyle(color: Palette.textDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (_loadingFeatures)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Palette.teal.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Palette.teal.withOpacity(0.4)),
                          ),
                          child: Text(
                            '$activeCount / ${badges.length} LIVE',
                            style: const TextStyle(
                              color: Palette.teal,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              fontFeatures: kTabular,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_featuresError != null)
                    Text(
                      'Status check offline ($_featuresError) — local fallbacks active.',
                      style: const TextStyle(color: Palette.amber, fontSize: 12),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final b in badges)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _EngineStatusChip(
                                label: b.label,
                                detail: b.detail,
                                active: b.active,
                                icon: b.icon,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Primary Feature Modules Grid ───────────────────────────────────
            const SectionHeader('Hardware, Clinical AI & Emergency Suite'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.96,
              children: [
                _HubFeatureTile(
                  icon: Icons.assist_walker_rounded,
                  title: 'Smart Walking Stick',
                  subtitle: 'ESP32 #2 • 3-Zone Ultrasonic Radar, Fall Alert & Safe-Zone Geofence',
                  badge: 'ESP32 #2',
                  color: Palette.teal,
                  onTap: () => _open(const WalkingStickScreen()),
                ),
                _HubFeatureTile(
                  icon: Icons.biotech_rounded,
                  title: 'AI Clinical Tools',
                  subtitle: 'Symptom Triage, MediScan Lab, OpenFDA, AYUSH & AI Radiology Imaging',
                  badge: '6 AI TOOLS',
                  color: Palette.blue,
                  onTap: () => _open(const ClinicalToolsScreen()),
                ),
                _HubFeatureTile(
                  icon: Icons.medication_rounded,
                  title: 'Medication & LED Trigger',
                  subtitle: 'Dose Adherence Tracker & VitaWatch Hardware Buzzer/LED Ring',
                  badge: 'HARDWARE SYNC',
                  color: Palette.amber,
                  onTap: () => _open(const MedicationsScreen()),
                ),
                _HubFeatureTile(
                  icon: Icons.public_rounded,
                  title: 'Community & Disaster',
                  subtitle: 'OpenWeather Disaster Risk, Blood Bank, NGOs, ABHA ID & QR Profile',
                  badge: '5 SERVICES',
                  color: Palette.red,
                  onTap: () => _open(const CommunityDisasterScreen()),
                ),
                _HubFeatureTile(
                  icon: Icons.local_hospital_rounded,
                  title: 'TomTom Care Map',
                  subtitle: 'Nearby Trauma Centers, Live Ambulance ETA & Traffic Delay Radar',
                  badge: 'LIVE ETA',
                  color: Palette.green,
                  onTap: () => _open(const CareMapScreen()),
                ),
                _HubFeatureTile(
                  icon: Icons.videocam_rounded,
                  title: 'Agora Telehealth 108',
                  subtitle: 'Encrypted Live Emergency Video Bridge with Real-Time Vitals Overlay',
                  badge: 'AGORA 007',
                  color: Palette.orange,
                  onTap: () => _open(
                    const VideoCallScreen(
                      channelId: 'jeevan-telehealth-108',
                      title: 'Emergency Telehealth Room (108)',
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Prominent MediKiosk OPD & AYUSH Clinical Interview Card
            GlassCard(
              padding: const EdgeInsets.all(16),
              onTap: () => _open(const MediKioskScreen()),
              borderColor: Palette.green.withOpacity(0.45),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Palette.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.fact_check_rounded, color: Palette.green, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MediKiosk OPD & AYUSH Clinical Interview',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Adaptive 10-question Allopathic (SOCRATES) & AYUSH (Dashavidha) intake in 22 Indian languages + 11-Section SOAP generator.',
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Palette.green),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Full-width VitaWatch BLE & Cloud Pairing Banner
            GlassCard(
              padding: const EdgeInsets.all(16),
              onTap: () => _open(const DevicesScreen()),
              borderColor: Palette.blue.withOpacity(0.4),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Palette.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.watch_rounded, color: Palette.blue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VitaWatch BLE (~40ms) & Cloud Hardware Pairing',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Scan and connect directly over Bluetooth GATT or pair ESP32 device IDs.',
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Palette.blue),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Full-width Vitals History & Manual Entry Banner
            GlassCard(
              padding: const EdgeInsets.all(16),
              onTap: () => _open(const HistoryScreen()),
              borderColor: Palette.teal.withOpacity(0.4),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Palette.teal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.timeline_rounded, color: Palette.teal, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recorded Vitals History & Manual BP/Vitals Entry',
                          style: TextStyle(
                            color: Palette.text,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'View HR, SpO₂, and temperature trend charts or log manual blood pressure readings.',
                          style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Palette.teal),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // ── Direct Deep-Link Shortcuts ─────────────────────────────────────
            const SectionHeader('Direct Tool Shortcuts'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickJumpChip(
                  icon: Icons.bloodtype_rounded,
                  label: 'Blood Bank Donors',
                  color: Palette.red,
                  onTap: () => _open(const CommunityDisasterScreen(initialTab: 1)),
                ),
                _QuickJumpChip(
                  icon: Icons.volunteer_activism_rounded,
                  label: 'Verified NGOs',
                  color: Palette.teal,
                  onTap: () => _open(const CommunityDisasterScreen(initialTab: 2)),
                ),
                _QuickJumpChip(
                  icon: Icons.badge_rounded,
                  label: 'ABHA Health ID (ABDM)',
                  color: Palette.blue,
                  onTap: () => _open(const CommunityDisasterScreen(initialTab: 3)),
                ),
                _QuickJumpChip(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Emergency Medical QR',
                  color: Palette.green,
                  onTap: () => _open(const CommunityDisasterScreen(initialTab: 4)),
                ),
                _QuickJumpChip(
                  icon: Icons.medication_liquid_rounded,
                  label: 'OpenFDA Drug Interactions',
                  color: Palette.amber,
                  onTap: () => _open(const ClinicalToolsScreen(initialTab: 2)),
                ),
                _QuickJumpChip(
                  icon: Icons.self_improvement_rounded,
                  label: 'Mental Wellbeing AI',
                  color: Palette.orange,
                  onTap: () => _open(const ClinicalToolsScreen(initialTab: 4)),
                ),
                _QuickJumpChip(
                  icon: Icons.collections_bookmark_rounded,
                  label: 'AI Radiology Imaging',
                  color: Palette.red,
                  onTap: () => _open(const ClinicalToolsScreen(initialTab: 5)),
                ),
                _QuickJumpChip(
                  icon: Icons.spa_rounded,
                  label: 'MediKiosk AYUSH Intake',
                  color: Palette.green,
                  onTap: () => _open(const MediKioskScreen(initialMode: 'ayush')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineStatusChip extends StatelessWidget {
  const _EngineStatusChip({
    required this.label,
    required this.detail,
    required this.active,
    required this.icon,
  });

  final String label;
  final String detail;
  final bool active;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = active ? Palette.green : Palette.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Palette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HubFeatureTile extends StatelessWidget {
  const _HubFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(15),
      borderColor: color.withOpacity(0.38),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 11.8,
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _QuickJumpChip extends StatelessWidget {
  const _QuickJumpChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
