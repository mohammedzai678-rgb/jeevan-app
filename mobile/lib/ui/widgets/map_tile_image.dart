import 'package:flutter/material.dart';

import '../../core/config.dart';

/// Loads free OpenStreetMap tiles first and uses TomTom only when OSM fails.
class MapTileImage extends StatelessWidget {
  const MapTileImage({
    super.key,
    required this.zoom,
    required this.x,
    required this.y,
    this.fallbackApiKey = Config.tomtomApiKey,
    this.fit = BoxFit.cover,
  });

  final int zoom;
  final int x;
  final int y;
  final String fallbackApiKey;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final tileCount = 1 << zoom;
    final tileX = ((x % tileCount) + tileCount) % tileCount;
    if (y < 0 || y >= tileCount) {
      return const ColoredBox(color: Color(0xFFE8EDF0));
    }

    return Image.network(
      'https://tile.openstreetmap.org/$zoom/$tileX/$y.png',
      headers: const {
        'User-Agent': 'JeevanCare/1.0',
        'Accept': 'image/png,image/*;q=0.9,*/*;q=0.8',
      },
      fit: fit,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame != null || wasSynchronouslyLoaded
              ? child
              : const ColoredBox(color: Color(0xFFE8EDF0)),
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Map tile OSM failed at $zoom/$tileX/$y; trying TomTom.');
        if (fallbackApiKey.isEmpty) {
          return const ColoredBox(color: Color(0xFFE8EDF0));
        }
        return Image.network(
          'https://api.tomtom.com/map/1/tile/basic/main/$zoom/$tileX/$y.png?key=${Uri.encodeQueryComponent(fallbackApiKey)}',
          fit: fit,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              frame != null || wasSynchronouslyLoaded
                  ? child
                  : const ColoredBox(color: Color(0xFFE8EDF0)),
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Map tile TomTom failed at $zoom/$tileX/$y.');
            return const ColoredBox(color: Color(0xFFE8EDF0));
          },
        );
      },
    );
  }
}
// Jeevan sync: 2026-11-13
