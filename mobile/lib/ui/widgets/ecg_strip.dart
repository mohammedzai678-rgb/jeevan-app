import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';

/// Live AD8232 single-lead ECG waveform strip with medical grid and lead-off alert.
class EcgStrip extends StatelessWidget {
  const EcgStrip({
    super.key,
    required this.samples,
    this.leadsOff = false,
    this.bpm,
  });

  final List<double> samples;
  final bool leadsOff;
  final int? bpm;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: leadsOff ? Palette.amber.withValues(alpha: 0.55) : Palette.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Palette.teal.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monitor_heart_rounded, color: Palette.teal, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ECG Lead I Trace (AD8232)',
                      style: TextStyle(color: Palette.text, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '25 mm/s • Auto-gain',
                      style: TextStyle(color: Palette.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (bpm != null && !leadsOff)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Palette.tint(Palette.teal),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$bpm BPM',
                    style: const TextStyle(
                      color: Palette.teal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: kTabular,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 124,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _EcgPainter(samples: samples, leadsOff: leadsOff),
                    ),
                  ),
                  if (leadsOff)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B2230).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Palette.amber.withValues(alpha: 0.6)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Palette.amber, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'LEADS OFF — CHECK ELECTRODES',
                              style: TextStyle(
                                color: Palette.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
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
        ],
      ),
    );
  }
}

class _EcgPainter extends CustomPainter {
  _EcgPainter({required this.samples, required this.leadsOff});

  final List<double> samples;
  final bool leadsOff;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF080E1A));

    // Subtle medical grid
    final minorGrid = Paint()
      ..color = Palette.teal.withValues(alpha: 0.05)
      ..strokeWidth = 0.6;
    final majorGrid = Paint()
      ..color = Palette.teal.withValues(alpha: 0.11)
      ..strokeWidth = 0.9;

    const step = 12.0;
    var idx = 0;
    for (double x = 0; x <= size.width; x += step, idx++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), idx % 5 == 0 ? majorGrid : minorGrid);
    }
    idx = 0;
    for (double y = 0; y <= size.height; y += step, idx++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), idx % 5 == 0 ? majorGrid : minorGrid);
    }

    if (leadsOff || samples.length < 2) {
      final flat = Paint()
        ..color = (leadsOff ? Palette.amber : Palette.teal).withValues(alpha: 0.45)
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), flat);
      return;
    }

    var minV = samples.first;
    var maxV = samples.first;
    for (final s in samples) {
      if (s < minV) minV = s;
      if (s > maxV) maxV = s;
    }
    final span = math.max(maxV - minV, 20.0);
    final lo = minV - span * 0.15;
    final hi = maxV + span * 0.15;
    final range = hi - lo;

    final path = Path();
    final stepX = size.width / (samples.length - 1);
    for (var i = 0; i < samples.length; i++) {
      final x = i * stepX;
      final norm = ((samples[i] - lo) / range).clamp(0.0, 1.0);
      final y = size.height - norm * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final glowPaint = Paint()
      ..color = Palette.teal.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    final tracePaint = Paint()
      ..color = Palette.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, tracePaint);

    final lastNorm = ((samples.last - lo) / range).clamp(0.0, 1.0);
    final head = Offset(size.width, size.height - lastNorm * size.height);
    canvas.drawCircle(head, 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _EcgPainter oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.leadsOff != leadsOff;
}
