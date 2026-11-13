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
    this.patientName = '',
    this.bloodGroup = '',
    this.dob = '',
    this.allergies = const [],
    this.conditions = const [],
    this.medications = const [],
    this.emergencyContactName = '',
    this.emergencyContactRelation = '',
    this.emergencyContactPhone = '',
    this.emergencyContacts,
    this.showEmergencyContacts,
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
  final List<Map<String, String>>? emergencyContacts;
  final bool? showEmergencyContacts;
  final bool compact;
  final bool hero;

  void _open(
    BuildContext context,
    String url, {
    required String name,
    required String blood,
    required String birthDate,
    required List<String> allergies,
    required List<String> conditions,
    required List<String> medications,
    required List<Map<String, String>> contacts,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmergencySummaryScreen(
          patientName: name,
          bloodGroup: blood,
          dob: birthDate,
          allergies: allergies,
          conditions: conditions,
          medications: medications,
          emergencyContacts: contacts,
          summaryUrl: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(sessionProvider).valueOrNull?.userId ??
        ref.read(authProvider).session?.userId;
    if (uid == null || uid.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(16),
        child: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: Palette.red),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sign in to create your emergency QR summary.',
                style: TextStyle(color: Palette.textDim, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final url = '${Config.webBaseUrl}/emergency/$uid';
    final store = ref.read(storeProvider);
    List<String> savedList(String value) => value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && !item.startsWith('None'))
        .toList();
    List<String> resolveList(List<String> supplied, String saved) =>
        (supplied.isNotEmpty ? supplied : savedList(saved))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && !item.startsWith('None'))
            .toList();
    final name =
        patientName.trim().isNotEmpty ? patientName.trim() : store.patientName;
    final blood =
        bloodGroup.trim().isNotEmpty ? bloodGroup.trim() : store.bloodGroup;
    final birthDate = dob.trim().isNotEmpty
        ? dob.trim()
        : (store.dateOfBirth.trim().isNotEmpty
            ? store.dateOfBirth.trim()
            : 'Not provided');
    final resolvedAllergies = resolveList(allergies, store.allergies);
    final resolvedConditions = resolveList(conditions, store.conditions);
    final resolvedMedications = resolveList(medications, store.medications);
    final showContacts =
        showEmergencyContacts ?? store.showEmergencyContactsOnQr;
    final contacts = showContacts
        ? (emergencyContacts ??
            (emergencyContactPhone.trim().isNotEmpty ||
                    emergencyContactName.trim().isNotEmpty
                ? [
                    {
                      'name': emergencyContactName.trim().isNotEmpty
                          ? emergencyContactName.trim()
                          : store.contactName,
                      'relationship': emergencyContactRelation.trim().isNotEmpty
                          ? emergencyContactRelation.trim()
                          : store.contactRelation,
                      'phone': emergencyContactPhone.trim().isNotEmpty
                          ? emergencyContactPhone.trim()
                          : store.contactPhone,
                      'email': store.contactEmail,
                    }
                  ]
                : store.emergencyContacts))
        : const <Map<String, String>>[];
    final openSummary = () => _open(
          context,
          url,
          name: name,
          blood: blood,
          birthDate: birthDate,
          allergies: resolvedAllergies,
          conditions: resolvedConditions,
          medications: resolvedMedications,
          contacts: contacts,
        );
    return hero
        ? _hero(context, url, name, blood, openSummary)
        : _light(context, url, name, blood, openSummary);
  }

  // ── Dashboard showpiece ──────────────────────────────────────────────────
  Widget _hero(BuildContext context, String url, String name, String blood,
      VoidCallback openSummary) {
    return GestureDetector(
      onTap: openSummary,
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2_rounded,
                                    size: 14, color: Colors.white),
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
                            name,
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
                              const Icon(Icons.water_drop_rounded,
                                  size: 15, color: Color(0xFFFFD5D9)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Blood type $blood',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFFE3E5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: const [
                              Flexible(
                                child: Text(
                                  'View medical summary',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 16, color: Colors.white),
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
  Widget _light(BuildContext context, String url, String name, String blood,
      VoidCallback openSummary) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: openSummary,
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
              eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square, color: Color(0xFF111827)),
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
                  '$name · $blood',
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
                  style: TextStyle(
                      color: Palette.textDim, fontSize: 12.5, height: 1.35),
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
        border:
            Border.all(color: Colors.white.withValues(alpha: alpha), width: 26),
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
    required this.emergencyContacts,
    required this.summaryUrl,
  });

  final String patientName;
  final String bloodGroup;
  final String dob;
  final List<String> allergies;
  final List<String> conditions;
  final List<String> medications;
  final List<Map<String, String>> emergencyContacts;
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
                        patientName.isNotEmpty
                            ? patientName[0].toUpperCase()
                            : 'Z',
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
                            style: const TextStyle(
                                color: Palette.textDim, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const IconChip(Icons.contacts_rounded,
                        color: Palette.purple),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Emergency contacts',
                        style: TextStyle(
                          color: Palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text('${emergencyContacts.length}',
                        style: const TextStyle(
                            color: Palette.textDim, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                if (emergencyContacts.isEmpty)
                  const Text(
                    'No emergency contacts saved for the QR.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                  )
                else
                  for (var i = 0; i < emergencyContacts.length; i++) ...[
                    if (i > 0) const Divider(height: 18),
                    _EmergencyContactSummaryRow(contact: emergencyContacts[i]),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyContactSummaryRow extends StatelessWidget {
  const _EmergencyContactSummaryRow({required this.contact});

  final Map<String, String> contact;

  @override
  Widget build(BuildContext context) {
    final name = contact['name']?.trim().isNotEmpty == true
        ? contact['name']!.trim()
        : 'Emergency contact';
    final relation = contact['relationship']?.trim() ?? '';
    final phone = contact['phone']?.trim() ?? '';
    final email = contact['email']?.trim() ?? '';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Palette.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              if (relation.isNotEmpty || phone.isNotEmpty)
                Text(
                  [
                    if (relation.isNotEmpty) relation,
                    if (phone.isNotEmpty) phone
                  ].join(' · '),
                  style:
                      const TextStyle(color: Palette.textDim, fontSize: 12.5),
                ),
              if (email.isNotEmpty)
                Text(email,
                    style: const TextStyle(
                        color: Palette.textDim, fontSize: 12.5)),
            ],
          ),
        ),
        if (phone.isNotEmpty)
          IconButton.filled(
            tooltip: 'Call $name',
            style: IconButton.styleFrom(
              backgroundColor: Palette.green,
              minimumSize: const Size(46, 46),
            ),
            onPressed: () => launchUrl(
              Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), '')),
            ),
            icon: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
          ),
      ],
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
// Jeevan sync: 2026-11-13
