import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Adds pinch zoom, one-finger map panning, and mouse-wheel zoom to a map.
class MapGestureLayer extends StatefulWidget {
  const MapGestureLayer({
    super.key,
    required this.child,
    required this.onPan,
    required this.onZoom,
  });

  final Widget child;
  final ValueChanged<Offset> onPan;
  final ValueChanged<int> onZoom;

  @override
  State<MapGestureLayer> createState() => _MapGestureLayerState();
}

class _MapGestureLayerState extends State<MapGestureLayer> {
  double _zoomCheckpoint = 1;

  void _handleScale(ScaleUpdateDetails details) {
    widget.onPan(details.focalPointDelta);
    final scale = details.scale;
    final difference = scale - _zoomCheckpoint;
    if (difference.abs() >= 0.22) {
      widget.onZoom(difference > 0 ? 1 : -1);
      _zoomCheckpoint = scale;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
          widget.onZoom(event.scrollDelta.dy < 0 ? 1 : -1);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => _zoomCheckpoint = 1,
        onScaleUpdate: _handleScale,
        child: widget.child,
      ),
    );
  }
}
