import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Jeevan brand mark: crimson squircle, white heart, ECG pulse through it.
/// Same geometry as the launcher icon (`tool/make_icon.py`).
class JeevanLogo extends StatelessWidget {
  const JeevanLogo({super.key, this.size = 40, this.shadow = true});

  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Palette.red.withValues(alpha: 0.32),
                  blurRadius: size * 0.4,
                  offset: Offset(0, size * 0.14),
                ),
              ]
            : null,
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

/// Mark + wordmark lockup: "Jeevan" in ink, "Care" in crimson.
class JeevanWordmark extends StatelessWidget {
  const JeevanWordmark({super.key, this.logoSize = 34, this.fontSize = 20, this.light = false});

  final double logoSize;
  final double fontSize;

  /// White wordmark for use on the crimson hero.
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JeevanLogo(size: logoSize),
        SizedBox(width: logoSize * 0.28),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1,
            ),
            children: [
              TextSpan(
                text: 'Jeevan',
                style: TextStyle(color: light ? Colors.white : Palette.text),
              ),
              TextSpan(
                text: 'Care',
                style: TextStyle(color: light ? const Color(0xFFFFD5D9) : Palette.red),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  static Path _heart(double box, double ox, double oy) {
    Offset p(double x, double y) => Offset(ox + x / 100 * box, oy + y / 100 * box);
    final path = Path()..moveTo(p(50, 88).dx, p(50, 88).dy);
    void c(double x1, double y1, double x2, double y2, double x3, double y3) {
      path.cubicTo(p(x1, y1).dx, p(x1, y1).dy, p(x2, y2).dx, p(x2, y2).dy, p(x3, y3).dx, p(x3, y3).dy);
    }

    c(20, 66, 8, 48, 8, 32);
    c(8, 18, 19, 10, 30, 10);
    c(39, 10, 46, 15, 50, 22);
    c(54, 15, 61, 10, 70, 10);
    c(81, 10, 92, 18, 92, 32);
    c(92, 48, 80, 66, 50, 88);
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.26));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF5E6C), Color(0xFFCD1F34)],
        ).createShader(Offset.zero & size),
    );

    final box = s * 0.62;
    final ox = (s - box) / 2;
    final oy = (s - box) / 2 + s * 0.012;

    canvas.drawPath(
      _heart(box, ox, oy + s * 0.012),
      Paint()..color = const Color(0xFF780014).withValues(alpha: 0.28),
    );
    canvas.drawPath(_heart(box, ox, oy), Paint()..color = Colors.white);

    Offset p(double x, double y) => Offset(ox + x / 100 * box, oy + y / 100 * box);
    final pulse = Path()
      ..moveTo(p(20, 50).dx, p(20, 50).dy)
      ..lineTo(p(36, 50).dx, p(36, 50).dy)
      ..lineTo(p(43, 33).dx, p(43, 33).dy)
      ..lineTo(p(53, 68).dx, p(53, 68).dy)
      ..lineTo(p(60, 44).dx, p(60, 44).dy)
      ..lineTo(p(64, 50).dx, p(64, 50).dy)
      ..lineTo(p(80, 50).dx, p(80, 50).dy);
    canvas.drawPath(
      pulse,
      Paint()
        ..color = const Color(0xFFD62839)
        ..style = PaintingStyle.stroke
        ..strokeWidth = box * 0.062
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
