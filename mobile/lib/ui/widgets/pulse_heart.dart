import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Heart icon synchronized with the live heart-rate cadence.
class PulseHeart extends StatefulWidget {
  const PulseHeart({super.key, this.bpm, this.size = 22});

  final int? bpm;
  final double size;

  @override
  State<PulseHeart> createState() => _PulseHeartState();
}

class _PulseHeartState extends State<PulseHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 1.24).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.24, end: 1.0).chain(CurveTween(curve: Curves.easeInCubic)),
      weight: 65,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    _syncCadence();
  }

  @override
  void didUpdateWidget(covariant PulseHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bpm != widget.bpm) _syncCadence();
  }

  void _syncCadence() {
    final bpm = widget.bpm;
    if (bpm != null && bpm > 0) {
      final ms = (60000 / bpm).round().clamp(300, 1500);
      _controller.duration = Duration(milliseconds: ms);
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(
        Icons.favorite_rounded,
        color: Palette.red,
        size: widget.size,
      ),
    );
  }
}
