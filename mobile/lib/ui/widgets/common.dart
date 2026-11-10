import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/ble_service.dart';
import '../../data/live_service.dart';
import '../../state/providers.dart';

/// Tabular (fixed-width) digits so live numbers don't jitter horizontally.
const kTabular = <FontFeature>[FontFeature.tabularFigures()];

/// Human label for the firmware's active sensor id.
String sensorLabel(String sensor) {
  switch (sensor) {
    case 'read_max30102':
    case 'max30102':
      return 'Pulse & SpO₂';
    case 'read_dht11':
    case 'dht11':
      return 'Temperature';
    case 'read_ad8232':
    case 'ad8232':
      return 'ECG';
    case 'auto':
      return 'Auto';
    case 'idle':
    case '':
      return 'Standby';
    default:
      return sensor;
  }
}

/// Floating snackbar with a status icon.
void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      action: action,
      content: Row(
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: error ? const Color(0xFFFF8A93) : const Color(0xFF5EE0A0),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// The one surface used everywhere: white, 20px radius, hairline border and a
/// very soft shadow for depth without noise.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
    this.borderColor,
    this.gradient,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final Gradient? gradient;
  final VoidCallback? onTap;

  static final BorderRadius _radius = BorderRadius.circular(20);

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(borderRadius: _radius, onTap: onTap, child: content);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Palette.surface) : null,
        gradient: gradient,
        borderRadius: _radius,
        border: Border.all(color: borderColor ?? Palette.outline),
        boxShadow: const [
          BoxShadow(color: Color(0x0D101828), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: content),
    );
  }
}

/// Tinted rounded-square icon chip: pastel fill + saturated glyph.
class IconChip extends StatelessWidget {
  const IconChip(this.icon, {super.key, this.color = Palette.red, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Palette.tint(color),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Small coloured status capsule: NORMAL / ATTENTION / WARNING / CRITICAL.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = Palette.forStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.tint(c),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            (label ?? status).toUpperCase(),
            style: TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

/// Connection status: a quiet dot + one word.
class ConnectionBadge extends ConsumerWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleStateProvider).valueOrNull;
    final link = ref.watch(linkStateProvider).valueOrNull ?? LinkState.offline;

    final String label;
    final Color color;
    final bool live;
    if (ble == BleState.connected) {
      label = 'Bluetooth';
      color = Palette.teal;
      live = true;
    } else if (link == LinkState.online) {
      label = 'Live';
      color = Palette.green;
      live = true;
    } else if (link == LinkState.connecting) {
      label = 'Connecting';
      color = Palette.amber;
      live = false;
    } else {
      label = 'Offline';
      color = Palette.textMuted;
      live = false;
    }

    return Semantics(
      label: 'Connection: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Palette.tint(color, 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(child: _LiveDot(color: color, pulsing: live)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color == Palette.textMuted ? Palette.textDim : color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color, required this.pulsing});
  final Color color;
  final bool pulsing;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.pulsing && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulsing)
                Container(
                  width: 6 + 6 * t,
                  height: 6 + 6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.4 * (1 - t)),
                  ),
                ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Title row above a group of cards, with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Palette.text,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Page title used at the top of every route screen.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Palette.text,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1.15,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(color: Palette.textDim, fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
}

/// Friendly placeholder for empty lists / missing setup.
class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, this.subtitle, {super.key, this.action});

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          IconChip(icon, size: 68),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.textDim, fontSize: 13.5, height: 1.45),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
