import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';

/// Animated circular arc gauge showing the composite clinical risk score (0-100).
class RiskRing extends StatelessWidget {
  const RiskRing({
    super.key,
    required this.score,
    required this.status,
    this.size = 104,
  });

  final int score;
  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Palette.forStatus(status);
    final clamped = score.clamp(0, 100).toDouble();

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: clamped),
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        builder: (context, val, _) {
          return CustomPaint(
            painter: _RingPainter(progress: val / 100.0, color: color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${val.round()}',
                    style: const TextStyle(
                      color: Palette.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      fontFeatures: kTabular,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const double _startAngle = 0.75 * math.pi;
  static const double _sweepTotal = 1.5 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);

    final trackPaint = Paint()
      ..color = Palette.outline.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);

    final sweep = (_sweepTotal * progress.clamp(0.02, 1.0));
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(rect, _startAngle, sweep, false, glowPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
// Jeevan sync: 2026-11-13
