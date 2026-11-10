import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Press-and-hold 1.5s emergency SOS trigger button with haptic ticks and progress ring.
class SosHoldButton extends ConsumerStatefulWidget {
  const SosHoldButton({super.key});

  @override
  ConsumerState<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends ConsumerState<SosHoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _hapticTimer?.cancel();
        HapticFeedback.heavyImpact();
        ref.read(sosProvider.notifier).trigger();
        _controller.value = 0;
      }
    });

  Timer? _hapticTimer;

  void _onDown(TapDownDetails _) {
    final sos = ref.read(sosProvider);
    if (sos.sending || sos.active) return;
    HapticFeedback.selectionClick();
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      HapticFeedback.selectionClick();
    });
    _controller.forward(from: 0);
  }

  void _onCancel() {
    _hapticTimer?.cancel();
    if (_controller.isAnimating) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SosState>(sosProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && context.mounted) {
        showSnack(context, 'SOS failed: ${next.error}', error: true);
      }
    });

    final sos = ref.watch(sosProvider);

    return GestureDetector(
      onTapDown: _onDown,
      onTapUp: (_) => _onCancel(),
      onTapCancel: _onCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final p = _controller.value;
          return Container(
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Palette.red,
                  Color.lerp(const Color(0xFFB91C1C), Palette.red, p)!,
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Palette.red.withValues(alpha: 0.32 + 0.28 * p),
                  blurRadius: 18 + 12 * p,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (p > 0)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: p,
                          heightFactor: 1.0,
                          child: Container(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (sos.sending)
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.8,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            else
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  value: p > 0 ? p : 1.0,
                                  strokeWidth: 2.6,
                                  backgroundColor: Colors.white.withValues(alpha: 0.24),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    p > 0 ? Colors.white : Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            const Icon(Icons.sos_rounded, color: Colors.white, size: 22),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sos.sending
                                  ? 'DISPATCHING EMERGENCY SOS…'
                                  : p > 0
                                      ? 'KEEP HOLDING… ${((1.0 - p) * 1.5).toStringAsFixed(1)}s'
                                      : 'HOLD 1.5s FOR EMERGENCY SOS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                fontFeatures: kTabular,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shares your location and alerts contacts',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
