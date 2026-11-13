import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'history_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _pingMs;
  bool _pinging = false;
  String? _pingError;

  Future<void> _pingServer() async {
    setState(() {
      _pinging = true;
      _pingError = null;
    });
    try {
      final ms = await ref.read(apiProvider).pingMs();
      if (mounted) {
        setState(() {
          _pingMs = ms;
          _pinging = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pingMs = null;
          _pingError = 'Unreachable';
          _pinging = false;
        });
      }
    }
  }

  Future<void> _changeServerUrl() async {
    final store = ref.read(storeProvider);
    final ctrl = TextEditingController(text: store.serverUrlOverride ?? Config.apiBaseUrl);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Palette.outline),
        ),
        title: const Text(
          'Change Server URL',
          style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(color: Palette.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'FastAPI Base URL',
            hintText: 'http://192.168.1.20:8000',
            prefixIcon: Icon(Icons.dns_rounded, color: Palette.teal),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await store.setServerUrl(null);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                setState(() {});
                showSnack(context, 'Reset to default server URL.');
              }
            },
            child: const Text('Reset Default', style: TextStyle(color: Palette.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 42)),
            onPressed: () async {
              await store.setServerUrl(ctrl.text.trim());
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                setState(() {});
                showSnack(context, 'Updated server URL.');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final api = ref.watch(apiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & System Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Palette.teal.withOpacity(0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.teal.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.verified_user_outlined, color: Palette.teal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Signed-in Account',
                        style: TextStyle(color: Palette.textDim, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session?.email ?? 'Authenticated Patient',
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const ConnectionBadge(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
            ),
            child: const Row(
              children: [
                Icon(Icons.insights_rounded, color: Palette.teal),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vitals History & Trend Charts',
                        style: TextStyle(color: Palette.text, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Inspect historical HR, SpO₂, temperature logs & record manual vitals',
                        style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Palette.textDim),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader('FastAPI Server & Latency Test'),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done_outlined, size: 18, color: Palette.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        api.baseUrl,
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ),
                    if (_pingMs != null)
                      StatusPill('normal', label: '$_pingMs ms')
                    else if (_pingError != null)
                      StatusPill('critical', label: _pingError),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pinging ? null : _pingServer,
                        icon: _pinging
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
                              )
                            : const Icon(Icons.speed_rounded, size: 18, color: Palette.teal),
                        label: const Text('Ping Server'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _changeServerUrl,
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Palette.blue),
                        label: const Text('Change Server URL'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader('Emergency Helplines'),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _HelplineRow(
                  number: '112',
                  title: 'National Emergency Response',
                  subtitle: 'All-in-one police, fire & medical dispatch',
                  color: Palette.red,
                ),
                const Divider(color: Palette.outline, height: 20),
                _HelplineRow(
                  number: '108',
                  title: 'Emergency Ambulance Service',
                  subtitle: '24/7 critical care ambulance dispatch',
                  color: Palette.orange,
                ),
                const Divider(color: Palette.outline, height: 20),
                _HelplineRow(
                  number: '1066',
                  title: 'Poison Control & Acute Care',
                  subtitle: 'Toxicology & overdose emergency helpline',
                  color: Palette.amber,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeader('Security & Privacy Architecture'),
          const GlassCard(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SecurityItem(
                  icon: Icons.vpn_key_outlined,
                  title: 'Android Keystore Encrypted JWTs',
                  subtitle: 'Session tokens are stored in hardware-backed EncryptedSharedPreferences with automatic background rotation.',
                ),
                SizedBox(height: 14),
                _SecurityItem(
                  icon: Icons.shield_outlined,
                  title: 'Isolated Hybrid RAG Vault',
                  subtitle: 'Uploaded medical records are scoped strictly to your authenticated user ID and never shared across accounts.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.red,
              side: BorderSide(color: Palette.red.withOpacity(0.55)),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => ref.read(authProvider).signOut(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'Sign Out',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelplineRow extends StatelessWidget {
  const _HelplineRow({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String number;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(
            number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              fontFeatures: kTabular,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Palette.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => launchUrl(Uri(scheme: 'tel', path: number)),
          style: IconButton.styleFrom(backgroundColor: color.withOpacity(0.15)),
          icon: Icon(Icons.call_rounded, color: color, size: 19),
        ),
      ],
    );
  }
}

class _SecurityItem extends StatelessWidget {
  const _SecurityItem({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Palette.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
// Jeevan sync: 2026-11-13
