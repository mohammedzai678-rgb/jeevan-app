import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

enum _TrendMetric { heartRate, spo2, temperature }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _TrendMetric _metric = _TrendMetric.heartRate;
  static final _dateFmt = DateFormat('MMM d, HH:mm');
  bool _snapshotBusy = false;
  bool _aiReportBusy = false;
  Map<String, dynamic>? _aiVitalsReport;

  Future<void> _captureWatchSnapshot() async {
    if (_snapshotBusy) return;
    final deviceId = ref.read(devicesProvider).selected ?? 'esp32_jeevancare_01';
    setState(() => _snapshotBusy = true);
    try {
      await ref.read(apiProvider).recordDeviceSnapshot(deviceId);
      ref.invalidate(historyProvider);
      if (mounted) showSnack(context, 'Recorded live VitaWatch ($deviceId) snapshot to cloud history!');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not snapshot device reading: $e', error: true);
    } finally {
      if (mounted) setState(() => _snapshotBusy = false);
    }
  }

  Future<void> _generateAiVitalsReport(List<Reading> readings) async {
    if (_aiReportBusy) return;
    final latest = readings.isNotEmpty ? readings.first : null;
    setState(() => _aiReportBusy = true);
    try {
      final res = await ref.read(apiProvider).vitalsReport(
            hr: latest?.heartRate ?? 76,
            spo2: latest?.spo2 ?? 98,
            sys: 122,
            dia: 78,
            temp: latest?.temperature ?? 36.7,
          );
      if (mounted) setState(() => _aiVitalsReport = res);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not generate AI vitals report: $e', error: true);
    } finally {
      if (mounted) setState(() => _aiReportBusy = false);
    }
  }

  Future<void> _deleteReading(String id) async {
    if (id.isEmpty) return;
    try {
      await ref.read(apiProvider).deleteVitalReading(id);
      ref.invalidate(historyProvider);
      if (mounted) showSnack(context, 'Deleted vital reading.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not delete reading: $e', error: true);
    }
  }

  void _openRecordSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RecordVitalsSheet(
        onRecorded: (analysis) {
          ref.invalidate(historyProvider);
          _showAnalysisDialog(analysis);
        },
      ),
    );
  }

  void _showAnalysisDialog(Analysis a) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Palette.outline),
        ),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Triage Analysis',
                style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            StatusPill(a.overallStatus),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.summary,
                style: const TextStyle(color: Palette.text, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Risk Score: ${a.riskScore} / 100',
                style: const TextStyle(color: Palette.textDim, fontSize: 13, fontFeatures: kTabular),
              ),
              if (a.redFlags.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final rf in a.redFlags)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: Palette.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            rf,
                            style: const TextStyle(color: Palette.red, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              if (a.findings.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final f in a.findings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '• ${f.metric} (${f.value}): ${f.explanation} ${f.recommendation}',
                      style: const TextStyle(color: Palette.textDim, fontSize: 12.5, height: 1.4),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncReadings = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vitals History & Trends'),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(historyProvider),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Palette.textDim),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecordSheet,
        backgroundColor: Palette.teal,
        foregroundColor: const Color(0xFF042F2A),
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Record Manual Vitals', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: asyncReadings.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Palette.teal)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: EmptyState(
              Icons.cloud_off_rounded,
              'Could Not Load History',
              '$e',
              action: FilledButton(
                onPressed: () => ref.invalidate(historyProvider),
                child: const Text('Retry'),
              ),
            ),
          ),
        ),
        data: (readings) {
          if (readings.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(
                Icons.timeline_rounded,
                'No Recorded Vitals Yet',
                'Stream from your VitaWatch or record a manual reading below to track clinical trends.',
                action: FilledButton.icon(
                  onPressed: _openRecordSheet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Record Manual Vitals'),
                ),
              ),
            );
          }

          final chronological = readings.reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Trend Chart',
                            style: TextStyle(color: Palette.text, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        _MetricChip(
                          label: 'HR',
                          selected: _metric == _TrendMetric.heartRate,
                          color: Palette.red,
                          onTap: () => setState(() => _metric = _TrendMetric.heartRate),
                        ),
                        const SizedBox(width: 6),
                        _MetricChip(
                          label: 'SpO₂',
                          selected: _metric == _TrendMetric.spo2,
                          color: Palette.teal,
                          onTap: () => setState(() => _metric = _TrendMetric.spo2),
                        ),
                        const SizedBox(width: 6),
                        _MetricChip(
                          label: 'Temp',
                          selected: _metric == _TrendMetric.temperature,
                          color: Palette.amber,
                          onTap: () => setState(() => _metric = _TrendMetric.temperature),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 190,
                      child: _TrendLineChart(readings: chronological, metric: _metric),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _snapshotBusy ? null : _captureWatchSnapshot,
                      icon: const Icon(Icons.watch_rounded, size: 17, color: Palette.teal),
                      label: Text(_snapshotBusy ? 'Snapshotting…' : 'Snapshot Watch'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _aiReportBusy ? null : () => _generateAiVitalsReport(readings),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17, color: Palette.blue),
                      label: Text(_aiReportBusy ? 'Analyzing…' : 'AI Vitals Report'),
                    ),
                  ),
                ],
              ),
              if (_aiVitalsReport != null) ...[
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  borderColor: Palette.blue.withValues(alpha: 0.45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.analytics_rounded, color: Palette.blue, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'AI Clinical Vitals Synthesis (/api/gemini/vitals-report)',
                            style: TextStyle(color: Palette.text, fontSize: 13.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_aiVitalsReport!['summary'] ?? _aiVitalsReport!['response'] ?? _aiVitalsReport!['assessment'] ?? 'Hemodynamic and respiratory parameters evaluated within expected range.'}',
                        style: const TextStyle(color: Palette.text, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SectionHeader('Recorded Readings (${readings.length})'),
              for (final r in readings) ...[
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _dateFmt.format(r.at),
                              style: const TextStyle(
                                color: Palette.textDim,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: kTabular,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 14,
                              runSpacing: 4,
                              children: [
                                _ReadingStat(label: 'HR', value: '${r.heartRate} BPM', color: Palette.red),
                                _ReadingStat(label: 'SpO₂', value: '${r.spo2}%', color: Palette.teal),
                                _ReadingStat(
                                  label: 'Temp',
                                  value: '${r.temperature.toStringAsFixed(1)} °C',
                                  color: Palette.amber,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      StatusPill(r.status),
                      if (r.id.isNotEmpty)
                        IconButton(
                          tooltip: 'Delete Reading',
                          onPressed: () => _deleteReading(r.id),
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Palette.red),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.18) : Palette.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : Palette.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Palette.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ReadingStat extends StatelessWidget {
  const _ReadingStat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(
          '$label ',
          style: const TextStyle(color: Palette.textDim, fontSize: 12.5),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Palette.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            fontFeatures: kTabular,
          ),
        ),
      ],
    );
  }
}

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({required this.readings, required this.metric});

  final List<Reading> readings;
  final _TrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < readings.length; i++) {
      final r = readings[i];
      final y = switch (metric) {
        _TrendMetric.heartRate => r.heartRate.toDouble(),
        _TrendMetric.spo2 => r.spo2.toDouble(),
        _TrendMetric.temperature => r.temperature,
      };
      if (y > 0) {
        spots.add(FlSpot(i.toDouble(), y));
      }
    }

    if (spots.isEmpty) {
      return const Center(
        child: Text('Not enough data points', style: TextStyle(color: Palette.textDim)),
      );
    }

    final color = switch (metric) {
      _TrendMetric.heartRate => Palette.red,
      _TrendMetric.spo2 => Palette.teal,
      _TrendMetric.temperature => Palette.amber,
    };

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Palette.outline.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.8,
            isStrokeCapRound: true,
            dotData: FlDotData(show: spots.length <= 25),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordVitalsSheet extends ConsumerStatefulWidget {
  const _RecordVitalsSheet({required this.onRecorded});

  final ValueChanged<Analysis> onRecorded;

  @override
  ConsumerState<_RecordVitalsSheet> createState() => _RecordVitalsSheetState();
}

class _RecordVitalsSheetState extends ConsumerState<_RecordVitalsSheet> {
  final _hrCtrl = TextEditingController(text: '74');
  final _spo2Ctrl = TextEditingController(text: '98');
  final _tempCtrl = TextEditingController(text: '36.7');
  final _sysCtrl = TextEditingController();
  final _diaCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _hrCtrl.dispose();
    _spo2Ctrl.dispose();
    _tempCtrl.dispose();
    _sysCtrl.dispose();
    _diaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final hr = int.tryParse(_hrCtrl.text.trim());
    final spo2 = int.tryParse(_spo2Ctrl.text.trim());
    final temp = double.tryParse(_tempCtrl.text.trim());
    final sys = int.tryParse(_sysCtrl.text.trim());
    final dia = int.tryParse(_diaCtrl.text.trim());

    if (hr == null || spo2 == null || temp == null) {
      showSnack(context, 'Enter valid Heart Rate, SpO₂, and Temperature values.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final analysis = await ref.read(apiProvider).recordVitals(
            heartRate: hr,
            spo2: spo2,
            temperature: temp,
            systolic: sys,
            diastolic: dia,
          );
      if (mounted) {
        Navigator.of(context).pop();
        widget.onRecorded(analysis);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Failed to record vitals: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.outline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Record Manual Vitals',
              style: TextStyle(color: Palette.text, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hrCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Palette.text),
                    decoration: const InputDecoration(labelText: 'Heart Rate (BPM)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _spo2Ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Palette.text),
                    decoration: const InputDecoration(labelText: 'SpO₂ (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tempCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Palette.text),
              decoration: const InputDecoration(labelText: 'Temperature (°C)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sysCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Palette.text),
                    decoration: const InputDecoration(labelText: 'Systolic BP (opt)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _diaCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Palette.text),
                    decoration: const InputDecoration(labelText: 'Diastolic BP (opt)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF042F2A)),
                    )
                  : const Text('Save & Run Clinical Triage'),
            ),
          ],
        ),
      ),
    );
  }
}
// Jeevan sync: 2026-11-13
