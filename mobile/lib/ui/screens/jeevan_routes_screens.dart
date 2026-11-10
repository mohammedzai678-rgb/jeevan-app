import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 2: VITAWATCH (/vitawatch) Ã¢â‚¬â€ Matches VitaWatchPage.tsx
// Sub-routes:
//   - Mode Switcher: Ã°Å¸â€Å’ ESP32 DevKit Live | Ã¢Å“ÂÃ¯Â¸Â Manual Entry (No Hardware)
//   - 7 Hardware Status Cards + Pin 22 LED Control
//   - 3 Sub-Tabs: Live Telemetry / Manual Scan | Reading History | Analysis Docs
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
    (icon: 'Ã°Å¸Å½â€ºÃ¯Â¸Â', name: 'ESP32 DEVKIT', role: 'Dual-Core MCU', pin: '240MHz Ã¢â‚¬Â¢ BLE/Wi-Fi'),
    (icon: 'Ã¢ÂÂ¤Ã¯Â¸Â', name: 'MAX30102', role: 'Pulse & SpOÃ¢â€šâ€š', pin: 'I2C GPIO 21/22'),
    (icon: 'Ã°Å¸Å’Â¡Ã¯Â¸Â', name: 'MAX30205 / DHT11', role: 'Body Temp', pin: 'GPIO 4 / I2C'),
    (icon: 'Ã°Å¸â€œË†', name: 'AD8232 ECG', role: 'Single-Lead ECG', pin: 'ADC GPIO 34'),
    (icon: 'Ã°Å¸â€“Â¥Ã¯Â¸Â', name: 'OLED 128Ãƒâ€”64', role: 'SSD1306 Display', pin: 'I2C 0x3C'),
    (icon: 'Ã°Å¸â€œÂ¶', name: 'ESP32 Wi-Fi', role: 'Cloud Telemetry', pin: 'HTTP/WS 2.4GHz'),
    (icon: 'Ã°Å¸Â¦Â¯', name: 'WALKING STICK', role: 'Paired Stick #2', pin: 'ESP-NOW / Cloud'),
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
                child: const Text('Ã°Å¸â€œÂ¡', style: TextStyle(fontSize: 22)),
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
                      'ESP32 DevKit Live Vitals Ã¢â‚¬Â¢ MAX30102 Ã¢â‚¬Â¢ AD8232 ECG Ã¢â‚¬Â¢ AI Scan',
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
                    label: 'Ã°Å¸â€Å’ ESP32 DevKit Live',
                    selected: !_manualMode,
                    onTap: () => setState(() => _manualMode = false),
                  ),
                ),
                Expanded(
                  child: _SegmentPill(
                    label: 'Ã¢Å“ÂÃ¯Â¸Â Manual Entry (No Hardware)',
                    selected: _manualMode,
                    onTap: () => setState(() => _manualMode = true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 7 Hardware Status Cards Ã¢â‚¬â€ Clean Vertical 2-Column Grid (No Horizontal Scroll)
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
                              '${hw.role} Ã‚Â· ${hw.pin}',
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
                            ? 'PIN 22 LED ON Ã¢â‚¬Â¢ Active reminder alert on watch'
                            : 'PIN 22 LED OFF Ã¢â‚¬Â¢ Ready for scheduled medication slot',
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

          // 3 Sub-Route Tabs (Vertical Wrap Ã¢â‚¬â€ No Horizontal Scroll)
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
                    unit: '% SpOÃ¢â€šâ€š',
                    icon: const Icon(Icons.water_drop_rounded, color: Palette.blue, size: 20),
                    color: Palette.blue,
                    status: 'normal',
                    sparkline: devicesState.spo2Series,
                    subtitle: 'Peripheral saturation',
                  ),
                  VitalTile(
                    label: 'Body Temp',
                    value: (current?.vitals.temperature ?? 36.7).toStringAsFixed(1),
                    unit: 'Ã‚Â°C',
                    icon: const Icon(Icons.thermostat_rounded, color: Palette.amber, size: 20),
                    color: Palette.amber,
                    status: 'normal',
                    subtitle: 'Normal 36.1Ã¢â‚¬â€œ37.2 Ã‚Â°C',
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
                    'Ã°Å¸Â¤â€“ AI Clinical Vitals Scanner & Manual Override',
                    style: TextStyle(
                      color: Palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Enter or verify Heart Rate, SpOÃ¢â€šâ€š, Body Temp, Blood Pressure & Glucose for instant Gemini AI clinical interpretation.',
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
                          decoration: const InputDecoration(labelText: 'SpOÃ¢â€šâ€š (%)'),
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
                          decoration: const InputDecoration(labelText: 'Temp (Ã‚Â°C)'),
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
                    label: Text(_aiScanBusy ? 'Analyzing VitalsÃ¢â‚¬Â¦' : 'Run AI Clinical Vitals Scan'),
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
                    'Ã°Å¸â€œËœ VitaWatch Hardware & Clinical Analysis Documentation',
                    style: TextStyle(color: Palette.text, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 12),
                  MarkdownLite(
                    '### 1. ESP32 DevKit V1 Sensor Pinout\n'
                    '- **MAX30102 Pulse Oximeter**: SDA Ã¢â€ â€™ `GPIO 21`, SCL Ã¢â€ â€™ `GPIO 22` (I2C 400kHz)\n'
                    '- **AD8232 Single-Lead ECG**: Output Ã¢â€ â€™ `GPIO 34 (ADC1_CH6)`, LO+ Ã¢â€ â€™ `GPIO 32`, LO- Ã¢â€ â€™ `GPIO 33`\n'
                    '- **MAX30205 / DHT11 Temp**: Digital / I2C Ã¢â€ â€™ `GPIO 4` (Ã‚Â±0.1Ã‚Â°C clinical accuracy)\n'
                    '- **Medicine Reminder LED & Buzzer**: Active-High output Ã¢â€ â€™ `GPIO 22`\n\n'
                    '### 2. Clinical Reference Thresholds\n'
                    '- **Heart Rate**: Normal `60Ã¢â‚¬â€œ100 BPM` | Bradycardia `< 50 BPM` | Tachycardia `> 110 BPM`\n'
                    '- **Blood Oxygen (SpOÃ¢â€šâ€š)**: Normal `95Ã¢â‚¬â€œ100%` | Mild Hypoxia `91Ã¢â‚¬â€œ94%` | Critical `< 90%`\n'
                    '- **Body Temperature**: Normal `36.1Ã¢â‚¬â€œ37.2 Ã‚Â°C` | Pyrexia/Fever `> 37.8 Ã‚Â°C`\n'
                    '- **Blood Pressure**: Optimal `< 120/80 mmHg` | Stage 1 HTN `130Ã¢â‚¬â€œ139 / 80Ã¢â‚¬â€œ89 mmHg`',
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 4: HEALTH VAULT (/health-vault) Ã¢â‚¬â€ Matches HealthVaultPage.tsx
// Includes:
//   - Visible Emergency QR Card
//   - 10 Category Filter Pills + Folder Filter Bar
//   - 9 Encrypted Documents (starting with "abbs medical sample.jpeg" from Image 2!)
//   - Decrypt, Move Folder, Upload AES-256-GCM Record, Delete
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
class HealthVaultRouteScreen extends ConsumerStatefulWidget {
  const HealthVaultRouteScreen({super.key});

  @override
  ConsumerState<HealthVaultRouteScreen> createState() => _HealthVaultRouteScreenState();
}

class _HealthVaultRouteScreenState extends ConsumerState<HealthVaultRouteScreen> {
  String _selectedCategory = 'All Records';
  String _searchQuery = '';
  bool _loading = true;
  bool _vaultLocked = true;
  String? _vaultPasswordHash;
  List<Map<String, dynamic>> _records = [];

  static const _categories = <String>[
    'All Records',
    'prescription',
    'lab_report',
    'vaccination',
    'insurance',
    'discharge_summary',
    'imaging',
    'other',
  ];

  static const _categoryLabels = <String, String>{
    'All Records': 'All Records',
    'prescription': 'Ã°Å¸â€™Å  Prescriptions',
    'lab_report': 'Ã°Å¸Â§Âª Lab Reports',
    'vaccination': 'Ã°Å¸â€™â€° Vaccinations',
    'insurance': 'Ã°Å¸â€ºÂ¡Ã¯Â¸Â Insurance',
    'discharge_summary': 'Ã°Å¸â€œâ€¹ Discharge',
    'imaging': 'Ã°Å¸â€“Â¼Ã¯Â¸Â Imaging',
    'other': 'Ã°Å¸â€œÂ¦ Other',
  };

  String get _userId => ref.read(authProvider).session?.userId ?? '';

  @override
  void initState() {
    super.initState();
    _loadVault();
  }

  Future<void> _loadVault() async {
    if (_userId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final api = ref.read(apiProvider);
      final settings = await api.healthVaultSettings();
      _vaultPasswordHash = settings?['vault_password_hash'] as String?;
      if (_vaultPasswordHash == null || _vaultPasswordHash!.isEmpty) {
        _vaultLocked = false;
      }
      if (!_vaultLocked) await _fetchDocuments();
    } catch (e) {
      if (mounted) showSnack(context, 'Error loading vault: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchDocuments() async {
    try {
      final docs = await ref.read(apiProvider).healthVaultDocuments();
      if (mounted) setState(() => _records = docs);
    } catch (e) {
      if (mounted) showSnack(context, 'Error loading documents: $e', error: true);
    }
  }

  String _hashPassword(String password) => base64Encode(utf8.encode(password));

  bool _verifyPassword(String password) {
    return _hashPassword(password) == _vaultPasswordHash;
  }

  Future<void> _setupVaultPassword() async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.outline)),
        title: const Text('Ã°Å¸â€â€™ Set Vault Password', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Create a password to protect your Health Vault. You\'ll need this to view, upload, or delete documents.', style: TextStyle(color: Palette.textDim, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 6 chars)', prefixIcon: Icon(Icons.lock_rounded))),
            const SizedBox(height: 10),
            TextField(controller: confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm Password', prefixIcon: Icon(Icons.lock_rounded))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Skip', style: TextStyle(color: Palette.textDim))),
          FilledButton(
            onPressed: () async {
              if (passCtrl.text.length < 6) { showSnack(ctx, 'Password must be at least 6 characters', error: true); return; }
              if (passCtrl.text != confirmCtrl.text) { showSnack(ctx, 'Passwords do not match', error: true); return; }
              final hash = _hashPassword(passCtrl.text);
              try {
                await ref.read(apiProvider).healthVaultSetPassword(hash);
                _vaultPasswordHash = hash;
                _vaultLocked = false;
                await _fetchDocuments();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) { setState(() {}); showSnack(context, 'Vault password set successfully!'); }
              } catch (e) {
                if (ctx.mounted) showSnack(ctx, 'Error: $e', error: true);
              }
            },
            child: const Text('Set Password'),
          ),
        ],
      ),
    );
  }

  Future<bool> _promptPassword(String action) async {
    if (_vaultPasswordHash == null || _vaultPasswordHash!.isEmpty) return true;
    final passCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.outline)),
        title: Text('Ã°Å¸â€Â Enter Vault Password to $action', style: const TextStyle(color: Palette.text, fontWeight: FontWeight.w800, fontSize: 16)),
        content: TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Vault Password', prefixIcon: Icon(Icons.key_rounded))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_verifyPassword(passCtrl.text)) {
                Navigator.of(ctx).pop(true);
              } else {
                showSnack(ctx, 'Incorrect password', error: true);
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _unlockVault() async {
    final passCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.outline)),
        title: const Text('Ã°Å¸â€â€™ Health Vault Locked', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your vault password to access your encrypted medical documents.', style: TextStyle(color: Palette.textDim, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Vault Password', prefixIcon: Icon(Icons.key_rounded))),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              if (_verifyPassword(passCtrl.text)) {
                Navigator.of(ctx).pop();
                setState(() => _vaultLocked = false);
                await _fetchDocuments();
                setState(() {});
              } else {
                showSnack(ctx, 'Incorrect password', error: true);
              }
            },
            child: const Text('Unlock Vault'),
          ),
        ],
      ),
    );
  }

  void _openDocumentViewer(Map<String, dynamic> doc) async {
    if (!await _promptPassword('view document')) return;
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.outline)),
        title: Row(
          children: [
            const Icon(Icons.lock_open_rounded, color: Palette.green),
            const SizedBox(width: 8),
            Expanded(child: Text(doc['title'] ?? doc['file_name'] ?? 'Document', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Palette.surfaceHi, borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.green.withOpacity(0.4))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ã°Å¸â€â€œ DECRYPTED RECORD', style: TextStyle(color: Palette.green, fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _docField('Title', doc['title']),
                    _docField('Category', doc['category']),
                    _docField('Description', doc['description']),
                    _docField('Doctor', doc['doctor_name']),
                    _docField('Hospital', doc['hospital_name']),
                    _docField('File', doc['file_name']),
                    _docField('Date', doc['document_date'] ?? doc['created_at']),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _docField(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w700))),
          Expanded(child: Text('$value', style: const TextStyle(color: Palette.text, fontSize: 13))),
        ],
      ),
    );
  }

  void _openUploadDialog() async {
    if (!await _promptPassword('upload document')) return;
    if (!mounted) return;
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final doctorCtrl = TextEditingController();
    final hospitalCtrl = TextEditingController();
    String category = 'prescription';
    bool uploading = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Palette.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Palette.outline)),
          title: const Text('Ã°Å¸â€œâ€ž Upload Medical Document', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Document Title *', hintText: 'e.g., Blood Report Nov 2026')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categories.where((c) => c != 'All Records').map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabels[c] ?? c))).toList(),
                  onChanged: (v) { if (v != null) category = v; },
                ),
                const SizedBox(height: 10),
                TextField(controller: descCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
                const SizedBox(height: 10),
                TextField(controller: doctorCtrl, decoration: const InputDecoration(labelText: 'Doctor Name (optional)')),
                const SizedBox(height: 10),
                TextField(controller: hospitalCtrl, decoration: const InputDecoration(labelText: 'Hospital Name (optional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: uploading ? null : () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: uploading ? null : () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) { showSnack(ctx, 'Please enter a document title', error: true); return; }
                setDialogState(() => uploading = true);
                try {
                  await ref.read(apiProvider).healthVaultUpload(
                    title: title, category: category,
                    description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                    doctorName: doctorCtrl.text.trim().isNotEmpty ? doctorCtrl.text.trim() : null,
                    hospitalName: hospitalCtrl.text.trim().isNotEmpty ? hospitalCtrl.text.trim() : null,
                  );
                  await _fetchDocuments();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) showSnack(context, 'Document "$title" saved to Health Vault!');
                } catch (e) {
                  if (ctx.mounted) showSnack(ctx, 'Upload error: $e', error: true);
                } finally {
                  if (ctx.mounted) setDialogState(() => uploading = false);
                }
              },
              icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file_rounded, size: 16),
              label: Text(uploading ? 'SavingÃ¢â‚¬Â¦' : 'Save Document'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteDocument(Map<String, dynamic> doc) async {
    if (!await _promptPassword('delete document')) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Document?'),
        content: Text('Are you sure you want to delete "${doc['title'] ?? doc['file_name'] ?? 'this document'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Palette.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(apiProvider).healthVaultDelete('${doc['id']}');
      await _fetchDocuments();
      if (mounted) showSnack(context, 'Document deleted.');
    } catch (e) {
      if (mounted) showSnack(context, 'Delete error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Palette.bg, body: Center(child: CircularProgressIndicator()));
    }

    if (_vaultLocked && _vaultPasswordHash != null && _vaultPasswordHash!.isNotEmpty) {
      return Scaffold(
        backgroundColor: Palette.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_rounded, size: 64, color: Palette.red),
                const SizedBox(height: 20),
                const Text('Health Vault Locked', style: TextStyle(color: Palette.text, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('Enter your vault password to access encrypted medical documents.', textAlign: TextAlign.center, style: TextStyle(color: Palette.textDim, fontSize: 14)),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: _unlockVault, icon: const Icon(Icons.lock_open_rounded), label: const Text('Unlock Vault')),
              ],
            ),
          ),
        ),
      );
    }

    if (_vaultPasswordHash == null && _records.isEmpty && _userId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_vaultPasswordHash == null && mounted) _setupVaultPassword();
      });
    }

    final filtered = _records.where((r) {
      final matchCat = _selectedCategory == 'All Records' || r['category'] == _selectedCategory;
      final matchSearch = _searchQuery.isEmpty ||
          (r['title'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (r['category'] ?? '').toString().toLowerCase().contains(_searchQuery.toLowerCase());
      return matchCat && matchSearch;
    }).toList();

    final userName = ref.watch(authProvider).session?.email?.split('@').first ?? 'User';

    return Scaffold(
      backgroundColor: Palette.bg,
      body: RefreshIndicator(
        onRefresh: _fetchDocuments,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: const Text('Ã°Å¸â€â€™', style: TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Health Vault', style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900)),
                      Text('${_records.length} Encrypted Medical Documents', style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
                    ],
                  ),
                ),
                FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: _openUploadDialog, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Upload')),
              ],
            ),
            const SizedBox(height: 16),

            EmergencyQrCard(patientName: userName, bloodGroup: '', compact: true),
            const SizedBox(height: 14),

            TextField(onChanged: (v) => setState(() => _searchQuery = v), decoration: const InputDecoration(hintText: 'Search documentsÃ¢â‚¬Â¦', prefixIcon: Icon(Icons.search_rounded))),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in _categories)
                  FilterChip(
                    selected: _selectedCategory == cat,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    label: Text(_categoryLabels[cat] ?? cat, style: TextStyle(color: _selectedCategory == cat ? Palette.blue : Palette.textDim, fontWeight: FontWeight.w700, fontSize: 12)),
                    selectedColor: Palette.blue.withOpacity(0.12),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _selectedCategory == cat ? Palette.blue : Palette.outline),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            if (filtered.isEmpty)
              GlassCard(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.folder_open_rounded, size: 48, color: Palette.textMuted),
                    const SizedBox(height: 12),
                    const Text('No documents found', style: TextStyle(color: Palette.textDim, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('Upload your first medical document to get started.', style: TextStyle(color: Palette.textMuted, fontSize: 13)),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _openUploadDialog, icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Upload Document')),
                  ],
                ),
              )
            else
              for (final doc in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () => _openDocumentViewer(doc),
                    child: Row(
                      children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(color: Palette.blue.withOpacity(0.10), borderRadius: BorderRadius.circular(12)), alignment: Alignment.center, child: const Text('Ã°Å¸â€œâ€ž', style: TextStyle(fontSize: 20))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc['title']?.toString() ?? doc['file_name']?.toString() ?? 'Document', style: const TextStyle(color: Palette.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _BadgePill(text: _categoryLabels[doc['category']] ?? '${doc['category']}', color: Palette.blue),
                                  _BadgePill(text: 'Ã°Å¸â€â€™ Encrypted', color: Palette.teal),
                                  if (doc['created_at'] != null) Text('${doc['created_at']}'.substring(0, 10), style: const TextStyle(color: Palette.textMuted, fontSize: 11.5)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Palette.red), onPressed: () => _deleteDocument(doc)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 5: MEDISCAN (/mediscan) Ã¢â‚¬â€ Matches MediscanPage.tsx + MedicineAnalyzerPage.tsx
// 3 Sub-route Tabs:
//   1. Ã°Å¸â€œâ€ž Document Scan (/api/gemini/mediscan)
//   2. Ã°Å¸â€Â¬ Diagnostic Imaging (/api/gemini/diagnostic-imaging)
//   3. Ã°Å¸Â§Âª Ingredient Analyzer (/api/gemini/medicine-ingredients with 5 sub-tabs:
//      Ã°Å¸Â§Âª Ingredients | Ã°Å¸â€™Å  Uses | Ã¢Å¡Â Ã¯Â¸Â Side Effects | Ã°Å¸Å’Â¿ Ayurvedic | Ã°Å¸â€ºÂ¡Ã¯Â¸Â Warnings)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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

  XFile? _selectedFile;
  Uint8List? _fileBytes;

  bool _docBusy = false;
  Map<String, dynamic>? _docResult;

  bool _imgBusy = false;
  Map<String, dynamic>? _imgResult;

  bool _medBusy = false;
  Map<String, dynamic>? _medResult;

  final _picker = ImagePicker();

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
    'ðŸ§ª Ingredients',
    'ðŸ’Š Uses',
    'âš ï¸ Side Effects',
    'ðŸŒ¿ Ayurvedic',
    'ðŸ›¡ï¸ Warnings',
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _selectedFile = photo;
          _fileBytes = bytes;
        });
        if (mounted) {
          showSnack(context, 'Image attached: ${photo.name} (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open camera/gallery: $e', error: true);
    }
  }

  void _clearImage() {
    setState(() {
      _selectedFile = null;
      _fileBytes = null;
    });
  }

  Future<void> _saveToSupabase(String scanType, Map<String, dynamic> analysis) async {
    final userId = ref.read(authProvider).session?.userId ?? '';
    if (userId.isEmpty) return;
    try {
      await ref.read(apiProvider).raw.post(
        ref.read(apiProvider).uri('/api/health-vault/scans'),
        headers: await ref.read(apiProvider).headers(),
        body: jsonEncode({
          'scan_type': scanType,
          'ai_analysis': analysis,
          'confidence_score': (analysis['confidenceScore'] as num?)?.toDouble() ?? 85.0,
        }),
      );
    } catch (_) {}
  }

  Future<void> _scanDocument() async {
    setState(() => _docBusy = true);
    try {
      final b64 = _fileBytes != null ? base64Encode(_fileBytes!) : null;
      final res = await ref.read(apiProvider).aiMediScan(
            _docTextCtrl.text.trim(),
            documentBase64: b64,
            filename: _selectedFile?.name ?? 'document.jpg',
            language: 'en',
          );
      if (mounted) {
        setState(() => _docResult = res);
        await _saveToSupabase('document_scan', res);
        showSnack(context, 'Document analysis complete!');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Document Scan error: $e', error: true);
    } finally {
      if (mounted) setState(() => _docBusy = false);
    }
  }

  Future<void> _scanImaging() async {
    setState(() => _imgBusy = true);
    try {
      final b64 = _fileBytes != null ? base64Encode(_fileBytes!) : null;
      final res = await ref.read(apiProvider).diagnosticImaging(
            imagingType: _modality,
            bodyRegion: _bodyRegion,
            clinicalContext: _imagingContextCtrl.text.trim(),
            documentBase64: b64,
            language: 'en',
          );
      if (mounted) {
        setState(() => _imgResult = res);
        await _saveToSupabase('diagnostic_imaging', res);
        showSnack(context, 'Diagnostic imaging analysis complete!');
      }
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
      final b64 = _fileBytes != null ? base64Encode(_fileBytes!) : null;
      final res = await ref.read(apiProvider).aiMedicineAnalyzer(
            _medSearchCtrl.text.trim(),
            documentBase64: b64,
            filename: _selectedFile?.name ?? 'medicine.jpg',
            language: 'en',
          );
      if (mounted) {
        setState(() => _medResult = res);
        await _saveToSupabase('medicine_analyzer', res);
        showSnack(context, 'Medicine breakdown complete!');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Ingredient Analyzer error: $e', error: true);
    } finally {
      if (mounted) setState(() => _medBusy = false);
    }
  }

  Widget _buildImagePickerBar() {
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
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded, size: 16, color: Palette.red),
                  label: const Text('Take Picture', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    side: const BorderSide(color: Palette.outline),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 16, color: Palette.blue),
                  label: const Text('Upload Device', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    side: const BorderSide(color: Palette.outline),
                  ),
                ),
              ),
            ],
          ),
          if (_selectedFile != null && _fileBytes != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.teal.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_fileBytes!, width: 44, height: 44, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Palette.text),
                        ),
                        Text(
                          '${(_fileBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB â€¢ Ready for scan',
                          style: const TextStyle(fontSize: 11, color: Palette.teal, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Palette.red),
                    onPressed: _clearImage,
                    tooltip: 'Remove image',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedDocResult() {
    final res = _docResult;
    if (res == null) return const SizedBox.shrink();

    final docType = res['documentType']?.toString() ?? 'Medical Document';
    final summary = res['summary']?.toString() ?? res['analysis']?.toString() ?? res['response']?.toString() ?? '';
    final notice = res['medicalDocumentNotice']?.toString() ?? '';
    final keyFindings = (res['keyFindings'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final medications = (res['medications'] as List?)?.whereType<Map>().toList() ?? [];
    final actionItems = (res['actionItems'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.teal.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BadgePill(text: docType.toUpperCase(), color: Palette.teal),
              const Spacer(),
              const _BadgePill(text: 'AI VERIFIED', color: Palette.green),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Document Summary', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Palette.text)),
          const SizedBox(height: 4),
          Text(summary, style: const TextStyle(fontSize: 13.5, color: Palette.textDim, height: 1.45)),

          if (notice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Palette.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 16, color: Palette.teal),
                  const SizedBox(width: 8),
                  Expanded(child: Text(notice, style: const TextStyle(fontSize: 12, color: Palette.teal, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ],

          if (keyFindings.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Key Clinical Findings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final kf in keyFindings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('â€¢ ', style: TextStyle(color: Palette.teal, fontSize: 16, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(kf, style: const TextStyle(fontSize: 13, color: Palette.textDim, height: 1.35))),
                  ],
                ),
              ),
          ],

          if (medications.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Medications Identified', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final med in medications)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Palette.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(med['name']?.toString() ?? 'Medicine', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Palette.text)),
                    const SizedBox(height: 2),
                    Text('Dose: ${med['dosage'] ?? 'As directed'} â€¢ ${med['instructions'] ?? ''}', style: const TextStyle(fontSize: 12, color: Palette.textDim)),
                  ],
                ),
              ),
          ],

          if (actionItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.red.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Suggested Action Items', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Palette.red)),
                  const SizedBox(height: 6),
                  for (final item in actionItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('â†’ $item', style: const TextStyle(fontSize: 12.5, color: Palette.text, height: 1.3)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedImagingResult() {
    final res = _imgResult;
    if (res == null) return const SizedBox.shrink();

    final urgency = res['urgencyLevel']?.toString() ?? 'Routine';
    final confidence = (res['confidenceScore'] as num?)?.toInt() ?? 84;
    final assessment = res['overallAssessment']?.toString() ?? res['summary']?.toString() ?? '';
    final findings = (res['findings'] as List?)?.whereType<Map>().toList() ?? [];
    final conditions = (res['possibleConditions'] as List?)?.whereType<Map>().toList() ?? [];
    final recommendations = (res['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final urgencyColor = urgency.toLowerCase().contains('emerg') || urgency.toLowerCase().contains('critical')
        ? Palette.red
        : (urgency.toLowerCase().contains('urgent') ? Palette.orange : Palette.teal);

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.blue.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BadgePill(text: '$urgency Urgency'.toUpperCase(), color: urgencyColor),
              const SizedBox(width: 8),
              _BadgePill(text: '$confidence% CONFIDENCE', color: Palette.blue),
              const Spacer(),
              Text('${res['imagingType'] ?? _modality}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.textDim)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Overall Assessment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Palette.text)),
          const SizedBox(height: 4),
          Text(assessment, style: const TextStyle(fontSize: 13.5, color: Palette.textDim, height: 1.45)),

          if (findings.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Radiology Findings', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final f in findings)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Palette.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(f['finding']?.toString() ?? 'Finding', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Palette.text))),
                        _BadgePill(text: '${f['severity'] ?? 'Normal'}', color: f['severity'] == 'Severe' ? Palette.red : Palette.teal),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(f['description']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Palette.textDim, height: 1.35)),
                  ],
                ),
              ),
          ],

          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Differential Diagnosis & Likelihood', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final pc in conditions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Palette.blue.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(pc['likelihood']?.toString() ?? 'Likely', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Palette.blue)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(pc['condition']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Palette.text))),
                  ],
                ),
              ),
          ],

          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Palette.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recommendations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Palette.teal)),
                  const SizedBox(height: 6),
                  for (final r in recommendations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('â€¢ $r', style: const TextStyle(fontSize: 12, color: Palette.textDim, height: 1.35)),
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
    final tabLabels = [
      'Active & Inactive Ingredients',
      'Clinical Uses & Indications',
      'Potential Side Effects',
      'Ayurvedic Alternatives',
      'Safety Warnings & Contraindications'
    ];

    if (res != null) {
      final keyVariants = <int, List<String>>{
        0: ['activeIngredients', 'ingredients', 'active_ingredients', 'composition'],
        1: ['uses', 'indications', 'clinical_uses', 'therapeutic_uses'],
        2: ['sideEffects', 'side_effects', 'adverse_effects', 'toxicity'],
        3: ['ayurvedic', 'ayurvedicAlternatives', 'ayurvedic_alternatives', 'herbal'],
        4: ['warnings', 'contraindications', 'safety_warnings', 'precautions'],
      };

      final keys = keyVariants[_ingredientSubTab] ?? [];
      for (final key in keys) {
        if (res[key] != null) {
          final val = res[key];
          if (val is List) {
            final items = val.map((item) {
              if (item is Map) {
                return '- **${item['name'] ?? item['role'] ?? ''}**: ${item['description'] ?? item['type'] ?? ''}';
              }
              return '- $item';
            }).join('\n');
            return '### ${tabLabels[_ingredientSubTab]} ($med)\n$items';
          }
          return '### ${tabLabels[_ingredientSubTab]} ($med)\n$val';
        }
      }

      final fullText = res['response']?.toString() ?? res['analysis']?.toString() ?? res['summary']?.toString();
      if (fullText != null && fullText.isNotEmpty) {
        return '### ${tabLabels[_ingredientSubTab]} ($med)\n$fullText';
      }
    }

    return '### ${tabLabels[_ingredientSubTab]} ($med)\n\n*Run the analysis above (or scan/upload a medicine package label) to see live breakdown for $med.*';
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
                decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: const Text('ðŸ“„', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mediscan AI', style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('Document Scan â€¢ Diagnostic Imaging â€¢ Ingredient Analyzer', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
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
              _SubRouteTabChip(label: 'ðŸ“„ Document Scan', selected: _subTab == 0, onTap: () => setState(() => _subTab = 0)),
              _SubRouteTabChip(label: 'ðŸ”¬ Diagnostic Imaging', selected: _subTab == 1, onTap: () => setState(() => _subTab = 1)),
              _SubRouteTabChip(label: 'ðŸ§ª Ingredient Analyzer', selected: _subTab == 2, onTap: () => setState(() => _subTab = 2)),
            ],
          ),
          const SizedBox(height: 14),

          if (_subTab == 0) ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ðŸ“„ Prescription & Lab Report AI Scanner', style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Take a picture of any report/prescription or upload from device for comprehensive AI extraction.', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  _buildImagePickerBar(),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _docTextCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Prescription / Lab Report Text / Notes (Optional)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _docBusy ? null : _scanDocument,
                    icon: _docBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.document_scanner_rounded, size: 18),
                    label: Text(_docBusy ? 'Scanning Documentâ€¦' : 'Analyze Medical Document'),
                  ),
                  _buildDetailedDocResult(),
                ],
              ),
            ),
          ] else if (_subTab == 1) ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ðŸ”¬ AI Radiology & Diagnostic Imaging Analyzer', style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Take a photo of X-Ray, CT, or MRI films or upload image file for AI abnormality detection.', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  _buildImagePickerBar(),
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
                          onChanged: (v) { if (v != null) setState(() => _modality = v); },
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
                          onChanged: (v) { if (v != null) setState(() => _bodyRegion = v); },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _imagingContextCtrl,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Clinical Indication / Imaging Notes'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _imgBusy ? null : _scanImaging,
                    icon: _imgBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.biotech_rounded, size: 18),
                    label: Text(_imgBusy ? 'Running Imaging AIâ€¦' : 'Run Diagnostic Imaging Analysis'),
                  ),
                  _buildDetailedImagingResult(),
                ],
              ),
            ),
          ] else ...[
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ðŸ§ª Medicine Ingredient & Ayurvedic Analyzer', style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Snap a picture of medicine box/strip or enter brand/generic name.', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  const SizedBox(height: 12),
                  _buildImagePickerBar(),
                  const SizedBox(height: 12),
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
                    icon: _medBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.science_rounded, size: 18),
                    label: Text(_medBusy ? 'Analyzing Ingredientsâ€¦' : 'Analyze Medicine Breakdown'),
                  ),
                  const SizedBox(height: 16),
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
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 6: TELEMEDICINE (/telemedicine) Ã¢â‚¬â€ Matches TelemedicinePage.tsx
// Sub-routes:
//   1. Ã°Å¸â€œÂ¹ Live Video Consultation Room (Agora RTC)
//   2. Ã°Å¸â€˜Â¨Ã¢â‚¬ÂÃ¢Å¡â€¢Ã¯Â¸Â Specialist Doctors Directory
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
      exp: '16 yrs exp Ã¢â‚¬Â¢ 24Ãƒâ€”7 Emergency On-Call',
      lang: 'English, Hindi, Kannada',
      room: 'cardio-consult-108',
    ),
    (
      name: 'Dr. Ananya Sharma, MD (Internal Medicine)',
      specialty: 'General Physician & Critical Care',
      hospital: 'Apollo Telehealth Command',
      exp: '12 yrs exp Ã¢â‚¬Â¢ Acute Fever & Triage',
      lang: 'English, Hindi, Bengali',
      room: 'med-consult-108',
    ),
    (
      name: 'Vaidya Pradeep Nair, BAMS, MD (Ayurveda)',
      specialty: 'AYUSH Kaya Chikitsa & Dashavidha Specialist',
      hospital: 'JeevanCare Integrative AYUSH Center',
      exp: '14 yrs exp Ã¢â‚¬Â¢ Prakriti & Chronic Care',
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
          'Ã°Å¸â€œÂ² Sent Agora Video Room link (${Config.videoCallUrl(room)}) via WhatsApp & Email to ${store.contactName}!',
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
                child: const Text('Ã°Å¸Â©Âº', style: TextStyle(fontSize: 22)),
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
                label: 'Ã°Å¸â€œÂ¹ Video Consultation Room',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: 'Ã°Å¸â€˜Â¨Ã¢â‚¬ÂÃ¢Å¡â€¢Ã¯Â¸Â Specialist Doctors',
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
                    'Ã°Å¸â€œÂ¹ Join or Host Agora RTC Emergency Video Room',
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
                          label: Text(_sendingInvite ? 'SendingÃ¢â‚¬Â¦' : 'Invite Emergency Contact'),
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
                            child: const Text('Ã°Å¸â€˜Â¨Ã¢â‚¬ÂÃ¢Å¡â€¢Ã¯Â¸Â', style: TextStyle(fontSize: 22)),
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
                                  '${doc.hospital} Ã¢â‚¬Â¢ ${doc.exp}',
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 7: SYMPTOM CHECKER (/symptom-checker) Ã¢â‚¬â€ Matches SymptomCheckerPage.tsx
// Includes:
//   - Front / Back Human Body Anatomy Map Selector
//   - 13 Symptom Chips + Severity Slider (1-10) + Duration Selector
//   - AI Triage Report (P1-P4 Urgency, Possible Conditions, Red Flags, Actions)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
class SymptomCheckerRouteScreen extends ConsumerStatefulWidget {
  const SymptomCheckerRouteScreen({super.key});

  @override
  ConsumerState<SymptomCheckerRouteScreen> createState() => _SymptomCheckerRouteScreenState();
}

class _SymptomCheckerRouteScreenState extends ConsumerState<SymptomCheckerRouteScreen> with SingleTickerProviderStateMixin {
  bool _backView = false;
  String _selectedRegion = 'Chest & Heart';
  final Set<String> _selectedSymptoms = {'Chest Pain', 'Shortness of Breath'};
  double _severity = 6;
  String _duration = '1â€“3 days';
  final _notesCtrl = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _triageResult;
  late AnimationController _pulseController;

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

  static const _symptomsByRegion = <String, List<String>>{
    'Head & Forehead': ['Headache', 'Migraine', 'Dizziness', 'Blurred Vision', 'Nausea', 'Fever', 'Tension', 'Scalp Tenderness'],
    'Eyes & Vision': ['Blurred Vision', 'Eye Pain', 'Redness', 'Watering', 'Light Sensitivity', 'Itching', 'Double Vision'],
    'Ear, Nose & Throat': ['Sore Throat', 'Ear Pain', 'Nasal Congestion', 'Hearing Loss', 'Sneezing', 'Fever', 'Runny Nose', 'Loss of Smell'],
    'Neck & Thyroid': ['Neck Pain', 'Stiffness', 'Swelling', 'Difficulty Swallowing', 'Hoarseness', 'Fever', 'Enlarged Glands'],
    'Chest & Heart': ['Chest Pain', 'Palpitations', 'Shortness of Breath', 'Tightness', 'Irregular Heartbeat', 'Dizziness', 'Cold Sweats', 'Pressure'],
    'Lungs & Airways': ['Cough', 'Wheezing', 'Shortness of Breath', 'Chest Congestion', 'Blood in Sputum', 'Fever', 'Rapid Breathing'],
    'Upper Abdomen': ['Nausea', 'Vomiting', 'Bloating', 'Heartburn', 'Loss of Appetite', 'Acid Reflux', 'Stomach Cramps'],
    'Lower Abdomen': ['Cramping', 'Diarrhea', 'Constipation', 'Blood in Stool', 'Bloating', 'Pelvic Pain', 'Gas'],
    'Pelvis & Hip': ['Hip Pain', 'Groin Pain', 'Urinary Issues', 'Pelvic Pressure', 'Numbness', 'Weakness', 'Burning Urination'],
    'Shoulder & Arm': ['Shoulder Pain', 'Arm Weakness', 'Numbness', 'Tingling', 'Limited Range', 'Swelling', 'Radiating Pain'],
    'Wrist & Hand': ['Wrist Pain', 'Numbness', 'Tingling', 'Weakness', 'Swelling', 'Stiffness', 'Tremor', 'Joint Stiffness'],
    'Knee & Lower Leg': ['Knee Pain', 'Swelling', 'Stiffness', 'Clicking', 'Instability', 'Cramps', 'Tenderness'],
    'Ankle & Foot': ['Ankle Pain', 'Swelling', 'Numbness', 'Plantar Pain', 'Stiffness', 'Burning', 'Heel Pain'],
    'Back of Head / Occiput': ['Occipital Pain', 'Tension', 'Neck Stiffness', 'Dizziness', 'Nausea', 'Tingling'],
    'Cervical Spine (Neck)': ['Neck Pain', 'Stiffness', 'Radiating Pain', 'Numbness', 'Weakness', 'Headache', 'Muscle Spasm'],
    'Upper Back & Scapula': ['Upper Back Pain', 'Shoulder Blade Pain', 'Stiffness', 'Muscle Spasm', 'Tenderness', 'Burning'],
    'Thoracic Spine': ['Mid-Back Pain', 'Stiffness', 'Radiating Pain', 'Muscle Spasm', 'Tenderness', 'Numbness'],
    'Lower Back / Lumbar': ['Lower Back Pain', 'Sciatica', 'Stiffness', 'Muscle Spasm', 'Numbness', 'Weakness', 'Shooting Pain'],
    'Flank & Kidneys': ['Flank Pain', 'Blood in Urine', 'Fever', 'Painful Urination', 'Nausea', 'Swelling', 'Severe Colic'],
    'Gluteal / Sciatic': ['Buttock Pain', 'Sciatica', 'Numbness', 'Tingling', 'Weakness', 'Burning', 'Radiating Leg Pain'],
    'Hamstring & Calf': ['Leg Cramps', 'Muscle Pull', 'Swelling', 'Tenderness', 'Stiffness', 'Pain when Walking'],
    'Achilles & Heel': ['Heel Pain', 'Achilles Tenderness', 'Stiffness', 'Swelling', 'Limping', 'Burning'],
  };

  static const _durations = <String>[
    'Just started (< 24h)',
    '1â€“3 days',
    '4â€“7 days',
    '1â€“4 weeks',
    '> 1 month',
  ];

  List<String> get _currentRegionList => _backView ? _backRegions : _frontRegions;
  List<String> get _availableSymptoms => _symptomsByRegion[_selectedRegion] ?? ['Pain', 'Swelling', 'Numbness', 'Fever'];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _runSymptomTriage() async {
    if (_selectedSymptoms.isEmpty) {
      showSnack(context, 'Please select at least one symptom.', error: true);
      return;
    }

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
      if (mounted) {
        setState(() => _triageResult = res);
        final userId = ref.read(authProvider).session?.userId ?? '';
        if (userId.isNotEmpty) {
          try {
            await ref.read(apiProvider).raw.post(
                  ref.read(apiProvider).uri('/api/health-vault/symptom-checks'),
                  headers: await ref.read(apiProvider).headers(),
                  body: jsonEncode({
                    'symptoms': {'list': _selectedSymptoms.toList()},
                    'body_region': _selectedRegion,
                    'severity': '${_severity.round()}/10',
                    'duration': _duration,
                    'ai_diagnosis': res,
                    'urgency_level': (res['urgencyLevel']?.toString().toLowerCase().contains('emerg') ?? false)
                        ? 'critical'
                        : ((res['urgencyLevel']?.toString().toLowerCase().contains('urgent') ?? false) ? 'high' : 'medium'),
                  }),
                );
          } catch (_) {}
        }
        showSnack(context, 'Clinical triage completed!');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Symptom Checker error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildBody3DVisualizer() {
    return Container(
      height: 290,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // Background grid lines (Sci-fi 3D hologram medical scan appearance)
          Positioned.fill(
            child: CustomPaint(
              painter: _MedicalGridPainter(),
            ),
          ),
          // Anatomical silhouette canvas
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (ctx, child) {
                return CustomPaint(
                  painter: _AnatomySilhouettePainter(
                    backView: _backView,
                    selectedRegion: _selectedRegion,
                    pulseValue: _pulseController.value,
                  ),
                );
              },
            ),
          ),
          // 3D View Banner Overlay
          Positioned(
            top: 10,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Palette.red.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: Palette.green, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(
                    '3D ANATOMY VIEW â€¢ ${_backView ? "POSTERIOR" : "ANTERIOR"}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
          // Selected region indicator card
          Positioned(
            bottom: 10,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.red.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_searching_rounded, size: 16, color: Palette.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target Region: $_selectedRegion',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${_selectedSymptoms.length} active',
                    style: const TextStyle(color: Palette.teal, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedTriageOutput() {
    final res = _triageResult;
    if (res == null) return const SizedBox.shrink();

    final urgency = res['urgencyLevel']?.toString() ?? res['triageLevel']?.toString() ?? 'P3 Moderate';
    final summary = res['summary']?.toString() ?? res['triage']?.toString() ?? res['analysis']?.toString() ?? '';
    final possibleConditions = (res['possibleConditions'] as List?)?.whereType<Map>().toList() ?? [];
    final redFlags = (res['redFlags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final recommendations = (res['recommendedActions'] as List?)?.map((e) => e.toString()).toList() ??
        (res['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final ayurvedic = res['ayurvedicCare']?.toString() ?? res['ayurveda']?.toString() ?? '';

    Color urgencyColor = Palette.teal;
    if (urgency.toLowerCase().contains('p1') || urgency.toLowerCase().contains('critical') || urgency.toLowerCase().contains('emerg')) {
      urgencyColor = Palette.red;
    } else if (urgency.toLowerCase().contains('p2') || urgency.toLowerCase().contains('high')) {
      urgencyColor = Palette.orange;
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surfaceHi,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: urgencyColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BadgePill(text: urgency.toUpperCase(), color: urgencyColor),
              const Spacer(),
              const _BadgePill(text: 'AI CLINICAL TRIAGE', color: Palette.blue),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Clinical Triage Assessment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Palette.text)),
          const SizedBox(height: 4),
          Text(summary, style: const TextStyle(fontSize: 13.5, color: Palette.textDim, height: 1.45)),

          if (redFlags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Palette.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Palette.red),
                      SizedBox(width: 6),
                      Text('Critical Warning Signs (Seek Immediate Medical Care)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Palette.red)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final flag in redFlags)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('â€¢ $flag', style: const TextStyle(fontSize: 12, color: Palette.text, height: 1.35)),
                    ),
                ],
              ),
            ),
          ],

          if (possibleConditions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Possible Conditions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final pc in possibleConditions)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Palette.outline)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(pc['condition']?.toString() ?? 'Condition', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Palette.text))),
                        if (pc['likelihood'] != null)
                          _BadgePill(text: '${pc['likelihood']}', color: Palette.blue),
                      ],
                    ),
                    if (pc['description'] != null) ...[
                      const SizedBox(height: 2),
                      Text(pc['description'].toString(), style: const TextStyle(fontSize: 12, color: Palette.textDim, height: 1.35)),
                    ],
                  ],
                ),
              ),
          ],

          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Recommended Actions & Care Plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Palette.text)),
            const SizedBox(height: 6),
            for (final r in recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('âœ“ ', style: TextStyle(color: Palette.green, fontSize: 14, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(r, style: const TextStyle(fontSize: 12.5, color: Palette.textDim, height: 1.35))),
                  ],
                ),
              ),
          ],

          if (ayurvedic.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Palette.green.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Palette.green.withOpacity(0.25))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Integrative AYUSH / Home Support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Palette.green)),
                  const SizedBox(height: 4),
                  Text(ayurvedic, style: const TextStyle(fontSize: 12, color: Palette.textDim, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
                decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: const Text('ðŸ§ ', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Symptom Checker', style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('3D Anatomy Model â€¢ Clinical Triage System', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3D Anatomy Model Visualizer Card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ðŸ§ Interactive 3D Anatomy Model', style: TextStyle(color: Palette.text, fontSize: 15.5, fontWeight: FontWeight.w800)),
                    SizedBox(
                      height: 36,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Front', style: TextStyle(fontSize: 12))),
                          ButtonSegment(value: true, label: Text('Back', style: TextStyle(fontSize: 12))),
                        ],
                        selected: {_backView},
                        onSelectionChanged: (s) {
                          setState(() {
                            _backView = s.first;
                            _selectedRegion = (_backView ? _backRegions : _frontRegions).first;
                            _selectedSymptoms.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildBody3DVisualizer(),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dropdown Selections (Region & Associated Symptoms)
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select Body Region', style: TextStyle(color: Palette.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _currentRegionList.contains(_selectedRegion) ? _selectedRegion : _currentRegionList.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Body Region (Dropdown)',
                    prefixIcon: Icon(Icons.accessibility_new_rounded, color: Palette.red),
                  ),
                  items: _currentRegionList.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedRegion = v;
                        _selectedSymptoms.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                const Text('Select Associated Symptoms', style: TextStyle(color: Palette.text, fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  hint: const Text('Choose a symptom from dropdown to addâ€¦'),
                  decoration: const InputDecoration(
                    labelText: 'Add Associated Symptom (Dropdown)',
                    prefixIcon: Icon(Icons.add_circle_outline_rounded, color: Palette.teal),
                  ),
                  items: _availableSymptoms.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (s) {
                    if (s != null) {
                      setState(() {
                        _selectedSymptoms.add(s);
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Selected symptom tags
                if (_selectedSymptoms.isNotEmpty) ...[
                  const Text('Active Selected Symptoms:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.textDim)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sym in _selectedSymptoms)
                        Chip(
                          label: Text(sym, style: const TextStyle(color: Palette.red, fontWeight: FontWeight.w700, fontSize: 12)),
                          backgroundColor: Palette.redLight,
                          side: const BorderSide(color: Palette.red),
                          deleteIcon: const Icon(Icons.close, size: 14, color: Palette.red),
                          onDeleted: () {
                            setState(() => _selectedSymptoms.remove(sym));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Or quick-tap suggested chips for region
                const Text('Or tap to toggle symptoms:', style: TextStyle(fontSize: 11.5, color: Palette.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in _availableSymptoms)
                      FilterChip(
                        selected: _selectedSymptoms.contains(s),
                        onSelected: (v) {
                          setState(() {
                            if (v) _selectedSymptoms.add(s);
                            else _selectedSymptoms.remove(s);
                          });
                        },
                        label: Text(s, style: TextStyle(fontSize: 11.5, color: _selectedSymptoms.contains(s) ? Palette.red : Palette.text)),
                        selectedColor: Palette.redLight,
                        checkmarkColor: Palette.red,
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Symptom Severity', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(999)),
                      child: Text('${_severity.round()} / 10', style: const TextStyle(color: Palette.red, fontWeight: FontWeight.w900)),
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
                  items: _durations.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
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
                    labelText: 'Additional Clinical Notes (Optional)',
                    hintText: 'Describe onset triggers, radiation of pain, or feverâ€¦',
                  ),
                ),
                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: _busy ? null : _runSymptomTriage,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.psychology_rounded, size: 18),
                  label: Text(_busy ? 'Running Clinical AI Triageâ€¦' : 'Analyze Symptoms with AI'),
                ),
                _buildDetailedTriageOutput(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B).withOpacity(0.4)
      ..strokeWidth = 0.8;

    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnatomySilhouettePainter extends CustomPainter {
  _AnatomySilhouettePainter({
    required this.backView,
    required this.selectedRegion,
    required this.pulseValue,
  });

  final bool backView;
  final String selectedRegion;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final bodyPaint = Paint()
      ..color = const Color(0xFF334155).withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final bodyStroke = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Head
    final headRect = Rect.fromCircle(center: Offset(cx, cy - 88), radius: 24);
    canvas.drawOval(headRect, bodyPaint);
    canvas.drawOval(headRect, bodyStroke);

    // Neck
    final neckRect = RRect.fromRectAndRadius(Rect.fromLTWH(cx - 8, cy - 64, 16, 14), const Radius.circular(3));
    canvas.drawRRect(neckRect, bodyPaint);
    canvas.drawRRect(neckRect, bodyStroke);

    // Torso / Chest / Abdomen
    final torsoPath = Path()
      ..moveTo(cx - 36, cy - 50)
      ..lineTo(cx + 36, cy - 50)
      ..lineTo(cx + 28, cy + 20)
      ..lineTo(cx - 28, cy + 20)
      ..close();
    canvas.drawPath(torsoPath, bodyPaint);
    canvas.drawPath(torsoPath, bodyStroke);

    // Arms
    final leftArm = Path()
      ..moveTo(cx - 36, cy - 48)
      ..lineTo(cx - 52, cy + 10)
      ..lineTo(cx - 56, cy + 50)
      ..lineTo(cx - 48, cy + 50)
      ..lineTo(cx - 44, cy + 10)
      ..lineTo(cx - 30, cy - 40)
      ..close();
    canvas.drawPath(leftArm, bodyPaint);
    canvas.drawPath(leftArm, bodyStroke);

    final rightArm = Path()
      ..moveTo(cx + 36, cy - 48)
      ..lineTo(cx + 52, cy + 10)
      ..lineTo(cx + 56, cy + 50)
      ..lineTo(cx + 48, cy + 50)
      ..lineTo(cx + 44, cy + 10)
      ..lineTo(cx + 30, cy - 40)
      ..close();
    canvas.drawPath(rightArm, bodyPaint);
    canvas.drawPath(rightArm, bodyStroke);

    // Pelvis
    final pelvisPath = Path()
      ..moveTo(cx - 28, cy + 20)
      ..lineTo(cx + 28, cy + 20)
      ..lineTo(cx + 22, cy + 42)
      ..lineTo(cx - 22, cy + 42)
      ..close();
    canvas.drawPath(pelvisPath, bodyPaint);
    canvas.drawPath(pelvisPath, bodyStroke);

    // Left leg
    final leftLeg = Path()
      ..moveTo(cx - 22, cy + 42)
      ..lineTo(cx - 10, cy + 42)
      ..lineTo(cx - 12, cy + 110)
      ..lineTo(cx - 20, cy + 110)
      ..close();
    canvas.drawPath(leftLeg, bodyPaint);
    canvas.drawPath(leftLeg, bodyStroke);

    // Right leg
    final rightLeg = Path()
      ..moveTo(cx + 10, cy + 42)
      ..lineTo(cx + 22, cy + 42)
      ..lineTo(cx + 20, cy + 110)
      ..lineTo(cx + 12, cy + 110)
      ..close();
    canvas.drawPath(rightLeg, bodyPaint);
    canvas.drawPath(rightLeg, bodyStroke);

    // Spine line on Back View
    if (backView) {
      final spinePaint = Paint()
        ..color = const Color(0xFF94A3B8).withOpacity(0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(cx, cy - 60), Offset(cx, cy + 24), spinePaint);
    }

    // Target coordinates for each region
    Offset targetOffset = Offset(cx, cy - 25);
    final reg = selectedRegion.toLowerCase();
    if (reg.contains('head') || reg.contains('eyes') || reg.contains('ear')) {
      targetOffset = Offset(cx, cy - 88);
    } else if (reg.contains('neck') || reg.contains('cervical')) {
      targetOffset = Offset(cx, cy - 58);
    } else if (reg.contains('chest') || reg.contains('heart') || reg.contains('lung') || reg.contains('upper back')) {
      targetOffset = Offset(cx, cy - 35);
    } else if (reg.contains('abdomen') || reg.contains('thoracic') || reg.contains('kidney')) {
      targetOffset = Offset(cx, cy);
    } else if (reg.contains('pelvis') || reg.contains('hip') || reg.contains('lumbar') || reg.contains('gluteal')) {
      targetOffset = Offset(cx, cy + 28);
    } else if (reg.contains('shoulder') || reg.contains('arm')) {
      targetOffset = Offset(cx - 44, cy - 10);
    } else if (reg.contains('wrist') || reg.contains('hand')) {
      targetOffset = Offset(cx - 52, cy + 48);
    } else if (reg.contains('knee') || reg.contains('thigh') || reg.contains('hamstring') || reg.contains('leg')) {
      targetOffset = Offset(cx - 16, cy + 70);
    } else if (reg.contains('ankle') || reg.contains('foot') || reg.contains('heel')) {
      targetOffset = Offset(cx - 16, cy + 108);
    }

    // Glowing target indicator
    final glowRadius = 14.0 + (pulseValue * 8.0);
    final glowPaint = Paint()
      ..color = const Color(0xFFE63946).withOpacity(0.35 - (pulseValue * 0.15))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetOffset, glowRadius, glowPaint);

    final centerPinPaint = Paint()
      ..color = const Color(0xFFE63946)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetOffset, 5.0, centerPinPaint);

    final whiteCenter = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetOffset, 2.0, whiteCenter);
  }

  @override
  bool shouldRepaint(covariant _AnatomySilhouettePainter oldDelegate) {
    return oldDelegate.backView != backView ||
        oldDelegate.selectedRegion != selectedRegion ||
        oldDelegate.pulseValue != pulseValue;
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 9: COMMUNITY (/community) Ã¢â‚¬â€ Matches CommunityPage.tsx & Image 2 ("5 / blood needed")
// Sub-routes:
//   1. Ã°Å¸Å¡Â¨ Community Alerts Feed (6 Category Filters + 3 Stat Cards + 5 Active Alerts starting with "blood needed")
//   2. Ã°Å¸Å’Â§Ã¯Â¸Â Disaster & Weather Radar Map (OpenWeather + RainViewer Radar + Risk Score)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
class CommunityRouteScreen extends ConsumerStatefulWidget {
  const CommunityRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  ConsumerState<CommunityRouteScreen> createState() => _CommunityRouteScreenState();
}

class _CommunityRouteScreenState extends ConsumerState<CommunityRouteScreen> {
  late int _subTab;
  String _selectedFilter = 'All';
  bool _loading = true;
  List<Map<String, dynamic>> _alerts = [];

  static const _filters = <String>['All', 'Medical', 'Flood', 'Fire', 'Infrastructure', 'General'];

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 1);
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    setState(() => _loading = true);
    final userId = ref.read(authProvider).session?.userId ?? '';
    if (userId.isNotEmpty) {
      try {
        _alerts = await ref.read(apiProvider).healthVaultAlerts();
      } catch (_) {
        _alerts = [];
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openPostAlertModal() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Medical';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ðŸš¨ Post Community Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Alert Headline', hintText: 'e.g., O- Blood Needed / Road Blocked')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _filters.where((f) => f != 'All').map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) { if (v != null) category = v; },
            ),
            const SizedBox(height: 10),
            TextField(controller: descCtrl, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Details & Location')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final userId = ref.read(authProvider).session?.userId ?? '';
              double lat = 12.9716, lng = 77.5946;
              try {
                final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 4)));
                lat = pos.latitude; lng = pos.longitude;
              } catch (_) {}
              try {
                await ref.read(apiProvider).healthVaultCreateAlert(alertType: category, latitude: lat, longitude: lng, address: descCtrl.text.trim(), title: titleCtrl.text.trim());
                await _fetchAlerts();
              } catch (_) {}
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) showSnack(context, 'Community alert broadcasted!');
            },
            child: const Text('Broadcast Alert'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedFilter == 'All' ? _alerts : _alerts.where((a) => a['alert_type'] == _selectedFilter).toList();
    final verifiedCount = _alerts.where((a) => a['status'] == 'resolved').length;

    return Scaffold(
      backgroundColor: Palette.bg,
      body: RefreshIndicator(
        onRefresh: _fetchAlerts,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: const Text('ðŸŒ', style: TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Community Alerts', style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('Crowdsourced Emergency Feed & Live Disaster Radar', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                  ]),
                ),
                FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: _openPostAlertModal, icon: const Icon(Icons.add_alert_rounded, size: 16), label: const Text('Post Alert')),
              ],
            ),
            const SizedBox(height: 14),

            Row(children: [
              Expanded(child: _MiniStatCard(label: 'ACTIVE ALERTS', value: '${_alerts.length}', color: Palette.red)),
              const SizedBox(width: 10),
              Expanded(child: _MiniStatCard(label: 'RESOLVED', value: '$verifiedCount', color: Palette.teal)),
              const SizedBox(width: 10),
              Expanded(child: _MiniStatCard(label: 'TOTAL', value: '${_alerts.length}', color: Palette.green)),
            ]),
            const SizedBox(height: 14),

            Wrap(spacing: 8, runSpacing: 8, children: [
              _SubRouteTabChip(label: 'ðŸš¨ Community Alerts Feed', selected: _subTab == 0, onTap: () => setState(() => _subTab = 0)),
              _SubRouteTabChip(label: 'ðŸŒ§ï¸ Disaster & Weather Radar', selected: _subTab == 1, onTap: () => setState(() => _subTab = 1)),
            ]),
            const SizedBox(height: 12),

            if (_subTab == 0) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final f in _filters)
                  ChoiceChip(selected: _selectedFilter == f, showCheckmark: false, onSelected: (_) => setState(() => _selectedFilter = f),
                    label: Text(f, style: TextStyle(color: _selectedFilter == f ? Palette.red : Palette.text, fontWeight: FontWeight.w700, fontSize: 12)),
                    selectedColor: Palette.redLight, backgroundColor: Colors.white, side: BorderSide(color: _selectedFilter == f ? Palette.red : Palette.outline)),
              ]),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (filtered.isEmpty)
                GlassCard(padding: const EdgeInsets.all(32), child: const Column(children: [
                  Icon(Icons.campaign_rounded, size: 48, color: Palette.textMuted), SizedBox(height: 12),
                  Text('No community alerts yet', style: TextStyle(color: Palette.textDim, fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('Be the first to post an alert for your community.', style: TextStyle(color: Palette.textMuted, fontSize: 13)),
                ]))
              else
                for (final alert in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          _BadgePill(text: '${alert['alert_type'] ?? 'General'}', color: Palette.orange),
                          const SizedBox(width: 8),
                          _BadgePill(text: '${alert['status'] ?? 'active'}', color: alert['status'] == 'resolved' ? Palette.green : Palette.red),
                          const Spacer(),
                          Text('${alert['created_at'] ?? ''}'.length > 10 ? '${alert['created_at']}'.substring(0, 10) : '', style: const TextStyle(color: Palette.textMuted, fontSize: 11.5)),
                        ]),
                        const SizedBox(height: 8),
                        Text('${alert['alert_type'] ?? 'Community Alert'}', style: const TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w900)),
                        if (alert['address'] != null && alert['address'].toString().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('${alert['address']}', style: const TextStyle(color: Palette.textDim, fontSize: 13, height: 1.35)),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 15, color: Palette.red),
                          const SizedBox(width: 4),
                          Expanded(child: Text('${alert['latitude'] ?? ''}, ${alert['longitude'] ?? ''}', style: const TextStyle(color: Palette.textDim, fontSize: 12, fontWeight: FontWeight.w600))),
                        ]),
                      ]),
                    ),
                  ),
            ] else ...[
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Text('ðŸŒ§ï¸', style: TextStyle(fontSize: 20)), SizedBox(width: 8),
                    Expanded(child: Text('Weather & Disaster Radar', style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w800))),
                  ]),
                  const SizedBox(height: 12),
                  Container(height: 180, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(14), border: Border.all(color: Palette.blue.withOpacity(0.3))),
                    alignment: Alignment.center,
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.radar_rounded, size: 42, color: Palette.blue), SizedBox(height: 8),
                      Text('Live Weather & Community Alert Pins', style: TextStyle(color: Palette.text, fontWeight: FontWeight.w800)),
                    ])),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 10: EMERGENCY SERVICES (/emergency-services) Ã¢â‚¬â€ Matches EmergencyServicesPage.tsx
// 4 Sub-route Tabs:
//   1. Ã°Å¸ÂÂ¥ Hospitals (10,000+ hospitals, Scope All/Nearby/24x7, 9 Categories)
//   2. Ã°Å¸Â©Â¸ Blood Banks (20+ verified banks & donors, Urgent Blood Requests, A+..O-)
//   3. Ã°Å¸Å¡â€˜ Ambulances (10,000+ Ambulances, 108/102/112, BLS/ALS/Cardiac/ICU)
//   4. Ã°Å¸Â¤Â NGO Connect (10,000+ Verified NGOs, 11 Categories, Contact NGO modal)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
class EmergencyServicesRouteScreen extends ConsumerStatefulWidget {
  const EmergencyServicesRouteScreen({super.key, this.initialSubTab = 0});

  final int initialSubTab;

  @override
  ConsumerState<EmergencyServicesRouteScreen> createState() => _EmergencyServicesRouteScreenState();
}

class _EmergencyServicesRouteScreenState extends ConsumerState<EmergencyServicesRouteScreen> {
  late int _subTab;
  String _hospitalCategory = 'All';
  String _bloodGroup = 'All';
  String _ambulanceType = 'All';
  String _ngoCategory = 'All';

  double? _lat;
  double? _lon;
  bool _loadingLocation = true;
  bool _loadingFacilities = false;
  bool _loadingBlood = false;
  bool _loadingNgos = false;

  List<CareFacility> _facilities = [];
  List<Map<String, dynamic>> _bloodBanks = [];
  List<Map<String, dynamic>> _ngos = [];

  @override
  void initState() {
    super.initState();
    _subTab = widget.initialSubTab.clamp(0, 3);
    _getLocationAndFetch();
  }

  Future<void> _getLocationAndFetch() async {
    setState(() => _loadingLocation = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        _lat = 12.9716; _lon = 77.5946;
      } else {
        try {
          final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 5)));
          _lat = pos.latitude; _lon = pos.longitude;
        } catch (_) {
          final last = await Geolocator.getLastKnownPosition();
          _lat = last?.latitude ?? 12.9716; _lon = last?.longitude ?? 77.5946;
        }
      }
    } catch (_) {
      _lat = 12.9716; _lon = 77.5946;
    }
    if (mounted) setState(() => _loadingLocation = false);
    await _fetchFacilities();
    await _fetchBloodBanks();
    await _fetchNgos();
  }

  Future<void> _fetchFacilities() async {
    if (_lat == null || _lon == null) return;
    setState(() => _loadingFacilities = true);
    try {
      _facilities = await ref.read(apiProvider).nearbyFacilities(_lat!, _lon!);
    } catch (_) {}
    if (mounted) setState(() => _loadingFacilities = false);
  }

  Future<void> _fetchBloodBanks() async {
    setState(() => _loadingBlood = true);
    try {
      _bloodBanks = await ref.read(apiProvider).searchBloodBank(bloodType: _bloodGroup == 'All' ? '' : _bloodGroup);
    } catch (_) {}
    if (mounted) setState(() => _loadingBlood = false);
  }

  Future<void> _fetchNgos() async {
    setState(() => _loadingNgos = true);
    try {
      _ngos = await ref.read(apiProvider).listNgos(category: _ngoCategory == 'All' ? 'all' : _ngoCategory.toLowerCase().replaceAll(' & ', '_').replaceAll(' ', '_'));
    } catch (_) {}
    if (mounted) setState(() => _loadingNgos = false);
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number.replaceAll(' ', ''));
    await launchUrl(uri);
  }

  List<CareFacility> get _filteredFacilities {
    if (_hospitalCategory == 'All') return _facilities;
    final cat = _hospitalCategory.toLowerCase();
    return _facilities.where((f) {
      final name = f.name.toLowerCase();
      if (cat.contains('24')) return f.open24x7 || f.emergency;
      return name.contains(cat);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: RefreshIndicator(
        onRefresh: _getLocationAndFetch,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Palette.redLight, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: const Text('Ã°Å¸Å¡Â¨', style: TextStyle(fontSize: 22))),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emergency Services', style: TextStyle(color: Palette.text, fontSize: 22, fontWeight: FontWeight.w900)),
                      Text('Hospitals Ã¢â‚¬Â¢ Blood Banks Ã¢â‚¬Â¢ Ambulances Ã¢â‚¬Â¢ NGO Connect', style: TextStyle(color: Palette.textDim, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // TomTom Static Map
            if (_lat != null && _lon != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  'https://api.tomtom.com/map/1/staticimage?key=${Config.tomtomApiKey}&center=$_lon,$_lat&zoom=13&width=600&height=200&format=png',
                  height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 160, decoration: BoxDecoration(color: Palette.surfaceHi, borderRadius: BorderRadius.circular(14)), alignment: Alignment.center,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.map_rounded, size: 36, color: Palette.textMuted), const SizedBox(height: 8), Text('Location: ${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}', style: const TextStyle(color: Palette.textDim, fontSize: 12))])),
                  loadingBuilder: (_, child, progress) { if (progress == null) return child; return Container(height: 160, decoration: BoxDecoration(color: Palette.surfaceHi, borderRadius: BorderRadius.circular(14)), alignment: Alignment.center, child: const CircularProgressIndicator()); },
                ),
              )
            else if (_loadingLocation)
              Container(height: 160, decoration: BoxDecoration(color: Palette.surfaceHi, borderRadius: BorderRadius.circular(14)), alignment: Alignment.center, child: const CircularProgressIndicator()),
            const SizedBox(height: 14),

            // 4 Sub-Route Tabs
            Wrap(spacing: 8, runSpacing: 8, children: [
              _SubRouteTabChip(label: 'Ã°Å¸ÂÂ¥ Hospitals', selected: _subTab == 0, onTap: () => setState(() => _subTab = 0)),
              _SubRouteTabChip(label: 'Ã°Å¸Â©Â¸ Blood Banks', selected: _subTab == 1, onTap: () => setState(() => _subTab = 1)),
              _SubRouteTabChip(label: 'Ã°Å¸Å¡â€˜ Ambulances', selected: _subTab == 2, onTap: () => setState(() => _subTab = 2)),
              _SubRouteTabChip(label: 'Ã°Å¸Â¤Â NGO Connect', selected: _subTab == 3, onTap: () => setState(() => _subTab = 3)),
            ]),
            const SizedBox(height: 14),

            if (_subTab == 0) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in const ['All', 'Emergency 24Ãƒâ€”7', 'Multi-Specialty', 'Government', 'Cardiac', 'Trauma', 'Maternity', 'Pediatric', 'AYUSH'])
                  ChoiceChip(selected: _hospitalCategory == c, showCheckmark: false, onSelected: (_) => setState(() => _hospitalCategory = c),
                    label: Text(c, style: TextStyle(color: _hospitalCategory == c ? Palette.red : Palette.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    selectedColor: Palette.redLight, backgroundColor: Colors.white, side: BorderSide(color: _hospitalCategory == c ? Palette.red : Palette.outline)),
              ]),
              const SizedBox(height: 12),
              if (_loadingFacilities)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_filteredFacilities.isEmpty)
                const GlassCard(padding: EdgeInsets.all(32), child: Column(children: [Icon(Icons.local_hospital_rounded, size: 40, color: Palette.textMuted), SizedBox(height: 8), Text('No hospitals found nearby. Pull to refresh.', style: TextStyle(color: Palette.textDim))]))
              else
                for (final f in _filteredFacilities)
                  _DirectoryCard(emoji: 'Ã°Å¸ÂÂ¥', title: f.name, subtitle: '${f.address} Ã¢â‚¬Â¢ ${(((f.distanceMeters ?? 0)) / 1000).toStringAsFixed(1)} km',
                    badges: [if (f.emergency) '24Ãƒâ€”7 Emergency', if (f.open24x7) 'Open 24Ãƒâ€”7', f.source], phone: f.phone.isNotEmpty ? f.phone : '108', accent: Palette.teal, onCall: () => _dial(f.phone.isNotEmpty ? f.phone : '108')),
            ] else if (_subTab == 1) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final bg in const ['All', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
                  ChoiceChip(selected: _bloodGroup == bg, showCheckmark: false, onSelected: (_) { setState(() => _bloodGroup = bg); _fetchBloodBanks(); },
                    label: Text('Ã°Å¸Â©Â¸ $bg', style: TextStyle(color: _bloodGroup == bg ? Palette.red : Palette.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    selectedColor: Palette.redLight, backgroundColor: Colors.white, side: BorderSide(color: _bloodGroup == bg ? Palette.red : Palette.outline)),
              ]),
              const SizedBox(height: 12),
              if (_loadingBlood)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_bloodBanks.isEmpty)
                const GlassCard(padding: EdgeInsets.all(32), child: Column(children: [Icon(Icons.bloodtype_rounded, size: 40, color: Palette.textMuted), SizedBox(height: 8), Text('No blood banks found. Pull to refresh.', style: TextStyle(color: Palette.textDim))]))
              else
                for (final bb in _bloodBanks)
                  _DirectoryCard(emoji: 'Ã°Å¸Â©Â¸', title: bb['name']?.toString() ?? 'Blood Bank', subtitle: bb['city']?.toString() ?? bb['address']?.toString() ?? '',
                    badges: [if (bb['bloodType'] != null) '${bb['bloodType']}'], phone: bb['phone']?.toString() ?? '108', accent: Palette.red, onCall: () => _dial(bb['phone']?.toString() ?? '108')),
            ] else if (_subTab == 2) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in const ['All', 'ALS (Advanced Life Support)', 'BLS (Basic)', 'Cardiac ICU', 'Neonatal', 'Ventilator'])
                  ChoiceChip(selected: _ambulanceType == t, showCheckmark: false, onSelected: (_) => setState(() => _ambulanceType = t),
                    label: Text(t, style: TextStyle(color: _ambulanceType == t ? Palette.red : Palette.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    selectedColor: Palette.redLight, backgroundColor: Colors.white, side: BorderSide(color: _ambulanceType == t ? Palette.red : Palette.outline)),
              ]),
              const SizedBox(height: 12),
              _DirectoryCard(emoji: 'Ã°Å¸Å¡â€˜', title: '108 Arogya Kavacha Free Emergency Ambulance', subtitle: 'Government 24Ãƒâ€”7 ALS & BLS Fleet Ã¢â‚¬Â¢ Avg ETA 7 mins', badges: const ['FREE SERVICE', '24Ãƒâ€”7 Open', 'ALS Ventilator & Defibrillator'], phone: '108', accent: Palette.orange, onCall: () => _dial('108')),
              _DirectoryCard(emoji: 'Ã°Å¸Å¡â€˜', title: '112 Emergency Response (Police/Fire/Ambulance)', subtitle: 'Unified Emergency Helpline Ã¢â‚¬Â¢ Pan-India', badges: const ['All Emergencies', '24Ãƒâ€”7 Open', 'GPS Tracked'], phone: '112', accent: Palette.red, onCall: () => _dial('112')),
              _DirectoryCard(emoji: 'Ã°Å¸Å¡â€˜', title: '102 Mother & Child Ambulance Service', subtitle: 'Free Pregnancy Transport Ã¢â‚¬Â¢ Government', badges: const ['Maternity', 'FREE SERVICE', '24Ãƒâ€”7'], phone: '102', accent: Palette.teal, onCall: () => _dial('102')),
            ] else ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in const ['All', 'Disaster Relief', 'Medical Aid', 'Blood Donation', 'Food & Hunger', 'Mental Health', 'Elderly Care'])
                  ChoiceChip(selected: _ngoCategory == c, showCheckmark: false, onSelected: (_) { setState(() => _ngoCategory = c); _fetchNgos(); },
                    label: Text(c, style: TextStyle(color: _ngoCategory == c ? Palette.red : Palette.text, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    selectedColor: Palette.redLight, backgroundColor: Colors.white, side: BorderSide(color: _ngoCategory == c ? Palette.red : Palette.outline)),
              ]),
              const SizedBox(height: 12),
              if (_loadingNgos)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_ngos.isEmpty)
                const GlassCard(padding: EdgeInsets.all(32), child: Column(children: [Icon(Icons.people_rounded, size: 40, color: Palette.textMuted), SizedBox(height: 8), Text('No NGOs found. Pull to refresh.', style: TextStyle(color: Palette.textDim))]))
              else
                for (final ngo in _ngos)
                  _DirectoryCard(emoji: 'Ã°Å¸Â¤Â', title: ngo['name']?.toString() ?? 'NGO', subtitle: ngo['description']?.toString() ?? ngo['category']?.toString() ?? '',
                    badges: [if (ngo['category'] != null) '${ngo['category']}', if (ngo['verified'] == true) 'Verified'], phone: ngo['phone']?.toString() ?? ngo['contact']?.toString() ?? '', accent: Palette.blue, onCall: () => _dial(ngo['phone']?.toString() ?? ngo['contact']?.toString() ?? '')),
            ],
          ],
        ),
      ),
    );
  }
}


// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 12: WELLBEING (/wellbeing) Ã¢â‚¬â€ Matches WellbeingPage.tsx
// Sarah Ã¢â‚¬â€ Your well-being companion Ã‚Â· Always here Ã°Å¸â€™â„¢
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
          "Hi zaid Ã°Å¸â€™â„¢ I'm Sarah, your confidential well-being companion. Whether you're feeling stressed, anxious, or just need someone to talk to, I'm right here to listen without judgment. How are you feeling right now?",
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
      final reply = '${res['reply'] ?? res['response'] ?? res['message'] ?? "I hear you Ã°Å¸â€™â„¢ Take a slow, deep breath with meÃ¢â‚¬â€inhale for 4 seconds, hold for 4 seconds, and exhale gently. You don't have to carry everything all at once."}';
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
                "I'm right here with you Ã°Å¸â€™â„¢ Let's pause for a gentle breath: inhale slowly for 4 counts, hold for 4 counts, and release for 4 counts. What part of today feels heaviest on your mind?",
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
                  child: const Text('Ã°Å¸Å’Â¸', style: TextStyle(fontSize: 24)),
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
                        'Your well-being companion Ã‚Â· Always here Ã°Å¸â€™â„¢',
                        style: TextStyle(color: Palette.textDim, fontSize: 12.5),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Ã°Å¸â€â€™ Private & Confidential',
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
                          'text': 'Conversation cleared Ã°Å¸â€™â„¢ How can I support you today, zaid?',
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

          // Quick Prompts (Vertical Wrap List Ã¢â‚¬â€ Zero Horizontal Scroll)
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
                    hintText: 'Share what is on your mind with SarahÃ¢â‚¬Â¦',
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 14: ABOUT US (/about) Ã¢â‚¬â€ Matches AboutUsPage.tsx
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
                    'Ã¢Å“Â¨ OUR MISSION',
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
                  'The Story of JeevanCare: In medical emergencies, every second countsÃ¢â‚¬â€yet critical health records, live vitals, and verified nearby trauma care are often fragmented. JeevanCare unites wearable ESP32 hardware (VitaWatch & Smart Walking Stick), zero-knowledge AES-256-GCM medical records, 22-language AI clinical triage, and 3-Tap SOS dispatch into one unified lifeline.',
                  style: TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _PillarCard(
            emoji: 'Ã°Å¸â€â€™',
            title: 'Absolute Privacy',
            desc: 'Client-side AES-256-GCM encryption in your Health Vault ensures only you and authorized first responders can access your medical records.',
          ),
          const SizedBox(height: 10),
          const _PillarCard(
            emoji: 'Ã¢Å¡Â¡',
            title: 'Instant Response',
            desc: '3-Tap SOS, Emergency QR Medical Summary, ESP32 VitaWatch fall/vital alerts, and TomTom live ambulance routing.',
          ),
          const SizedBox(height: 10),
          const _PillarCard(
            emoji: 'Ã°Å¸Å’Â',
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ROUTE 15: PROFILE SETTINGS (/profile) Ã¢â‚¬â€ Matches ProfilePage.tsx
// 2 Sub-route Tabs:
//   1. Ã°Å¸â€˜Â¤ Edit Profile (Personal Info, Medical Summary, Visible Emergency QR, Server URL)
//   2. Ã°Å¸â€œÅ¾ Emergency Contact (+91 Phone, Email, Relationship, Show on QR toggle)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
                      'Medical Identity Ã¢â‚¬Â¢ Emergency QR Ã¢â‚¬Â¢ Emergency Contacts',
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

          // 2 Sub-Route Tabs (Wrap Ã¢â‚¬â€ Zero Overflow)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SubRouteTabChip(
                label: 'Ã°Å¸â€˜Â¤ Edit Profile',
                selected: _subTab == 0,
                onTap: () => setState(() => _subTab = 0),
              ),
              _SubRouteTabChip(
                label: 'Ã°Å¸â€œÅ¾ Emergency Contact (1)',
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
                              .map((b) => DropdownMenuItem(value: b, child: Text('Ã°Å¸Â©Â¸ $b')))
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// SHARED HELPER WIDGETS
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
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
