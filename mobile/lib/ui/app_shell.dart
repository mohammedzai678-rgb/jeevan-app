import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import 'screens/care_map_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/jeevan_routes_screens.dart';
import 'screens/medications_screen.dart';
import 'screens/medikiosk_screen.dart';
import 'screens/sos_active_screen.dart';
import 'screens/walking_stick_screen.dart';
import 'widgets/common.dart';
import 'widgets/jeevan_logo.dart';

/// All 14 JeevanCare routes displayed in the vertical Sidebar Drawer list.
class JeevanRouteItem {
  const JeevanRouteItem({
    required this.id,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String id;
  final String emoji;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

const kJeevanRoutes = <JeevanRouteItem>[
  JeevanRouteItem(
    id: 'dashboard',
    emoji: '⬡',
    label: 'Dashboard',
    subtitle: 'Overview, Emergency QR & quick actions',
    icon: Icons.grid_view_rounded,
    color: Palette.red,
  ),
  JeevanRouteItem(
    id: 'sos',
    emoji: '🆘',
    label: 'Emergency SOS',
    subtitle: '3-Tap SOS, Agora video link & notified contacts',
    icon: Icons.sos_rounded,
    color: Palette.red,
  ),
  JeevanRouteItem(
    id: 'vitawatch',
    emoji: '📡',
    label: 'VitaWatch',
    subtitle: 'Live HR, SpO₂, BP, ECG & AI PPG scanner',
    icon: Icons.watch_rounded,
    color: Palette.teal,
  ),
  JeevanRouteItem(
    id: 'walking-stick',
    emoji: '🦯',
    label: 'Walking Stick',
    subtitle: 'ESP32 smart cane, radar & fall detection',
    icon: Icons.accessibility_new_rounded,
    color: Palette.blue,
  ),
  JeevanRouteItem(
    id: 'health-vault',
    emoji: '🔒',
    label: 'Health Vault',
    subtitle: 'Encrypted medical records & prescriptions',
    icon: Icons.folder_shared_rounded,
    color: Palette.amber,
  ),
  JeevanRouteItem(
    id: 'mediscan',
    emoji: '📄',
    label: 'Mediscan',
    subtitle: 'AI lab report, X-Ray & medicine analyzer',
    icon: Icons.document_scanner_rounded,
    color: Palette.purple,
  ),
  JeevanRouteItem(
    id: 'telemedicine',
    emoji: '🩺',
    label: 'Telemedicine',
    subtitle: 'Instant HD video consults & specialists',
    icon: Icons.videocam_rounded,
    color: Palette.teal,
  ),
  JeevanRouteItem(
    id: 'symptom-checker',
    emoji: '🧠',
    label: 'Symptom Checker',
    subtitle: 'Interactive body map & AI clinical triage',
    icon: Icons.psychology_rounded,
    color: Palette.pink,
  ),
  JeevanRouteItem(
    id: 'medications',
    emoji: '💊',
    label: 'Medications',
    subtitle: 'Daily schedule, adherence & FDA safety',
    icon: Icons.medication_rounded,
    color: Palette.orange,
  ),
  JeevanRouteItem(
    id: 'community',
    emoji: '🌐',
    label: 'Community',
    subtitle: 'Blood bank network & emergency alerts',
    icon: Icons.people_alt_rounded,
    color: Palette.red,
  ),
  JeevanRouteItem(
    id: 'emergency-services',
    emoji: '🚨',
    label: 'Emergency Services',
    subtitle: '24×7 hospitals, ambulances & helplines',
    icon: Icons.emergency_rounded,
    color: Palette.red,
  ),
  JeevanRouteItem(
    id: 'emergency-tracker',
    emoji: '🗺️',
    label: 'Emergency Route',
    subtitle: 'TomTom live ambulance & hospital routing',
    icon: Icons.route_rounded,
    color: Palette.blue,
  ),
  JeevanRouteItem(
    id: 'wellbeing',
    emoji: '🌸',
    label: 'Wellbeing',
    subtitle: 'Guided breathing, mood & AI wellness coach',
    icon: Icons.spa_rounded,
    color: Palette.pink,
  ),
  JeevanRouteItem(
    id: 'medikiosk',
    emoji: '🩻',
    label: 'MediKiosk',
    subtitle: '9-step walk-in diagnostic booth & token',
    icon: Icons.medical_information_rounded,
    color: Palette.teal,
  ),
  JeevanRouteItem(
    id: 'about',
    emoji: '✨',
    label: 'About Us',
    subtitle: 'JeevanCare mission, architecture & team',
    icon: Icons.auto_awesome_rounded,
    color: Palette.amber,
  ),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _activeRoute = 'dashboard';
  int _activeSubTab = 0;
  String _selectedLang = 'English';
  String? _shownSosEventId;

  static const _languages = <String>[
    'English',
    'हिन्दी (Hindi)',
    'বাংলা (Bengali)',
    'తెలుగు (Telugu)',
    'मराठी (Marathi)',
    'தமிழ் (Tamil)',
    'اردو (Urdu)',
    'ગુજરાતી (Gujarati)',
    'മലയാളം (Malayalam)',
    'ಕನ್ನಡ (Kannada)',
    'ଓଡ଼ିଆ (Odia)',
    'ਪੰਜਾਬੀ (Punjabi)',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(liveProvider).start();
      unawaited(ref.read(devicesProvider.notifier).refresh().catchError((_) {}));
      unawaited(ref.read(bleProvider).autoConnect());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(liveProvider).start();
      unawaited(ref.read(devicesProvider.notifier).refresh().catchError((_) {}));
      unawaited(ref.read(bleProvider).autoConnect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _navigateTo(String route, {int subTab = 0}) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeRoute = route;
      _activeSubTab = subTab;
    });
  }

  Widget _buildActiveScreen() {
    switch (_activeRoute) {
      case 'dashboard':
        return DashboardScreen(
          onOpenDevices: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
          ),
          onNavigate: _navigateTo,
        );
      case 'vitawatch':
        return VitaWatchRouteScreen(
          key: ValueKey('vitawatch-$_activeSubTab'),
          initialSubTab: _activeSubTab,
        );
      case 'walking-stick':
        return const WalkingStickScreen();
      case 'health-vault':
        return const HealthVaultRouteScreen();
      case 'mediscan':
        return MediscanRouteScreen(
          key: ValueKey('mediscan-$_activeSubTab'),
          initialSubTab: _activeSubTab,
        );
      case 'telemedicine':
        return const TelemedicineRouteScreen();
      case 'symptom-checker':
        return const SymptomCheckerRouteScreen();
      case 'medications':
        return const MedicationsScreen();
      case 'community':
        return CommunityRouteScreen(
          key: ValueKey('community-$_activeSubTab'),
          initialSubTab: _activeSubTab,
        );
      case 'emergency-services':
        return EmergencyServicesRouteScreen(
          key: ValueKey('emergency-services-$_activeSubTab'),
          initialSubTab: _activeSubTab,
        );
      case 'emergency-tracker':
        return const CareMapScreen();
      case 'wellbeing':
        return const WellbeingRouteScreen();
      case 'medikiosk':
        return const MediKioskScreen();
      case 'about':
        return AboutUsRouteScreen(onNavigate: _navigateTo);
      case 'profile':
        return ProfileRouteScreen(
          key: ValueKey('profile-$_activeSubTab'),
          initialSubTab: _activeSubTab,
        );
      case 'sos':
        return const SosActiveScreen(embedded: true);
      default:
        return DashboardScreen(onNavigate: _navigateTo);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SosState>(sosProvider, (prev, next) {
      final eventId = next.event?.eventId;
      if (next.active && eventId != null && eventId != _shownSosEventId) {
        _shownSosEventId = eventId;
        HapticFeedback.heavyImpact();
        setState(() => _activeRoute = 'sos');
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnack(
          context,
          '🚨 Emergency SOS Activated! Sent Blood Group, Live Location, Medical Details & Agora Link via SMS, Email & WhatsApp.',
        );
      } else if (!next.active && (prev?.active ?? false)) {
        _shownSosEventId = null;
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnack(
          context,
          '✅ Safe Alert sent via SMS, Email & WhatsApp! SOS deactivated.',
        );
      } else if (!next.active && next.tapCount > 0 && next.tapCount != (prev?.tapCount ?? 0)) {
        ScaffoldMessenger.of(context).clearSnackBars();
        showSnack(
          context,
          '🆘 Press SOS ${next.remainingTaps} more time${next.remainingTaps == 1 ? '' : 's'} within 5s to send SOS!',
        );
      }
    });

    final sos = ref.watch(sosProvider);
    final store = ref.watch(storeProvider);
    final session = ref.watch(authProvider).session;
    final emailName = session?.email?.split('@').first.trim() ?? '';
    final name = store.patientName.isNotEmpty
        ? store.patientName
        : (emailName.isNotEmpty ? emailName : 'zaid');
    final initial = name[0].toUpperCase();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Palette.bg,

      // ── Vertical Sidebar Drawer (Opened by pressing the top-left ☰ button) ──
      drawer: Drawer(
        width: 300,
        backgroundColor: Palette.surface,
        surfaceTintColor: Colors.transparent,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Header ('Z' + 'zaid' + 'A+')
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  _navigateTo('profile');
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${store.bloodGroup} · Medical ID Active',
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Palette.textMuted),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // Clean Vertical List of All 14 JeevanCare Routes (Zero Overlapping)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  children: [
                    for (final item in kJeevanRoutes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _SidebarRouteTile(
                          item: item,
                          selected: _activeRoute == item.id,
                          onTap: () {
                            Navigator.of(context).pop();
                            _navigateTo(item.id);
                          },
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    // Language Selector inside the Drawer so the top bar never overflows
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        setState(() => _selectedLang = v.split(' ').first);
                      },
                      itemBuilder: (_) => _languages
                          .map(
                            (l) => PopupMenuItem<String>(
                              value: l,
                              child: Text(l, style: const TextStyle(fontSize: 14)),
                            ),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(
                          children: [
                            const Text('🌐', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Language ($_selectedLang)',
                                style: const TextStyle(
                                  color: Palette.text,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.unfold_more_rounded, size: 18, color: Palette.textMuted),
                          ],
                        ),
                      ),
                    ),
                    _SidebarRouteTile(
                      item: const JeevanRouteItem(
                        id: 'profile',
                        emoji: '⚙️',
                        label: 'Profile Settings',
                        subtitle: 'Account, contacts & preferences',
                        icon: Icons.settings_rounded,
                        color: Palette.purple,
                      ),
                      selected: _activeRoute == 'profile',
                      onTap: () {
                        Navigator.of(context).pop();
                        _navigateTo('profile');
                      },
                    ),
                    _SidebarRouteTile(
                      item: const JeevanRouteItem(
                        id: 'signout',
                        emoji: '🚪',
                        label: 'Sign Out',
                        subtitle: 'Sign out of JeevanCare',
                        icon: Icons.logout_rounded,
                        color: Palette.red,
                      ),
                      selected: false,
                      onTap: () {
                        Navigator.of(context).pop();
                        ref.read(authProvider).signOut();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Single Clean Top Navbar: ☰ + JeevanCare Logo on Left, Live + SOS on Right ──
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            color: Palette.surface,
            border: Border(bottom: BorderSide(color: Palette.outline)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 60,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // ☰ Menu Button (Image 3) — opens the 14-route vertical list drawer
                    IconButton(
                      tooltip: 'Open Menu',
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      style: IconButton.styleFrom(
                        backgroundColor: Palette.surfaceHi,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.menu_rounded, color: Palette.text, size: 22),
                    ),
                    const SizedBox(width: 10),
                    // JeevanCare Logo + Wordmark (wrapped in Expanded so it can never overflow)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _navigateTo('dashboard'),
                        behavior: HitTestBehavior.opaque,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: const JeevanWordmark(logoSize: 32, fontSize: 18.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ConnectionBadge(),
                    const SizedBox(width: 8),
                    // Website-Parity 3-Tap SOS -> Green "I'M SAFE" Toggle Button
                    InkWell(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        if (sos.active) {
                          if (!sos.resolving) {
                            ref.read(sosProvider.notifier).resolve();
                          }
                        } else {
                          ref.read(sosProvider.notifier).registerTap();
                        }
                      },
                      onLongPress: () => _navigateTo('sos'),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: sos.active
                              ? const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                                )
                              : const LinearGradient(
                                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                                ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: (sos.active ? const Color(0xFF10B981) : Palette.red)
                                  .withValues(alpha: 0.30),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sos.active
                                  ? (sos.resolving ? '⏳' : '✅')
                                  : (sos.sending ? '⏳' : '🆘'),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              sos.active
                                  ? (sos.resolving ? 'SAFE…' : "I'M SAFE")
                                  : sos.sending
                                      ? 'ALERTING'
                                      : sos.tapCount > 0
                                          ? '${sos.remainingTaps} MORE'
                                          : 'SOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      // ── Active Screen Body (No bottom bar, no second top bar, no overlapping FAB) ──
      body: _buildActiveScreen(),
    );
  }
}

class _SidebarRouteTile extends StatelessWidget {
  const _SidebarRouteTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final JeevanRouteItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Palette.redLight : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: selected
                ? Border.all(color: Palette.red.withValues(alpha: 0.28))
                : null,
          ),
          child: Row(
            children: [
              if (selected)
                Container(
                  width: 3.5,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Palette.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              Text(
                item.emoji,
                style: TextStyle(
                  fontSize: 18,
                  color: selected ? Palette.red : Palette.text,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: selected ? Palette.red : Palette.text,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
