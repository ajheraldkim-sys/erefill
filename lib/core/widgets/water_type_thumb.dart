import 'package:flutter/material.dart';

import '../constants.dart';
import '../water_types.dart';
import 'app_cached_image.dart';

/// A water type's product photo, or its tinted icon when no photo is set.
class WaterTypeThumb extends StatelessWidget {
  const WaterTypeThumb({
    super.key,
    required this.type,
    required this.size,
    this.radius = AppUi.radiusCard,
    this.iconSize,
  });

  final WaterTypeInfo type;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final photoUrl = type.photoUrl;
    final borderRadius = BorderRadius.circular(radius);
    if (photoUrl != null) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return AppCachedImage(
        imageUrl: photoUrl,
        width: size,
        height: size,
        borderRadius: borderRadius,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
        fallbackIcon: type.icon,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: type.color.withValues(alpha: 0.12),
        borderRadius: borderRadius,
      ),
      child: Icon(type.icon, color: type.color, size: iconSize ?? size / 2),
    );
  }
}
