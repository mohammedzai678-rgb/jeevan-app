import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/emergency_qr_card.dart';

/// Home: greeting, the Emergency QR hero, live Supabase stats overview and three quick actions.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    this.onOpenDevices,
    this.onNavigate,
  });

  final VoidCallback? onOpenDevices;
  final void Function(String route, {int subTab})? onNavigate;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _docCount = 0;
  int _alertCount = 0;
  bool _loadingCounts = false;

  @override
  void initState() {
    super.initState();
    _fetchLiveCounts();
  }

  Future<void> _fetchLiveCounts() async {
    final userId = ref.read(authProvider).session?.userId ?? '';
    if (userId.isEmpty) return;
    setState(() => _loadingCounts = true);
    try {
      final api = ref.read(apiProvider);
      final docsFuture = api
          .healthVaultDocuments()
          .catchError((_) => <Map<String, dynamic>>[]);
      final alertsFuture =
          api.healthVaultAlerts().catchError((_) => <Map<String, dynamic>>[]);
      final results = await Future.wait([docsFuture, alertsFuture]);
      if (mounted) {
        setState(() {
          _docCount = results[0].length;
          _alertCount = results[1].length;
          _loadingCounts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCounts = false);
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _go(String route, {int subTab = 0}) =>
      widget.onNavigate?.call(route, subTab: subTab);

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());
    final store = ref.watch(storeProvider);
    final session = ref.watch(sessionProvider).valueOrNull;

    final displayName = session?.email != null && session!.email!.isNotEmpty
        ? (store.patientName != 'User'
            ? store.patientName
            : session.email!.split('@').first)
        : store.patientName;

    return RefreshIndicator(
      onRefresh: _fetchLiveCounts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // Greeting
          Text(
            '${_greeting()} 👋',
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            displayName,
            style: const TextStyle(
              color: Palette.text,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dateStr,
            style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 20),

          // Hero: always-visible Emergency QR with live Supabase user data
          EmergencyQrCard(
            hero: true,
            patientName: displayName,
            bloodGroup: store.bloodGroup,
            dob: store.dateOfBirth,
            allergies: store.allergies
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty && e != 'None reported')
                .toList(),
            conditions: store.conditions
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty && e != 'None reported')
                .toList(),
            medications: store.medications
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty && e != 'None')
                .toList(),
            emergencyContactName: store.contactName,
            emergencyContactRelation: store.contactRelation,
            emergencyContactPhone: store.contactPhone,
            emergencyContacts: store.emergencyContacts,
            showEmergencyContacts: store.showEmergencyContactsOnQr,
          ),
          const SizedBox(height: 28),

          // Overview (Live Supabase counts)
          const SectionHeader('Overview'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              _StatTile(
                icon: Icons.groups_rounded,
                color: Palette.purple,
                value: store.contactPhone.isNotEmpty ? '1' : '0',
                label: 'Contacts',
                onTap: () => _go('profile', subTab: 1),
              ),
              _StatTile(
                icon: Icons.folder_copy_rounded,
                color: Palette.blue,
                value: '$_docCount',
                label: 'Documents',
                onTap: () => _go('health-vault'),
              ),
              _StatTile(
                icon: Icons.medication_rounded,
                color: Palette.amber,
                value: 'Active',
                label: 'Medications',
                onTap: () => _go('medications'),
              ),
              _StatTile(
                icon: Icons.local_hospital_rounded,
                color: Palette.teal,
                value: 'Nearby',
                label: 'Hospitals',
                onTap: () => _go('emergency-services', subTab: 0),
              ),
              _StatTile(
                icon: Icons.bloodtype_rounded,
                color: Palette.red,
                value: '24×7',
                label: 'Blood banks',
                onTap: () => _go('emergency-services', subTab: 1),
              ),
              _StatTile(
                icon: Icons.campaign_rounded,
                color: Palette.orange,
                value: '$_alertCount',
                label: 'Community alerts',
                onTap: () => _go('community'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Quick actions
          const SectionHeader('Quick actions'),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.sos_rounded,
                  color: Palette.red,
                  title: 'Run an SOS test',
                  subtitle: 'Check location and alerts',
                  onTap: () => _go('sos'),
                ),
                const Divider(indent: 72, endIndent: 16),
                _ActionRow(
                  icon: Icons.local_hospital_rounded,
                  color: Palette.teal,
                  title: 'Find hospitals',
                  subtitle: 'Emergency care near you',
                  onTap: () => _go('emergency-services', subTab: 0),
                ),
                const Divider(indent: 72, endIndent: 16),
                _ActionRow(
                  icon: Icons.volunteer_activism_rounded,
                  color: Palette.blue,
                  title: 'Connect with an NGO',
                  subtitle: 'Relief and medical aid',
                  onTap: () => _go('emergency-services', subTab: 3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconChip(icon, color: color, size: 38),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Palette.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                    fontFeatures: kTabular,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconChip(icon, color: color, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Palette.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style:
                        const TextStyle(color: Palette.textDim, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Palette.textMuted),
          ],
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
