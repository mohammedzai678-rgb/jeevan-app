import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';

/// Live vital card with tabular numerals, status pill, and smooth sparkline.
class VitalTile extends StatelessWidget {
  const VitalTile({
    super.key,
    required this.label,
    required this.unit,
    required this.icon,
    required this.color,
    required this.status,
    this.value,
    this.sparkline,
    this.subtitle,
  });

  final String label;
  final String? value;
  final String unit;
  final Widget icon;
  final Color color;
  final String status;
  final List<double>? sparkline;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    final hasSpark = sparkline != null && sparkline!.length > 1;
    final borderTint = status == 'critical'
        ? Palette.red.withValues(alpha: 0.55)
        : status == 'warning'
            ? Palette.orange.withValues(alpha: 0.45)
            : Palette.outline;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      borderColor: borderTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Palette.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasValue) StatusPill(status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                child: Text(
                  hasValue ? value! : '--',
                  key: ValueKey<String>(value ?? '--'),
                  style: TextStyle(
                    color: hasValue ? Palette.text : Palette.textDim,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    fontFeatures: kTabular,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: const TextStyle(
                  color: Palette.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasSpark)
            SizedBox(
              height: 30,
              width: double.infinity,
              child: CustomPaint(
                painter: _SparklinePainter(values: sparkline!, color: color),
              ),
            )
          else
            Text(
              subtitle ?? (hasValue ? 'Live telemetry' : 'Awaiting sensor…'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Palette.textDim, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final span = math.max(maxV - minV, 1.0);
    final pad = span * 0.15;
    final lo = minV - pad;
    final hi = maxV + pad;
    final range = hi - lo;

    final path = Path();
    final stepX = size.width / (values.length - 1);

    Offset pt(int i) {
      final x = i * stepX;
      final norm = ((values[i] - lo) / range).clamp(0.0, 1.0);
      final y = size.height - norm * size.height;
      return Offset(x, y);
    }

    final first = pt(0);
    path.moveTo(first.dx, first.dy);
    for (var i = 0; i < values.length - 1; i++) {
      final p0 = pt(i);
      final p1 = pt(i + 1);
      final midX = (p0.dx + p1.dx) / 2;
      path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    final last = pt(values.length - 1);
    canvas.drawCircle(last, 3.0, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
