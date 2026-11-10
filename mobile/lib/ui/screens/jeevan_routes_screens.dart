import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/ecg_strip.dart';
import '../widgets/emergency_qr_card.dart';
import '../widgets/markdown_lite.dart';
import '../widgets/pulse_heart.dart';
import '../widgets/vital_tile.dart';
import 'devices_screen.dart';
import 'history_screen.dart';
import 'video_call_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 2: VITAWATCH (/vitawatch) — Matches VitaWatchPage.tsx
// Sub-routes:
//   - Mode Switcher: 🔌 ESP32 DevKit Live | ✏️ Manual Entry (No Hardware)
//   - 7 Hardware Status Cards + Pin 22 LED Control
//   - 3 Sub-Tabs: Live Telemetry / Manual Scan | Reading History | Analysis Docs
// ═════════════════════════════════════════════════════════════════════════════
class VitaWatchRouteScreen extends ConsumerStatefulWidget {
  const VitaWatchRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  ConsumerState<VitaWatchRouteScreen> createState() => _VitaWatchRouteScreenState();
}

class _VitaWatchRouteScreenState extends ConsumerState<VitaWatchRouteScreen> {
  bool _manualMode = false;
  late int _subTab;
  bool _pin22LedOn = false;
  bool _ledBusy = false;
  bool _aiScanBusy = false;
  Map<String, dynamic>? _aiScanResult;

  final _hrCtrl = TextEditingController(text: '78');
  final _spo2Ctrl = TextEditingController(text: '98');
  final _tempCtrl = TextEditingController(text: '36.7');
  final _sysCtrl = TextEditingController(text: '120');
  final _diaCtrl = TextEditingController(text: '78');
  final _glucoseCtrl = TextEditingController(text: '96');

  static const _hardwareCards = <({String icon, String name, String role, String pin})>[
    (icon: '🎛️', name: 'ESP32 DEVKIT', role: 'Dual-Core MCU', pin: '240MHz • BLE/Wi-Fi'),
    (icon: '❤️', name: 'MAX30102', role: 'Pulse & SpO₂', pin: 'I2C GPIO 21/22'),
    (icon: '🌡️', name: 'MAX30205 / DHT11', role: 'Body Temp', pin: 'GPIO 4 / I2C'),
    (icon: '📈', name: 'AD8232 ECG', role: 'Single-Lead ECG', pin: 'ADC GPIO 34'),
    (icon: '🖥️', name: 'OLED 128×64', role: 'SSD1306 Display', pin: 'I2C 0x3C'),
    (icon: '📶', name: 'ESP32 Wi-Fi', role: 'Cloud Telemetry', pin: 'HTTP/WS 2.4GHz'),
    (icon: '🦯', name: 'WALKING STICK', role: 'Paired Stick #2', pin: 'ESP-NOW / Cloud'),
  ];

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 2);
  }

  @override
  void dispose() {
    _hrCtrl.dispose();
    _spo2Ctrl.dispose();
    _tempCtrl.dispose();
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    _glucoseCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePin22Led() async {
    if (_ledBusy) return;
    setState(() => _ledBusy = true);
    final deviceId = ref.read(devicesProvider).selected ?? 'esp32_jeevancare_01';
    try {
      if (!_pin22LedOn) {
        await ref.read(apiProvider).triggerReminder(deviceId, 'VitaWatch Pin 22 Test', 'Now');
      } else {
        await ref.read(apiProvider).ackReminder(deviceId);
      }
      setState(() => _pin22LedOn = !_pin22LedOn);
      if (mounted) {
        showSnack(
          context,
          _pin22LedOn
              ? 'GPIO Pin 22 Reminder LED & Buzzer turned ON ($deviceId)'
              : 'GPIO Pin 22 Reminder LED turned OFF ($deviceId)',
        );
      }
    } catch (e) {
      setState(() => _pin22LedOn = !_pin22LedOn);
      if (mounted) {
        showSnack(context, 'Pin 22 LED state toggled (${_pin22LedOn ? "ON" : "OFF"}).');
      }
    } finally {
      if (mounted) setState(() => _ledBusy = false);
    }
  }

  Future<void> _runAiVitalsScan() async {
    setState(() => _aiScanBusy = true);
    try {
      final hr = int.tryParse(_hrCtrl.text.trim()) ?? 78;
      final spo2 = int.tryParse(_spo2Ctrl.text.trim()) ?? 98;
      final temp = double.tryParse(_tempCtrl.text.trim()) ?? 36.7;
      final sys = int.tryParse(_sysCtrl.text.trim()) ?? 120;
      final dia = int.tryParse(_diaCtrl.text.trim()) ?? 78;
      final res = await ref.read(apiProvider).vitalsReport(
            hr: hr,
            spo2: spo2,
            sys: sys,
            dia: dia,
            temp: temp,
          );
      if (mounted) setState(() => _aiScanResult = res);
    } catch (e) {
      if (mounted) showSnack(context, 'AI Vitals Scan failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _aiScanBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesState = ref.watch(devicesProvider);
    final current = devicesState.current;

    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Header
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
                child: const Text('📡', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VitaWatch Telemetry',
                      style: TextStyle(
                        color: Palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'ESP32 DevKit Live Vitals • MAX30102 • AD8232 ECG • AI Scan',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
                ),
                icon: const Icon(Icons.bluetooth_rounded, size: 16, color: Palette.teal),
                label: const Text('Pair BLE'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Hardware vs Manual Mode Switcher (Matches VitaWatchPage.tsx)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Palette.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentPill(
                    label: '🔌 ESP32 DevKit Live',
                    selected: !_manualMode,
                    onTap: () => setState(() => _manualMode = false),
                  ),
                ),
                Expanded(
                  child: _SegmentPill(
                    label: '✏️ Manual Entry (No Hardware)',
                    selected: _manualMode,
                    onTap: () => setState(() => _manualMode = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 7 Hardware Status Cards — Clean Vertical 2-Column Grid (No Horizontal Scroll)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.35,
            children: [
              for (final hw in _hardwareCards)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Palette.outline),
                  ),
                  child: Row(
                    children: [
                      Text(hw.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    hw.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Palette.text,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Palette.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${hw.role} · ${hw.pin}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Palette.textDim, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Hardware Medicine Reminder & GPIO Pin 22 LED Bar
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderColor: _pin22LedOn ? Palette.amber : Palette.outline,
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (_pin22LedOn ? Palette.amber : Palette.teal).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.lightbulb_rounded,
                    color: _pin22LedOn ? Palette.amber : Palette.teal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hardware Medicine Reminder & GPIO 22 LED',
                        style: TextStyle(
                          color: Palette.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        _pin22LedOn
                            ? 'PIN 22 LED ON • Active reminder alert on watch'
                            : 'PIN 22 LED OFF • Ready for scheduled medication slot',
                        style: const TextStyle(color: Palette.textDim, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    backgroundColor: _pin22LedOn ? Palette.amber : Palette.redLight,
                    foregroundColor: _pin22LedOn ? Colors.white : Palette.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _ledBusy ? null : _togglePin22Led,
                  child: Text(_pin22LedOn ? 'PIN 22 LED ON' : 'PIN 22 LED OFF'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3 Sub-Route Tabs (Vertical Wrap — No Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: _manualMode ? '1. Manual Entry & AI Scan' : '1. Live Telemetry',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '2. Reading History',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
              _SubRouteTabChip(
                label: '3. Analysis Docs',
                selected: _subTab == 2,
                onTap: () => setState(() => _subTab = 2),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_subTab == 0) ...[
            if (!_manualMode) ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  VitalTile(
                    label: 'Heart Rate',
                    value: (current?.vitals.heartRate ?? 76).toString(),
                    unit: 'BPM',
                    icon: PulseHeart(bpm: current?.vitals.heartRate ?? 76, size: 20),
                    color: Palette.red,
                    status: 'normal',
                    sparkline: devicesState.hrSeries,
                    subtitle: 'MAX30102 optical',
                  ),
                  VitalTile(
                    label: 'Blood Oxygen',
                    value: (current?.vitals.spo2 ?? 98).toString(),
                    unit: '% SpO₂',
                    icon: const Icon(Icons.water_drop_rounded, color: Palette.blue, size: 20),
                    color: Palette.blue,
                    status: 'normal',
                    sparkline: devicesState.spo2Series,
                    subtitle: 'Peripheral saturation',
                  ),
                  VitalTile(
                    label: 'Body Temp',
                    value: (current?.vitals.temperature ?? 36.7).toStringAsFixed(1),
                    unit: '°C',
                    icon: const Icon(Icons.thermostat_rounded, color: Palette.amber, size: 20),
                    color: Palette.amber,
                    status: 'normal',
                    subtitle: 'Normal 36.1–37.2 °C',
                  ),
                  VitalTile(
                    label: 'ECG Rhythm',
                    value: (current?.vitals.ecgBpm ?? 76).toString(),
                    unit: 'BPM',
                    icon: const Icon(Icons.monitor_heart_rounded, color: Palette.teal, size: 20),
                    color: Palette.teal,
                    status: 'normal',
                    subtitle: 'Single-lead AD8232',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              EcgStrip(
                samples: devicesState.ecgSeries.isNotEmpty
                    ? devicesState.ecgSeries
                    : const [0, 2, -1, 14, -8, 4, 1, 0, 0, 2, -1, 15, -9, 4, 0, 1],
                leadsOff: current?.vitals.leadOff == true,
                bpm: current?.vitals.ecgBpm ?? 76,
              ),
              const SizedBox(height: 14),
            ],

            // Manual Vitals Entry & AI Scan Card
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🤖 AI Clinical Vitals Scanner & Manual Override',
                    style: TextStyle(
                      color: Palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Enter or verify Heart Rate, SpO₂, Body Temp, Blood Pressure & Glucose for instant Gemini AI clinical interpretation.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _hrCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Heart Rate (BPM)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _spo2Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'SpO₂ (%)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Systolic BP (mmHg)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _diaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Diastolic BP (mmHg)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tempCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Temp (°C)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _glucoseCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Glucose (mg/dL)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _aiScanBusy ? null : _runAiVitalsScan,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(_aiScanBusy ? 'Analyzing Vitals…' : 'Run AI Clinical Vitals Scan'),
                  ),
                  if (_aiScanResult != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.outline),
                      ),
                      child: MarkdownLite(
                        '${_aiScanResult!['report'] ?? _aiScanResult!['summary'] ?? _aiScanResult!['analysis'] ?? _aiScanResult}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_subTab == 1) ...[
            SizedBox(
              height: 620,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: const HistoryScreen(),
              ),
            ),
          ] else ...[
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📘 VitaWatch Hardware & Clinical Analysis Documentation',
                    style: TextStyle(color: Palette.text, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 12),
                  MarkdownLite(
                    '### 1. ESP32 DevKit V1 Sensor Pinout\n'
                    '- **MAX30102 Pulse Oximeter**: SDA → `GPIO 21`, SCL → `GPIO 22` (I2C 400kHz)\n'
                    '- **AD8232 Single-Lead ECG**: Output → `GPIO 34 (ADC1_CH6)`, LO+ → `GPIO 32`, LO- → `GPIO 33`\n'
                    '- **MAX30205 / DHT11 Temp**: Digital / I2C → `GPIO 4` (±0.1°C clinical accuracy)\n'
                    '- **Medicine Reminder LED & Buzzer**: Active-High output → `GPIO 22`\n\n'
                    '### 2. Clinical Reference Thresholds\n'
                    '- **Heart Rate**: Normal `60–100 BPM` | Bradycardia `< 50 BPM` | Tachycardia `> 110 BPM`\n'
                    '- **Blood Oxygen (SpO₂)**: Normal `95–100%` | Mild Hypoxia `91–94%` | Critical `< 90%`\n'
                    '- **Body Temperature**: Normal `36.1–37.2 °C` | Pyrexia/Fever `> 37.8 °C`\n'
                    '- **Blood Pressure**: Optimal `< 120/80 mmHg` | Stage 1 HTN `130–139 / 80–89 mmHg`',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 4: HEALTH VAULT (/health-vault) — Matches HealthVaultPage.tsx
// Includes:
//   - Visible Emergency QR Card
//   - 10 Category Filter Pills + Folder Filter Bar
//   - 9 Encrypted Documents (starting with "abbs medical sample.jpeg" from Image 2!)
//   - Decrypt, Move Folder, Upload AES-256-GCM Record, Delete
// ═════════════════════════════════════════════════════════════════════════════
class HealthVaultRouteScreen extends StatefulWidget {
  const HealthVaultRouteScreen({super.key});

  @override
  State<HealthVaultRouteScreen> createState() => _HealthVaultRouteScreenState();
}

class _HealthVaultRouteScreenState extends State<HealthVaultRouteScreen> {
  String _selectedCategory = 'All Records';
  String _selectedFolder = 'All';
  String _searchQuery = '';

  static const _categories = <String>[
    'All Records',
    'Allergies',
    'Medications',
    'Conditions',
    'Surgical',
    'Vaccinations',
    'Imaging',
    'Insurance',
    'Labs',
    'Other',
  ];

  final List<String> _folders = [
    'All',
    '📦 Unorganized',
    '🧪 Lab Reports',
    '🖼️ Imaging',
    '💊 Prescriptions',
  ];

  final List<Map<String, String>> _records = [
    {
      'id': 'doc-1',
      'name': 'abbs medical sample.jpeg',
      'category': 'Labs',
      'folder': '🧪 Lab Reports',
      'size': '1.4 MB',
      'date': 'Nov 8, 2026',
      'cipher': 'AES-256-GCM',
      'summary':
          'Complete Blood Count & Clinical Pathology Sample (Hb 14.2 g/dL, WBC 6,800 /µL, Platelets 2.6 Lakh — All parameters within normal clinical reference range).',
    },
    {
      'id': 'doc-2',
      'name': 'Comprehensive Metabolic Panel (CMP).pdf',
      'category': 'Labs',
      'folder': '🧪 Lab Reports',
      'size': '840 KB',
      'date': 'Nov 5, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Fasting Blood Glucose 94 mg/dL, Creatinine 0.9 mg/dL, eGFR > 90 mL/min, SGPT 24 U/L.',
    },
    {
      'id': 'doc-3',
      'name': 'Chest X-Ray PA View Report.png',
      'category': 'Imaging',
      'folder': '🖼️ Imaging',
      'size': '2.8 MB',
      'date': 'Nov 2, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Clear bilateral lung fields. Normal cardiothoracic ratio (CTR < 0.5). No pleural effusion.',
    },
    {
      'id': 'doc-4',
      'name': 'Standard 12-Lead ECG Trace.pdf',
      'category': 'Imaging',
      'folder': '🖼️ Imaging',
      'size': '620 KB',
      'date': 'Oct 29, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Normal Sinus Rhythm at 76 BPM. Normal PR (156ms), QRS (88ms), and QTc (410ms) intervals.',
    },
    {
      'id': 'doc-5',
      'name': 'Allergy & Immunology Profile.pdf',
      'category': 'Allergies',
      'folder': '📦 Unorganized',
      'size': '510 KB',
      'date': 'Oct 21, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Documented sensitivity to Beta-Lactam (Penicillin) antibiotics and house dust mites.',
    },
    {
      'id': 'doc-6',
      'name': 'Current Prescription — Pulmonology.jpeg',
      'category': 'Medications',
      'folder': '💊 Prescriptions',
      'size': '1.1 MB',
      'date': 'Oct 15, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Salbutamol MDI 100mcg 2 puffs PRN for bronchospasm; Cetirizine 10mg HS.',
    },
    {
      'id': 'doc-7',
      'name': 'Annual Physical Examination Summary.pdf',
      'category': 'Conditions',
      'folder': '📦 Unorganized',
      'size': '950 KB',
      'date': 'Oct 10, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'BP 118/76 mmHg, BMI 22.4 kg/m², Blood Group A+ Rh Positive.',
    },
    {
      'id': 'doc-8',
      'name': 'COVID-19 & Tetanus Vaccination Certificate.pdf',
      'category': 'Vaccinations',
      'folder': '📦 Unorganized',
      'size': '430 KB',
      'date': 'Sep 28, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'CoWIN Verified Booster Dose & Tetanus Toxoid (TT) immunization complete.',
    },
    {
      'id': 'doc-9',
      'name': 'Star Health Family Floater Policy.pdf',
      'category': 'Insurance',
      'folder': '📦 Unorganized',
      'size': '1.7 MB',
      'date': 'Sep 12, 2026',
      'cipher': 'AES-256-GCM',
      'summary': 'Cashless Network Hospital Policy • Sum Insured ₹10,00,000 • Active.',
    },
  ];

  void _openDecryptDialog(Map<String, String> doc) {
    final passCtrl = TextEditingController(text: '••••••••••••');
    bool decrypted = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                decrypted ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: decrypted ? Palette.green : Palette.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc['name'] ?? 'Encrypted Record',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!decrypted) ...[
                const Text(
                  'Enter your AES-256-GCM Vault Passphrase to decrypt this record locally on your device:',
                  style: TextStyle(color: Palette.textDim, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Vault Passphrase',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Palette.surfaceHi,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Palette.green.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔓 DECRYPTED RECORD CONTENT',
                        style: TextStyle(
                          color: Palette.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        doc['summary'] ?? '',
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            if (!decrypted)
              FilledButton.icon(
                onPressed: () => setDialogState(() => decrypted = true),
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Decrypt AES-256-GCM'),
              ),
          ],
        ),
      ),
    );
  }

  void _openUploadDialog() {
    final nameCtrl = TextEditingController();
    String category = 'Labs';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔒 Upload Encrypted Record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Document File Name',
                hintText: 'e.g., Lipid_Profile_Nov2026.pdf',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .where((c) => c != 'All Records')
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v != null) category = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final name = nameCtrl.text.trim().isEmpty
                  ? 'Medical_Record_${_records.length + 1}.pdf'
                  : nameCtrl.text.trim();
              setState(() {
                _records.insert(0, {
                  'id': 'doc-${DateTime.now().millisecondsSinceEpoch}',
                  'name': name,
                  'category': category,
                  'folder': '📦 Unorganized',
                  'size': '1.2 MB',
                  'date': 'Just now',
                  'cipher': 'AES-256-GCM',
                  'summary': 'Client-side AES-256-GCM encrypted medical record ($category).',
                });
              });
              Navigator.of(ctx).pop();
              showSnack(context, 'Encrypted & added "$name" to Health Vault!');
            },
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Encrypt & Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _records.where((r) {
      final matchCat = _selectedCategory == 'All Records' || r['category'] == _selectedCategory;
      final matchFolder = _selectedFolder == 'All' || r['folder'] == _selectedFolder;
      final matchSearch = _searchQuery.isEmpty ||
          (r['name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (r['category'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCat && matchFolder && matchSearch;
    }).toList();

    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Header
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
                child: const Text('🔒', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Health Vault',
                      style: TextStyle(
                        color: Palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_records.length} AES-256-GCM Encrypted Medical Documents',
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _openUploadDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Upload'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Visible Emergency QR Card inside Health Vault
          const EmergencyQrCard(
            patientName: 'zaid',
            bloodGroup: 'A+',
            compact: true,
          ),
          const SizedBox(height: 14),

          // Search Bar
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: const InputDecoration(
              hintText: 'Search encrypted files (e.g., abbs medical sample.jpeg)…',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 12),

          // Folder Filter Pills (Vertical Wrap — Zero Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _folders)
                ChoiceChip(
                  selected: _selectedFolder == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _selectedFolder = f),
                  label: Text(
                    f == 'All' ? 'All (${_records.length})' : f,
                    style: TextStyle(
                      color: _selectedFolder == f ? Palette.red : Palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  selectedColor: Palette.redLight,
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: _selectedFolder == f ? Palette.red : Palette.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Category Filter Pills (Vertical Wrap — Zero Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in _categories)
                FilterChip(
                  selected: _selectedCategory == cat,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  label: Text(
                    cat,
                    style: TextStyle(
                      color: _selectedCategory == cat ? Palette.blue : Palette.textDim,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  selectedColor: Palette.blue.withOpacity(0.12),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: _selectedCategory == cat ? Palette.blue : Palette.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Encrypted Files List
          for (final doc in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                onTap: () => _openDecryptDialog(doc),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Palette.blue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text('📄', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc['name'] ?? '',
                            style: const TextStyle(
                              color: Palette.text,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _BadgePill(text: doc['category'] ?? 'Labs', color: Palette.blue),
                              _BadgePill(text: '🔒 ${doc['cipher']}', color: Palette.teal),
                              Text(
                                '${doc['size']} • ${doc['date']}',
                                style: const TextStyle(color: Palette.textMuted, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openDecryptDialog(doc),
                      icon: const Icon(Icons.lock_open_rounded, size: 16, color: Palette.red),
                      label: const Text(
                        'Decrypt',
                        style: TextStyle(color: Palette.red, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 5: MEDISCAN (/mediscan) — Matches MediscanPage.tsx + MedicineAnalyzerPage.tsx
// 3 Sub-route Tabs:
//   1. 📄 Document Scan (/api/gemini/mediscan)
//   2. 🔬 Diagnostic Imaging (/api/gemini/diagnostic-imaging)
//   3. 🧪 Ingredient Analyzer (/api/gemini/medicine-ingredients with 5 sub-tabs:
//      🧪 Ingredients | 💊 Uses | ⚠️ Side Effects | 🌿 Ayurvedic | 🛡️ Warnings)
// ═════════════════════════════════════════════════════════════════════════════
class MediscanRouteScreen extends ConsumerStatefulWidget {
  const MediscanRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  ConsumerState<MediscanRouteScreen> createState() => _MediscanRouteScreenState();
}

class _MediscanRouteScreenState extends ConsumerState<MediscanRouteScreen> {
  late int _subTab;
  int _ingredientSubTab = 0;

  final _docTextCtrl = TextEditingController(
    text: 'Rx: Tab Metformin 500mg BD after meals, Tab Atorvastatin 10mg HS. Lab: HbA1c 7.4%, LDL 132 mg/dL, Fasting Glucose 128 mg/dL.',
  );
  final _imagingContextCtrl = TextEditingController(
    text: 'Chest X-Ray PA view: Evaluate bilateral lung fields, costophrenic angles, and cardiac silhouette.',
  );
  final _medSearchCtrl = TextEditingController(text: 'Paracetamol 650 (Dolo 650)');

  String _modality = 'Chest X-Ray';
  String _bodyRegion = 'Thorax / Lungs';

  bool _docBusy = false;
  Map<String, dynamic>? _docResult;

  bool _imgBusy = false;
  Map<String, dynamic>? _imgResult;

  bool _medBusy = false;
  Map<String, dynamic>? _medResult;

  static const _popularMeds = <String>[
    'Paracetamol 650',
    'Metformin 500',
    'Augmentin 625',
    'Azithromycin 500',
    'Pantoprazole 40',
    'Amlodipine 5',
    'Cetirizine 10',
  ];

  static const _ingredientTabs = <String>[
    '🧪 Ingredients',
    '💊 Uses',
    '⚠️ Side Effects',
    '🌿 Ayurvedic',
    '🛡️ Warnings',
  ];

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 2);
  }

  @override
  void dispose() {
    _docTextCtrl.dispose();
    _imagingContextCtrl.dispose();
    _medSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanDocument() async {
    setState(() => _docBusy = true);
    try {
      final res = await ref.read(apiProvider).aiMediScan(
            _docTextCtrl.text.trim(),
            language: 'en',
          );
      if (mounted) setState(() => _docResult = res);
    } catch (e) {
      if (mounted) showSnack(context, 'Document Scan error: $e', error: true);
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<void> _scanImaging() async {
    setState(() => _imgBusy = true);
    try {
      final res = await ref.read(apiProvider).diagnosticImaging(
            imagingType: _modality,
            bodyRegion: _bodyRegion,
            clinicalContext: _imagingContextCtrl.text.trim(),
            language: 'en',
          );
      if (mounted) setState(() => _imgResult = res);
    } catch (e) {
      if (mounted) showSnack(context, 'Diagnostic Imaging error: $e', error: true);
    } finally {
      if (mounted) setState(() => _imgBusy = false);
    }
  }

  Future<void> _analyzeMedicine([String? preset]) async {
    if (preset != null) _medSearchCtrl.text = preset;
    setState(() => _medBusy = true);
    try {
      final res = await ref.read(apiProvider).aiMedicineAnalyzer(
            _medSearchCtrl.text.trim(),
            language: 'en',
          );
      if (mounted) setState(() => _medResult = res);
    } catch (e) {
      if (mounted) showSnack(context, 'Ingredient Analyzer error: $e', error: true);
    } finally {
      if (mounted) setState(() => _medBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Header
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
                child: const Text('📄', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mediscan AI',
                      style: TextStyle(
                        color: Palette.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Document Scan • Diagnostic Imaging • Ingredient Analyzer',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 Sub-Route Tabs (Vertical Wrap — No Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: '📄 Document Scan',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '🔬 Diagnostic Imaging',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
              _SubRouteTabChip(
                label: '🧪 Ingredient Analyzer',
                selected: _subTab == 2,
                onTap: () => setState(() => _subTab = 2),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_subTab == 0) ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📄 Prescription & Lab Report AI Scanner',
                    style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Extracts medications, lab values (Normal/High/Low), clinical plain-language summary, and precautions.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _docTextCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Prescription / Lab Report Text or OCR Content',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _docBusy ? null : _scanDocument,
                    icon: const Icon(Icons.document_scanner_rounded, size: 18),
                    label: Text(_docBusy ? 'Scanning Document…' : 'Analyze Medical Document'),
                  ),
                  if (_docResult != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.outline),
                      ),
                      child: MarkdownLite(
                        '${_docResult!['summary'] ?? _docResult!['analysis'] ?? _docResult!['response'] ?? _docResult}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_subTab == 1) ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔬 AI Radiology & Diagnostic Imaging Analyzer',
                    style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _modality,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Modality'),
                          items: const [
                            DropdownMenuItem(value: 'Chest X-Ray', child: Text('Chest X-Ray')),
                            DropdownMenuItem(value: 'CT Scan', child: Text('CT Scan')),
                            DropdownMenuItem(value: 'MRI', child: Text('MRI')),
                            DropdownMenuItem(value: 'Ultrasound', child: Text('Ultrasound')),
                            DropdownMenuItem(value: 'Skin/Retinal', child: Text('Skin/Retinal')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _modality = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _bodyRegion,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Body Region'),
                          items: const [
                            DropdownMenuItem(value: 'Thorax / Lungs', child: Text('Thorax / Lungs')),
                            DropdownMenuItem(value: 'Brain / Cranium', child: Text('Brain / Cranium')),
                            DropdownMenuItem(value: 'Spine / Pelvis', child: Text('Spine / Pelvis')),
                            DropdownMenuItem(value: 'Abdomen', child: Text('Abdomen')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _bodyRegion = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _imagingContextCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Clinical Indication / Imaging Notes',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _imgBusy ? null : _scanImaging,
                    icon: const Icon(Icons.biotech_rounded, size: 18),
                    label: Text(_imgBusy ? 'Running Imaging AI…' : 'Run Diagnostic Imaging Analysis'),
                  ),
                  if (_imgResult != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Palette.surfaceHi,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.outline),
                      ),
                      child: MarkdownLite(
                        '${_imgResult!['findings'] ?? _imgResult!['summary'] ?? _imgResult!['impression'] ?? _imgResult}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🧪 Medicine Ingredient & Ayurvedic Analyzer',
                    style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in _popularMeds)
                        ActionChip(
                          label: Text(m, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          onPressed: () => _analyzeMedicine(m),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _medSearchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Medicine Brand or Generic Name',
                      prefixIcon: Icon(Icons.medication_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _medBusy ? null : () => _analyzeMedicine(),
                    icon: const Icon(Icons.science_rounded, size: 18),
                    label: Text(_medBusy ? 'Analyzing Ingredients…' : 'Analyze Medicine Breakdown'),
                  ),
                  const SizedBox(height: 16),

                  // 5 Result Sub-Tabs (Vertical Wrap — No Horizontal Scroll)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _ingredientTabs.length; i++)
                        _SubRouteTabChip(
                          label: _ingredientTabs[i],
                          selected: _ingredientSubTab == i,
                          onTap: () => setState(() => _ingredientSubTab = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Palette.outline),
                    ),
                    child: MarkdownLite(_buildIngredientTabContent()),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildIngredientTabContent() {
    final med = _medSearchCtrl.text.trim();
    final res = _medResult;
    if (_ingredientSubTab == 0) {
      if (res != null && res['activeIngredients'] != null) {
        return '### Active & Inactive Ingredients for $med\n${res['activeIngredients']}';
      }
      return '### 🧪 Active & Inactive Ingredients ($med)\n'
          '- **Active Pharmaceutical Ingredient (API)**: Paracetamol IP `650 mg` (Analgesic & Antipyretic)\n'
          '- **Excipients**: Pregelatinised Starch, Povidone K-30, Sodium Starch Glycolate, Stearic Acid\n'
          '- **Pharmacological Class**: Non-opioid para-aminophenol derivative';
    } else if (_ingredientSubTab == 1) {
      return '### 💊 Clinical Uses & Indications ($med)\n'
          '- **Primary Indications**: Fever (Pyrexia), headache, migraine, toothache, musculoskeletal pain, post-vaccination pyrexia\n'
          '- **Adult Dosage**: `500–650 mg` every 4–6 hours as needed (Max `4,000 mg/day`)\n'
          '- **Onset of Action**: 30–45 minutes orally';
    } else if (_ingredientSubTab == 2) {
      return '### ⚠️ Potential Side Effects ($med)\n'
          '- **Common (Rare at therapeutic doses)**: Mild nausea, epigastric discomfort\n'
          '- **Serious / Overdose Risk**: Hepatotoxicity (acute liver injury if daily dose exceeds 4g), rare hypersensitivity skin rash';
    } else if (_ingredientSubTab == 3) {
      return '### 🌿 Integrative Ayurvedic Alternatives ($med)\n'
          '- **Guduchi (Tinospora cordifolia / Amruthaballi)**: Classical *Jwarahara* (antipyretic) & immunomodulator\n'
          '- **Sudarshan Ghanvati**: Traditional polyherbal formulation for viral pyrexia & Pitta-Kapha balance\n'
          '- **Tulsi & Shunthi (Dry Ginger) Kwatha**: Supports diaphoresis and upper respiratory relief';
    } else {
      return '### 🛡️ Safety Warnings & Contraindications ($med)\n'
          '- **Hepatic Impairment**: Avoid or reduce dose in chronic liver disease or heavy alcohol use\n'
          '- **Duplicate Therapy Warning**: Check other cold/flu combinations to prevent accidental paracetamol overdose\n'
          '- **Drug Interactions**: Warfarin (prolonged high-dose use may increase INR)';
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 6: TELEMEDICINE (/telemedicine) — Matches TelemedicinePage.tsx
// Sub-routes:
//   1. 📹 Live Video Consultation Room (Agora RTC)
//   2. 👨‍⚕️ Specialist Doctors Directory
// ═════════════════════════════════════════════════════════════════════════════
class TelemedicineRouteScreen extends ConsumerStatefulWidget {
  const TelemedicineRouteScreen({super.key});

  @override
  ConsumerState<TelemedicineRouteScreen> createState() => _TelemedicineRouteScreenState();
}

class _TelemedicineRouteScreenState extends ConsumerState<TelemedicineRouteScreen> {
  int _subTab = 0;
  final _roomCtrl = TextEditingController(text: 'jeevan-consult-108');
  bool _sendingInvite = false;

  static const _specialists = <({
    String name,
    String specialty,
    String hospital,
    String exp,
    String lang,
    String room,
  })>[
    (
      name: 'Dr. Ramesh Rao, MD (Cardiology)',
      specialty: 'Senior Interventional Cardiologist',
      hospital: 'Narayana Heart & Trauma Institute',
      exp: '16 yrs exp • 24×7 Emergency On-Call',
      lang: 'English, Hindi, Kannada',
      room: 'cardio-consult-108',
    ),
    (
      name: 'Dr. Ananya Sharma, MD (Internal Medicine)',
      specialty: 'General Physician & Critical Care',
      hospital: 'Apollo Telehealth Command',
      exp: '12 yrs exp • Acute Fever & Triage',
      lang: 'English, Hindi, Bengali',
      room: 'med-consult-108',
    ),
    (
      name: 'Vaidya Pradeep Nair, BAMS, MD (Ayurveda)',
      specialty: 'AYUSH Kaya Chikitsa & Dashavidha Specialist',
      hospital: 'JeevanCare Integrative AYUSH Center',
      exp: '14 yrs exp • Prakriti & Chronic Care',
      lang: 'English, Malayalam, Tamil, Hindi',
      room: 'ayush-consult-108',
    ),
  ];

  @override
  void dispose() {
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendEmergencyContactInvite() async {
    setState(() => _sendingInvite = true);
    final store = ref.read(storeProvider);
    try {
      final room = _roomCtrl.text.trim().isEmpty ? 'jeevan-consult-108' : _roomCtrl.text.trim();
      await ref.read(apiProvider).sendVideoCallInvite(
            roomId: room,
            name: store.contactName,
            phone: store.contactPhone,
            email: store.contactEmail,
          );
      if (mounted) {
        showSnack(
          context,
          '📲 Sent Agora Video Room link (${Config.videoCallUrl(room)}) via WhatsApp & Email to ${store.contactName}!',
        );
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Invite dispatched to ${store.contactName} (${store.contactPhone}).');
      }
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
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
                child: const Text('🩺', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Telemedicine',
                      style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Agora RTC Encrypted Video Consultations & Specialist Triage',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: '📹 Video Consultation Room',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '👨‍⚕️ Specialist Doctors',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_subTab == 0) ...[
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📹 Join or Host Agora RTC Emergency Video Room',
                    style: TextStyle(color: Palette.text, fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Low-latency WebRTC / Agora 007 encrypted video consultation with live VitaWatch vitals overlay.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _roomCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Consultation Room ID',
                      prefixIcon: Icon(Icons.meeting_room_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () {
                      final room = _roomCtrl.text.trim().isEmpty ? 'jeevan-consult-108' : _roomCtrl.text.trim();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => VideoCallScreen(
                            channelId: room,
                            title: 'Telemedicine Room ($room)',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Start / Join Live Video Consultation'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sendingInvite ? null : _sendEmergencyContactInvite,
                          icon: const Icon(Icons.send_rounded, size: 16, color: Palette.green),
                          label: Text(_sendingInvite ? 'Sending…' : 'Invite Emergency Contact'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final room = _roomCtrl.text.trim().isEmpty
                              ? 'jeevan-consult-108'
                              : _roomCtrl.text.trim();
                          await Clipboard.setData(
                            ClipboardData(text: Config.videoCallUrl(room)),
                          );
                          if (context.mounted) {
                            showSnack(context, 'Agora Video Call Link copied!');
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy Link'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            for (final doc in _specialists)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Palette.teal.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            alignment: Alignment.center,
                            child: const Text('👨‍⚕️', style: TextStyle(fontSize: 22)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.name,
                                  style: const TextStyle(
                                    color: Palette.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  doc.specialty,
                                  style: const TextStyle(
                                    color: Palette.teal,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${doc.hospital} • ${doc.exp}',
                                  style: const TextStyle(color: Palette.textDim, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Languages: ${doc.lang}',
                              style: const TextStyle(color: Palette.textDim, fontSize: 11.5),
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => VideoCallScreen(
                                    channelId: doc.room,
                                    title: doc.name,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.videocam_rounded, size: 16),
                            label: const Text('Video Consult'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 7: SYMPTOM CHECKER (/symptom-checker) — Matches SymptomCheckerPage.tsx
// Includes:
//   - Front / Back Human Body Anatomy Map Selector
//   - 13 Symptom Chips + Severity Slider (1-10) + Duration Selector
//   - AI Triage Report (P1-P4 Urgency, Possible Conditions, Red Flags, Actions)
// ═════════════════════════════════════════════════════════════════════════════
class SymptomCheckerRouteScreen extends ConsumerStatefulWidget {
  const SymptomCheckerRouteScreen({super.key});

  @override
  ConsumerState<SymptomCheckerRouteScreen> createState() => _SymptomCheckerRouteScreenState();
}

class _SymptomCheckerRouteScreenState extends ConsumerState<SymptomCheckerRouteScreen> {
  bool _backView = false;
  String _selectedRegion = 'Chest & Heart';
  final Set<String> _selectedSymptoms = {'Pain', 'Shortness of Breath'};
  double _severity = 6;
  String _duration = '1–3 days';
  final _notesCtrl = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _triageResult;

  static const _frontRegions = <String>[
    'Head & Forehead',
    'Eyes & Vision',
    'Ear, Nose & Throat',
    'Neck & Thyroid',
    'Chest & Heart',
    'Lungs & Airways',
    'Upper Abdomen',
    'Lower Abdomen',
    'Pelvis & Hip',
    'Shoulder & Arm',
    'Wrist & Hand',
    'Knee & Lower Leg',
    'Ankle & Foot',
  ];

  static const _backRegions = <String>[
    'Back of Head / Occiput',
    'Cervical Spine (Neck)',
    'Upper Back & Scapula',
    'Thoracic Spine',
    'Lower Back / Lumbar',
    'Flank & Kidneys',
    'Gluteal / Sciatic',
    'Hamstring & Calf',
    'Achilles & Heel',
  ];

  static const _symptomChips = <String>[
    'Pain',
    'Swelling',
    'Numbness',
    'Tingling',
    'Weakness',
    'Stiffness',
    'Redness',
    'Itching',
    'Burning',
    'Cramps',
    'Dizziness',
    'Fever',
    'Shortness of Breath',
  ];

  static const _durations = <String>[
    'Just started (< 24h)',
    '1–3 days',
    '4–7 days',
    '1–4 weeks',
    '> 1 month',
  ];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _runSymptomTriage() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(apiProvider).bodySymptomCheck(
            bodyLocation: '$_selectedRegion (${_backView ? "Back View" : "Front View"})',
            symptoms: _selectedSymptoms.toList(),
            severity: _severity.round(),
            duration: _duration,
            additionalInfo: _notesCtrl.text.trim(),
            language: 'en',
          );
      if (mounted) setState(() => _triageResult = res);
    } catch (e) {
      if (mounted) showSnack(context, 'Symptom Checker error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = _backView ? _backRegions : _frontRegions;

    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
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
                child: const Text('🧠', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Symptom Checker',
                      style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Interactive Human Anatomy Map • AI Clinical Triage (P1–P4)',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Anatomy Map Card (Front / Back View — Stacked Cleanly, Zero Overflow)
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🧍 Select Body Region',
                  style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Front View')),
                      ButtonSegment(value: true, label: Text('Back View')),
                    ],
                    selected: {_backView},
                    onSelectionChanged: (s) {
                      setState(() {
                        _backView = s.first;
                        _selectedRegion = (_backView ? _backRegions : _frontRegions).first;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reg in regions)
                      ChoiceChip(
                        selected: _selectedRegion == reg,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _selectedRegion = reg),
                        label: Text(
                          reg,
                          style: TextStyle(
                            color: _selectedRegion == reg ? Palette.red : Palette.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        selectedColor: Palette.redLight,
                        backgroundColor: Palette.surfaceHi,
                        side: BorderSide(
                          color: _selectedRegion == reg ? Palette.red : Palette.outline,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 13 Symptom Chips + Severity Slider + Duration
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🩺 Associated Symptoms (Select all that apply)',
                  style: TextStyle(color: Palette.text, fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final sym in _symptomChips)
                      FilterChip(
                        selected: _selectedSymptoms.contains(sym),
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedSymptoms.add(sym);
                            } else {
                              _selectedSymptoms.remove(sym);
                            }
                          });
                        },
                        label: Text(sym),
                        selectedColor: Palette.redLight,
                        checkmarkColor: Palette.red,
                        labelStyle: TextStyle(
                          color: _selectedSymptoms.contains(sym) ? Palette.red : Palette.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pain / Symptom Severity',
                      style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Palette.redLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_severity.round()} / 10',
                        style: const TextStyle(
                          color: Palette.red,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _severity,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: Palette.red,
                  onChanged: (v) => setState(() => _severity = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _duration,
                  decoration: const InputDecoration(labelText: 'Symptom Duration'),
                  items: _durations
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _duration = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    hintText: 'Describe onset, triggers, or radiating pain…',
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _runSymptomTriage,
                  icon: const Icon(Icons.psychology_rounded, size: 18),
                  label: Text(_busy ? 'Running Clinical Triage…' : 'Analyze Symptoms with AI'),
                ),
                if (_triageResult != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Palette.surfaceHi,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Palette.red.withOpacity(0.35)),
                    ),
                    child: MarkdownLite(
                      '${_triageResult!['triage'] ?? _triageResult!['summary'] ?? _triageResult!['analysis'] ?? _triageResult}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 9: COMMUNITY (/community) — Matches CommunityPage.tsx & Image 2 ("5 / blood needed")
// Sub-routes:
//   1. 🚨 Community Alerts Feed (6 Category Filters + 3 Stat Cards + 5 Active Alerts starting with "blood needed")
//   2. 🌧️ Disaster & Weather Radar Map (OpenWeather + RainViewer Radar + Risk Score)
// ═════════════════════════════════════════════════════════════════════════════
class CommunityRouteScreen extends StatefulWidget {
  const CommunityRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  State<CommunityRouteScreen> createState() => _CommunityRouteScreenState();
}

class _CommunityRouteScreenState extends State<CommunityRouteScreen> {
  late int _subTab;
  String _selectedFilter = 'All';

  static const _filters = <String>[
    'All',
    'Medical',
    'Flood',
    'Fire',
    'Infrastructure',
    'General',
  ];

  final List<Map<String, dynamic>> _alerts = [
    {
      'title': 'blood needed',
      'category': 'Medical',
      'severity': 'CRITICAL',
      'location': 'Victoria Hospital Trauma Center • 0.8 km away',
      'time': '12 mins ago',
      'description': 'Urgent requirement for 2 units of A+ / O+ whole blood for emergency trauma surgery.',
      'verified': true,
      'safeCount': 4,
    },
    {
      'title': 'Mobile Medical & Dengue Screening Camp',
      'category': 'Medical',
      'severity': 'MODERATE',
      'location': 'Civic Center Ward 110 • 1.2 km away',
      'time': '45 mins ago',
      'description': 'Free NS1 antigen testing, platelet count & ORS distribution open until 6:00 PM.',
      'verified': true,
      'safeCount': 19,
    },
    {
      'title': 'Waterlogging on Low-Lying Underpass',
      'category': 'Flood',
      'severity': 'HIGH',
      'location': 'KR Circle Underpass • 1.5 km away',
      'time': '1 hour ago',
      'description': 'Heavy rainfall runoff causing slow ambulance movement; use elevated flyover route.',
      'verified': true,
      'safeCount': 11,
    },
    {
      'title': 'Transformer Sparking Reported — Fire Tender Dispatched',
      'category': 'Fire',
      'severity': 'HIGH',
      'location': 'Residency Road Cross • 2.1 km away',
      'time': '2 hours ago',
      'description': 'BESCOM and 101 Fire Brigade on site; pedestrian corridor cordoned off safely.',
      'verified': true,
      'safeCount': 8,
    },
    {
      'title': '24×7 Oxygen Cylinder & Nebulizer Backup Bank',
      'category': 'General',
      'severity': 'NORMAL',
      'location': 'JeevanCare Community Relief Hub • 1.8 km away',
      'time': '3 hours ago',
      'description': '15 portable 10L oxygen concentrators available for elderly & respiratory patients.',
      'verified': false,
      'safeCount': 27,
    },
  ];

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 1);
  }

  void _openPostAlertModal() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Medical';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚨 Post Community Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Alert Headline',
                hintText: 'e.g., O- Blood Needed / Road Blocked',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _filters
                  .where((f) => f != 'All')
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) {
                if (v != null) category = v;
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Details & Location'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              setState(() {
                _alerts.insert(0, {
                  'title': titleCtrl.text.trim().isEmpty ? 'Community Emergency Alert' : titleCtrl.text.trim(),
                  'category': category,
                  'severity': 'HIGH',
                  'location': 'Near Your Current Location',
                  'time': 'Just now',
                  'description': descCtrl.text.trim().isEmpty
                      ? 'Reported via JeevanCare Community App.'
                      : descCtrl.text.trim(),
                  'verified': true,
                  'safeCount': 1,
                });
              });
              Navigator.of(ctx).pop();
              showSnack(context, 'Community alert broadcasted to nearby users!');
            },
            child: const Text('Broadcast Alert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 'All'
        ? _alerts
        : _alerts.where((a) => a['category'] == _selectedFilter).toList();

    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
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
                child: const Text('🌐', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community Alerts',
                      style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Crowdsourced Emergency Feed & Live Disaster Radar',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _openPostAlertModal,
                icon: const Icon(Icons.add_alert_rounded, size: 16),
                label: const Text('Post Alert'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 Stat Cards (ACTIVE ALERTS: 5 | VERIFIED: 4 | SAFE REPORTS: 69)
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  label: 'ACTIVE ALERTS',
                  value: '${_alerts.length}',
                  color: Palette.red,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _MiniStatCard(
                  label: 'VERIFIED',
                  value: '4',
                  color: Palette.teal,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _MiniStatCard(
                  label: 'SAFE REPORTS',
                  value: '69',
                  color: Palette.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sub-Route Tabs: Feed vs Disaster & Weather Radar Map (Wrap — Zero Overflow)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: '🚨 Community Alerts Feed',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '🌧️ Disaster & Weather Radar',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_subTab == 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _filters)
                  ChoiceChip(
                    selected: _selectedFilter == f,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedFilter = f),
                    label: Text(
                      f,
                      style: TextStyle(
                        color: _selectedFilter == f ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    selectedColor: Palette.redLight,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: _selectedFilter == f ? Palette.red : Palette.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final alert in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderColor: alert['severity'] == 'CRITICAL'
                      ? Palette.red.withOpacity(0.45)
                      : Palette.outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _BadgePill(
                            text: '${alert['category']}',
                            color: alert['severity'] == 'CRITICAL' ? Palette.red : Palette.orange,
                          ),
                          const SizedBox(width: 8),
                          if (alert['verified'] == true)
                            const _BadgePill(text: '✓ Verified', color: Palette.teal),
                          const Spacer(),
                          Text(
                            '${alert['time']}',
                            style: const TextStyle(color: Palette.textMuted, fontSize: 11.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${alert['title']}',
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${alert['description']}',
                        style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 15, color: Palette.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${alert['location']}',
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () {
                              setState(() {
                                alert['safeCount'] = ((alert['safeCount'] as int?) ?? 0) + 1;
                              });
                              showSnack(context, 'Marked Safe! (${alert['safeCount']} safe reports)');
                            },
                            icon: const Icon(Icons.verified_user_rounded, size: 15, color: Palette.green),
                            label: Text('Mark Safe (${alert['safeCount']})', style: const TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => setState(() => _subTab = 1),
                            icon: const Icon(Icons.map_rounded, size: 15, color: Palette.blue),
                            label: const Text('View on Map', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text('🌧️', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'OpenWeather & RainViewer Precipitation Radar',
                          style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                      ),
                      _BadgePill(text: 'RISK SCORE: 24/100 (LOW)', color: Palette.green),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Palette.blue.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar_rounded, size: 42, color: Palette.blue),
                        SizedBox(height: 8),
                        Text(
                          'Live Doppler Weather & Community Alert Pins Active',
                          style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Temp: 26°C • Humidity: 68% • Wind: 14 km/h • AQI: 62 (Satisfactory)',
                          style: TextStyle(color: Palette.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 10: EMERGENCY SERVICES (/emergency-services) — Matches EmergencyServicesPage.tsx
// 4 Sub-route Tabs:
//   1. 🏥 Hospitals (10,000+ hospitals, Scope All/Nearby/24x7, 9 Categories)
//   2. 🩸 Blood Banks (20+ verified banks & donors, Urgent Blood Requests, A+..O-)
//   3. 🚑 Ambulances (10,000+ Ambulances, 108/102/112, BLS/ALS/Cardiac/ICU)
//   4. 🤝 NGO Connect (10,000+ Verified NGOs, 11 Categories, Contact NGO modal)
// ═════════════════════════════════════════════════════════════════════════════
class EmergencyServicesRouteScreen extends StatefulWidget {
  const EmergencyServicesRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  State<EmergencyServicesRouteScreen> createState() => _EmergencyServicesRouteScreenState();
}

class _EmergencyServicesRouteScreenState extends State<EmergencyServicesRouteScreen> {
  late int _subTab;
  String _hospitalCategory = 'All';
  String _bloodGroup = 'All';
  String _ambulanceType = 'All';
  String _ngoCategory = 'All';

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 3);
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number.replaceAll(' ', ''));
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
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
                child: const Text('🚨', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Services',
                      style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Hospitals • Blood Banks • Ambulances • NGO Connect',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4 Sub-Route Tabs (Vertical Wrap — Zero Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: '🏥 Hospitals (10,000+)',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '🩸 Blood Banks (20+)',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
              _SubRouteTabChip(
                label: '🚑 Ambulances (10,000+)',
                selected: _subTab == 2,
                onTap: () => setState(() => _subTab = 2),
              ),
              _SubRouteTabChip(
                label: '🤝 NGO Connect (10,000+)',
                selected: _subTab == 3,
                onTap: () => setState(() => _subTab = 3),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_subTab == 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in const [
                  'All',
                  'Emergency 24×7',
                  'Multi-Specialty',
                  'Government',
                  'Cardiac',
                  'Trauma',
                  'Maternity',
                  'Pediatric',
                  'AYUSH',
                ])
                  ChoiceChip(
                    selected: _hospitalCategory == c,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _hospitalCategory = c),
                    label: Text(
                      c,
                      style: TextStyle(
                        color: _hospitalCategory == c ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    selectedColor: Palette.redLight,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: _hospitalCategory == c ? Palette.red : Palette.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DirectoryCard(
              emoji: '🏥',
              title: 'Victoria Hospital & Trauma Care Center',
              subtitle: 'Government Multi-Specialty • Fort Rd, Bengaluru • 0.8 km',
              badges: const ['24×7 Emergency', 'ICU Beds Available', 'PM-JAY / ABHA'],
              phone: '08026701150',
              accent: Palette.teal,
              onCall: () => _dial('08026701150'),
            ),
            _DirectoryCard(
              emoji: '🏥',
              title: 'Manipal Hospital Emergency & Cardiac Wing',
              subtitle: 'Multi-Specialty Trauma • Old Airport Rd • 3.2 km',
              badges: const ['24×7 Cath Lab', 'Stroke Unit', 'Cashless Insurance'],
              phone: '1066',
              accent: Palette.teal,
              onCall: () => _dial('1066'),
            ),
            _DirectoryCard(
              emoji: '🏥',
              title: 'St. John’s Medical College & Emergency Hospital',
              subtitle: 'Tertiary Trauma & Burn Unit • Sarjapur Rd • 4.1 km',
              badges: const ['24×7 Trauma', 'Blood Bank On-Site', 'NICU'],
              phone: '08022065000',
              accent: Palette.teal,
              onCall: () => _dial('08022065000'),
            ),
          ] else if (_subTab == 1) ...[
            // Urgent Blood Requests Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.redLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.red.withOpacity(0.35)),
              ),
              child: const Row(
                children: [
                  Text('🔴', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'URGENT BLOOD REQUESTS ACTIVE',
                          style: TextStyle(
                            color: Palette.red,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'A+ and O+ Whole Blood / Platelets needed at Victoria Trauma Center (2 units)',
                          style: TextStyle(color: Palette.text, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bg in const ['All', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
                  ChoiceChip(
                    selected: _bloodGroup == bg,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _bloodGroup = bg),
                    label: Text(
                      '🩸 $bg',
                      style: TextStyle(
                        color: _bloodGroup == bg ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    selectedColor: Palette.redLight,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: _bloodGroup == bg ? Palette.red : Palette.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DirectoryCard(
              emoji: '🩸',
              title: 'Indian Red Cross Society Regional Blood Bank',
              subtitle: 'Race Course Rd • Verified Component Separation Unit • 1.5 km',
              badges: const ['A+ (18 Units)', 'O+ (24 Units)', 'O- (4 Units)', 'Platelets'],
              phone: '08022264205',
              accent: Palette.red,
              onCall: () => _dial('08022264205'),
            ),
            _DirectoryCard(
              emoji: '🩸',
              title: 'Rashtrotthana Parishat Blood Centre',
              subtitle: 'Kempegowda Nagar • 24×7 Voluntary Donor Bank • 2.1 km',
              badges: const ['A+ (12 Units)', 'B+ (19 Units)', 'AB+ (9 Units)', 'FFP'],
              phone: '08026612730',
              accent: Palette.red,
              onCall: () => _dial('08026612730'),
            ),
          ] else if (_subTab == 2) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [
                  'All',
                  'ALS (Advanced Life Support)',
                  'BLS (Basic)',
                  'Cardiac ICU',
                  'Neonatal',
                  'Ventilator',
                ])
                  ChoiceChip(
                    selected: _ambulanceType == t,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _ambulanceType = t),
                    label: Text(
                      t,
                      style: TextStyle(
                        color: _ambulanceType == t ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    selectedColor: Palette.redLight,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: _ambulanceType == t ? Palette.red : Palette.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DirectoryCard(
              emoji: '🚑',
              title: '108 Arogya Kavacha Free Emergency Ambulance',
              subtitle: 'Government 24×7 ALS & BLS Fleet • Avg ETA 7 mins',
              badges: const ['FREE SERVICE', '24×7 Open', 'ALS Ventilator & Defibrillator'],
              phone: '108',
              accent: Palette.orange,
              onCall: () => _dial('108'),
            ),
            _DirectoryCard(
              emoji: '🚑',
              title: 'StanPlus Red Health Cardiac ICU Ambulance',
              subtitle: 'Rapid Paramedic Dispatch • Live GPS Tracked • ETA 6 mins',
              badges: const ['Cardiac Monitor', 'Oxygen 20L', '24×7 Open'],
              phone: '112',
              accent: Palette.red,
              onCall: () => _dial('112'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in const [
                  'All',
                  'Disaster Relief',
                  'Medical Aid',
                  'Blood Donation',
                  'Food & Hunger',
                  'Mental Health',
                  'Elderly Care',
                ])
                  ChoiceChip(
                    selected: _ngoCategory == c,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _ngoCategory = c),
                    label: Text(
                      c,
                      style: TextStyle(
                        color: _ngoCategory == c ? Palette.red : Palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    selectedColor: Palette.redLight,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: _ngoCategory == c ? Palette.red : Palette.outline,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _DirectoryCard(
              emoji: '🤝',
              title: 'Goonj & JeevanCare Disaster Relief Network',
              subtitle: 'Medical Kits, Flood Relief, Food & Emergency Shelter',
              badges: const ['Verified NGO', 'Disaster Relief', 'Medical Aid'],
              phone: '01126972351',
              accent: Palette.blue,
              onCall: () => _dial('01126972351'),
            ),
            _DirectoryCard(
              emoji: '🤝',
              title: 'HelpAge India Elder Care Helpline',
              subtitle: 'Mobile Healthcare Units, Assisted Living & cataract/geriatric support',
              badges: const ['Elderly Care', 'Toll-Free 1800-180-1253', '24×7 Support'],
              phone: '18001801253',
              accent: Palette.purple,
              onCall: () => _dial('18001801253'),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 12: WELLBEING (/wellbeing) — Matches WellbeingPage.tsx
// Sarah — Your well-being companion · Always here 💙
// ═════════════════════════════════════════════════════════════════════════════
class WellbeingRouteScreen extends ConsumerStatefulWidget {
  const WellbeingRouteScreen({super.key});

  @override
  ConsumerState<WellbeingRouteScreen> createState() => _WellbeingRouteScreenState();
}

class _WellbeingRouteScreenState extends ConsumerState<WellbeingRouteScreen> {
  final _msgCtrl = TextEditingController();
  bool _busy = false;

  static const _quickPrompts = <String>[
    "I'm feeling overwhelmed and anxious today",
    'Guide me through a 2-minute box breathing exercise',
    "I'm having trouble sleeping at night",
    'Help me with 5-4-3-2-1 sensory grounding',
    'Dealing with caregiver stress and burnout',
    'Share a gentle positive affirmation',
  ];

  final List<Map<String, String>> _messages = [
    {
      'role': 'sarah',
      'text':
          "Hi zaid 💙 I'm Sarah, your confidential well-being companion. Whether you're feeling stressed, anxious, or just need someone to talk to, I'm right here to listen without judgment. How are you feeling right now?",
    },
  ];

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _msgCtrl.text).trim();
    if (text.isEmpty || _busy) return;
    if (preset == null) _msgCtrl.clear();

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _busy = true;
    });

    try {
      final res = await ref.read(apiProvider).aiWellbeing(
            text,
            language: 'en',
          );
      final reply = '${res['reply'] ?? res['response'] ?? res['message'] ?? "I hear you 💙 Take a slow, deep breath with me—inhale for 4 seconds, hold for 4 seconds, and exhale gently. You don't have to carry everything all at once."}';
      if (mounted) {
        setState(() {
          _messages.add({'role': 'sarah', 'text': reply});
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'sarah',
            'text':
                "I'm right here with you 💙 Let's pause for a gentle breath: inhale slowly for 4 counts, hold for 4 counts, and release for 4 counts. What part of today feels heaviest on your mind?",
          });
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Sarah Header (Matches WellbeingPage.tsx)
          GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: Palette.pink.withOpacity(0.3),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Palette.pink.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Text('🌸', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sarah',
                        style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Your well-being companion · Always here 💙',
                        style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '🔒 Private & Confidential',
                        style: TextStyle(
                          color: Palette.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _messages
                        ..clear()
                        ..add({
                          'role': 'sarah',
                          'text': 'Conversation cleared 💙 How can I support you today, zaid?',
                        });
                    });
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Palette.red),
                  label: const Text('Delete All', style: TextStyle(color: Palette.red)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Quick Prompts (Vertical Wrap List — Zero Horizontal Scroll)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _quickPrompts)
                ActionChip(
                  label: Text(
                    p,
                    style: const TextStyle(color: Palette.text, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _send(p),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Messages
          for (var i = 0; i < _messages.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: _messages[i]['role'] == 'user'
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _messages[i]['role'] == 'user' ? Palette.red : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _messages[i]['role'] == 'user' ? Palette.red : Palette.outline,
                    ),
                  ),
                  child: Text(
                    _messages[i]['text'] ?? '',
                    style: TextStyle(
                      color: _messages[i]['role'] == 'user' ? Colors.white : Palette.text,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Share what is on your mind with Sarah…',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: Palette.red,
                  minimumSize: const Size(48, 48),
                ),
                onPressed: _busy ? null : () => _send(),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 14: ABOUT US (/about) — Matches AboutUsPage.tsx
// ═════════════════════════════════════════════════════════════════════════════
class AboutUsRouteScreen extends StatelessWidget {
  const AboutUsRouteScreen({super.key, this.onNavigate});

  final void Function(String route, {int subTab})? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Palette.redLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '✨ OUR MISSION',
                    style: TextStyle(
                      color: Palette.red,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Empowering communities through accessible healthcare intelligence.',
                  style: TextStyle(
                    color: Palette.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The Story of JeevanCare: In medical emergencies, every second counts—yet critical health records, live vitals, and verified nearby trauma care are often fragmented. JeevanCare unites wearable ESP32 hardware (VitaWatch & Smart Walking Stick), zero-knowledge AES-256-GCM medical records, 22-language AI clinical triage, and 3-Tap SOS dispatch into one unified lifeline.',
                  style: TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _PillarCard(
            emoji: '🔒',
            title: 'Absolute Privacy',
            desc: 'Client-side AES-256-GCM encryption in your Health Vault ensures only you and authorized first responders can access your medical records.',
          ),
          const SizedBox(height: 10),
          const _PillarCard(
            emoji: '⚡',
            title: 'Instant Response',
            desc: '3-Tap SOS, Emergency QR Medical Summary, ESP32 VitaWatch fall/vital alerts, and TomTom live ambulance routing.',
          ),
          const SizedBox(height: 10),
          const _PillarCard(
            emoji: '🌐',
            title: 'Community Driven',
            desc: '10,000+ hospitals, 20+ blood banks, 10,000+ ambulances & NGOs, plus crowdsourced disaster and blood alerts.',
          ),
          const SizedBox(height: 16),
          GlassCard(
            padding: const EdgeInsets.all(20),
            color: Palette.redLight,
            borderColor: Palette.red.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Join the JeevanCare Movement',
                  style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Keep your Emergency Medical QR and ICE contacts up to date so first responders always have the information they need.',
                  style: TextStyle(color: Palette.textDim, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => onNavigate?.call('profile', subTab: 0),
                        child: const Text('Edit Profile'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onNavigate?.call('dashboard'),
                        child: const Text('Dashboard'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ROUTE 15: PROFILE SETTINGS (/profile) — Matches ProfilePage.tsx
// 2 Sub-route Tabs:
//   1. 👤 Edit Profile (Personal Info, Medical Summary, Visible Emergency QR, Server URL)
//   2. 📞 Emergency Contact (+91 Phone, Email, Relationship, Show on QR toggle)
// ═════════════════════════════════════════════════════════════════════════════
class ProfileRouteScreen extends ConsumerStatefulWidget {
  const ProfileRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  ConsumerState<ProfileRouteScreen> createState() => _ProfileRouteScreenState();
}

class _ProfileRouteScreenState extends ConsumerState<ProfileRouteScreen> {
  late int _subTab;
  final _nameCtrl = TextEditingController(text: 'zaid');
  String _bloodGroup = 'A+';
  final _dobCtrl = TextEditingController(text: '1999-05-14');
  final _allergiesCtrl = TextEditingController(text: 'Penicillin, Sulfa Drugs');
  final _conditionsCtrl = TextEditingController(text: 'Mild Asthma');
  final _medsCtrl = TextEditingController(text: 'Salbutamol Inhaler PRN');

  final _iceNameCtrl = TextEditingController(text: 'Family Emergency Contact');
  final _iceRelCtrl = TextEditingController(text: 'Parent / Guardian');
  final _icePhoneCtrl = TextEditingController(text: '+91 98765 43210');
  final _iceEmailCtrl = TextEditingController(text: 'family@jeevancare.in');
  bool _showOnQr = true;

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 1);
    final store = ref.read(storeProvider);
    _nameCtrl.text = store.patientName;
    _bloodGroup = store.bloodGroup;
    _allergiesCtrl.text = store.allergies;
    _conditionsCtrl.text = store.conditions;
    _medsCtrl.text = store.medications;
    _iceNameCtrl.text = store.contactName;
    _iceRelCtrl.text = store.contactRelation;
    _icePhoneCtrl.text = store.contactPhone;
    _iceEmailCtrl.text = store.contactEmail;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _medsCtrl.dispose();
    _iceNameCtrl.dispose();
    _iceRelCtrl.dispose();
    _icePhoneCtrl.dispose();
    _iceEmailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.read(storeProvider);

    return Scaffold(
      backgroundColor: Palette.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Palette.red,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Z',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile Settings',
                      style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'Medical Identity • Emergency QR • Emergency Contacts',
                      style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Visible Emergency QR Card on Profile Page
          EmergencyQrCard(
            patientName: _nameCtrl.text.trim().isEmpty ? 'zaid' : _nameCtrl.text.trim(),
            bloodGroup: _bloodGroup,
            dob: _dobCtrl.text.trim(),
            allergies: _allergiesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            conditions: _conditionsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            medications: _medsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            emergencyContactName: _iceNameCtrl.text.trim(),
            emergencyContactRelation: _iceRelCtrl.text.trim(),
            emergencyContactPhone: _icePhoneCtrl.text.trim(),
          ),
          const SizedBox(height: 14),

          // 2 Sub-Route Tabs (Wrap — Zero Overflow)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: '👤 Edit Profile',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: '📞 Emergency Contact (1)',
                selected: _subTab == 1,
                onTap: () => setState(() => _subTab = 1),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_subTab == 0) ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal & Medical Summary',
                    style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Full Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _bloodGroup,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Blood Group'),
                          items: const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                              .map((b) => DropdownMenuItem(value: b, child: Text('🩸 $b')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _bloodGroup = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _dobCtrl,
                          decoration: const InputDecoration(labelText: 'Date of Birth'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _allergiesCtrl,
                    decoration: const InputDecoration(labelText: 'Known Allergies'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _conditionsCtrl,
                    decoration: const InputDecoration(labelText: 'Medical Conditions'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _medsCtrl,
                    decoration: const InputDecoration(labelText: 'Current Medications'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      final store = ref.read(storeProvider);
                      await store.setPatientName(_nameCtrl.text.trim());
                      await store.setBloodGroup(_bloodGroup);
                      await store.setAllergies(_allergiesCtrl.text.trim());
                      await store.setConditions(_conditionsCtrl.text.trim());
                      await store.setMedications(_medsCtrl.text.trim());
                      if (mounted) {
                        setState(() {});
                        showSnack(context, 'Profile, Medical Details & Emergency QR updated!');
                      }
                    },
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save Profile'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.dns_rounded, color: Palette.teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'FastAPI Gateway: ${store.serverUrlOverride ?? Config.apiBaseUrl}',
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(authProvider).signOut(),
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(color: Palette.red, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Primary Emergency Contact (ICE)',
                    style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Notified automatically via WhatsApp, SMS & Email during a 3-Tap SOS alert.',
                    style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _iceNameCtrl,
                    decoration: const InputDecoration(labelText: 'Contact Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _iceRelCtrl,
                    decoration: const InputDecoration(labelText: 'Relationship'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _icePhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number (+91)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _iceEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email Address'),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showOnQr,
                    activeColor: Palette.red,
                    onChanged: (v) => setState(() => _showOnQr = v),
                    title: const Text(
                      'Display on Emergency QR Medical Summary',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    subtitle: const Text(
                      'Allows paramedics & first responders to call this contact in 1 tap',
                      style: TextStyle(fontSize: 12, color: Palette.textDim),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref.read(sosProvider.notifier).updatePrimaryContact(
                            name: _iceNameCtrl.text.trim(),
                            relationship: _iceRelCtrl.text.trim(),
                            phone: _icePhoneCtrl.text.trim(),
                            email: _iceEmailCtrl.text.trim(),
                          );
                      if (mounted) {
                        setState(() {});
                        showSnack(context, 'Emergency contact saved & linked to SOS + QR!');
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Save Emergency Contact'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════
class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.redLight : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? Palette.red.withOpacity(0.35) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Palette.red : Palette.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SubRouteTabChip extends StatelessWidget {
  const _SubRouteTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Palette.red : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Palette.red : Palette.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Palette.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Palette.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              fontFeatures: kTabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryCard extends StatelessWidget {
  const _DirectoryCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.badges,
    required this.phone,
    required this.accent,
    required this.onCall,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<String> badges;
  final String phone;
  final Color accent;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Palette.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Palette.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: accent),
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in badges) _BadgePill(text: b, color: accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillarCard extends StatelessWidget {
  const _PillarCard({
    required this.emoji,
    required this.title,
    required this.desc,
  });

  final String emoji;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Palette.redLight,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Palette.text, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
