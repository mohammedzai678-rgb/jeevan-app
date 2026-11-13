import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../data/ble_service.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import 'walking_stick_screen.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final _pairController = TextEditingController(text: 'esp32_jeevancare_01');
  bool _pairing = false;
  String? _connectingBleId;

  static final _idRegex = RegExp(r'^[A-Za-z0-9_-]{3,64}$');

  @override
  void dispose() {
    _pairController.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      await ref.read(bleProvider).scan();
    } catch (e) {
      if (mounted) showSnack(context, 'Bluetooth scan failed: $e', error: true);
    }
  }

  Future<void> _connectBle(String remoteId) async {
    setState(() => _connectingBleId = remoteId);
    try {
      await ref.read(bleProvider).connect(remoteId);
      if (mounted) showSnack(context, 'Connected to VitaWatch over BLE.');
    } catch (e) {
      if (mounted) showSnack(context, 'BLE connect failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _connectingBleId = null);
    }
  }

  Future<void> _disconnectBle() async {
    try {
      await ref.read(bleProvider).disconnect();
      if (mounted) showSnack(context, 'Bluetooth disconnected.');
    } catch (e) {
      if (mounted) showSnack(context, 'Disconnect failed: $e', error: true);
    }
  }

  Future<void> _pairDevice() async {
    final id = _pairController.text.trim();
    if (!_idRegex.hasMatch(id)) {
      showSnack(
        context,
        'Device ID must be 3–64 characters (letters, digits, _ or -).',
        error: true,
      );
      return;
    }
    setState(() => _pairing = true);
    try {
      await ref.read(devicesProvider.notifier).pair(id);
      if (mounted) showSnack(context, 'Paired device $id.');
    } catch (e) {
      if (mounted) showSnack(context, 'Pairing failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _unpairDevice(String id) async {
    try {
      await ref.read(devicesProvider.notifier).unpair(id);
      if (mounted) showSnack(context, 'Unpaired $id.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not unpair: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleStateProvider).valueOrNull ?? BleState.idle;
    final foundBle = ref.watch(bleScanProvider).valueOrNull ?? const <BleDevice>[];
    final bleService = ref.watch(bleProvider);
    final devicesState = ref.watch(devicesProvider);
    final cloudDevices = devicesState.devices.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardware & Connectivity'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: ConnectionBadge(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Palette.teal,
        backgroundColor: Palette.surfaceHi,
        onRefresh: () => ref.read(devicesProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
          children: [
            // Section 1: Direct Bluetooth
            SectionHeader(
              'Direct Bluetooth (Ultra-Low Latency ~40ms)',
              action: TextButton.icon(
                onPressed: bleState == BleState.scanning ? null : _startBleScan,
                icon: bleState == BleState.scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Palette.teal),
                        ),
                      )
                    : const Icon(Icons.bluetooth_searching_rounded, size: 18),
                label: Text(bleState == BleState.scanning ? 'Scanning…' : 'Scan Watch'),
              ),
            ),
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: bleState == BleState.connected
                  ? Palette.teal.withValues(alpha: 0.55)
                  : Palette.outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Palette.teal.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          bleState == BleState.connected
                              ? Icons.bluetooth_connected_rounded
                              : Icons.bluetooth_rounded,
                          color: Palette.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bleState == BleState.connected
                                  ? 'Connected to ${bleService.connectedName ?? 'VitaWatch'}'
                                  : bleState == BleState.connecting
                                      ? 'Connecting to VitaWatch…'
                                      : 'Direct GATT Telemetry Link',
                              style: const TextStyle(
                                color: Palette.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Streams vitals directly from ESP32 without Wi-Fi and forwards to cloud.',
                              style: TextStyle(color: Palette.textDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      if (bleState == BleState.connected)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Palette.red,
                            side: BorderSide(color: Palette.red.withValues(alpha: 0.5)),
                          ),
                          onPressed: _disconnectBle,
                          child: const Text('Disconnect'),
                        ),
                    ],
                  ),
                  if (foundBle.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(color: Palette.outline, height: 1),
                    const SizedBox(height: 10),
                    for (final dev in foundBle)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            _RssiBars(rssi: dev.rssi),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dev.name,
                                    style: const TextStyle(
                                      color: Palette.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${dev.id} • ${dev.rssi} dBm',
                                    style: const TextStyle(
                                      color: Palette.textDim,
                                      fontSize: 11,
                                      fontFeatures: kTabular,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                backgroundColor: Palette.teal.withValues(alpha: 0.18),
                                foregroundColor: Palette.teal,
                              ),
                              onPressed: _connectingBleId == dev.id
                                  ? null
                                  : () => _connectBle(dev.id),
                              child: Text(_connectingBleId == dev.id ? 'Linking…' : 'Connect'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Section 2: Paired Cloud / Wi-Fi Devices
            const SectionHeader('Paired Cloud / Wi-Fi Devices'),
            if (cloudDevices.isEmpty)
              const EmptyState(
                Icons.router_rounded,
                'No Cloud Devices Linked',
                'Enter your ESP32 device ID below to link your VitaWatch or Smart Walking Stick.',
              )
            else
              for (final d in cloudDevices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderColor: devicesState.selected == d.deviceId
                        ? Palette.teal
                        : Palette.outline,
                    onTap: () => ref.read(devicesProvider.notifier).select(d.deviceId),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d.online ? Palette.green : Palette.textDim,
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
                                      d.deviceId,
                                      style: const TextStyle(
                                        color: Palette.text,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (devicesState.selected == d.deviceId) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Palette.teal.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Palette.teal,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${d.online ? 'Online' : 'Offline'} • Sensor: ${sensorLabel(d.sensor)}'
                                '${d.rssi != null ? ' • ${d.rssi} dBm' : ''}',
                                style: const TextStyle(color: Palette.textDim, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Unpair device',
                          onPressed: () => _unpairDevice(d.deviceId),
                          icon: const Icon(Icons.link_off_rounded, color: Palette.textDim),
                        ),
                      ],
                    ),
                  ),
                ),

            const SizedBox(height: 16),

            // Pair new device card
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pair VitaWatch / Walking Stick',
                    style: TextStyle(
                      color: Palette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Enter the hardware ID flashed on your ESP32 firmware (e.g. esp32_jeevancare_01).',
                    style: TextStyle(color: Palette.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pairController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _pairDevice(),
                    decoration: const InputDecoration(
                      labelText: 'Hardware Device ID',
                      hintText: 'esp32_jeevancare_01',
                      prefixIcon: Icon(Icons.watch_outlined, color: Palette.teal),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _pairing ? null : _pairDevice,
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(_pairing ? 'Pairing…' : 'Pair Device'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            const SectionHeader('Smart Walking Stick (ESP32 #2) & Geofence'),
            GlassCard(
              padding: const EdgeInsets.all(16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WalkingStickScreen()),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Palette.blue.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.radar_rounded, color: Palette.blue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart Walking Stick Console',
                          style: TextStyle(color: Palette.text, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Live 3-zone ultrasonic obstacle radar, LDR auto-headlight & safe-zone geofence perimeter',
                          style: TextStyle(color: Palette.textDim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RssiBars extends StatelessWidget {
  const _RssiBars({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final bars = rssi >= -60
        ? 4
        : rssi >= -72
            ? 3
            : rssi >= -84
                ? 2
                : 1;
    final color = bars >= 3
        ? Palette.green
        : bars == 2
            ? Palette.amber
            : Palette.red;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          width: 4,
          height: 6.0 + i * 4.0,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? color : Palette.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
// Jeevan sync: 2026-11-13
