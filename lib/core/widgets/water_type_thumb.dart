import 'package:flutter/material.dart';

import '../constants.dart';
import '../water_types.dart';
import 'app_cached_image.dart';

/// A water type's product photo, or its tinted icon when no photo is set.
///
/// Listens to [WaterTypes.catalog] in real time so image updates or deletions
/// reflect immediately across the UI.
class WaterTypeThumb extends StatelessWidget {
  const WaterTypeThumb({
    super.key,
    this.type,
    this.typeName,
    required this.size,
    this.radius = AppUi.radiusCard,
    this.iconSize,
  }) : assert(type != null || typeName != null, 'Either type or typeName must be provided');

  final WaterTypeInfo? type;
  final String? typeName;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<WaterTypeInfo>>(
      valueListenable: WaterTypes.catalog,
      builder: (context, _, _) {
        final currentType = WaterTypes.byName(type?.name ?? typeName);
        final photoUrl = currentType.photoUrl;
        final borderRadius = BorderRadius.circular(radius);
        if (photoUrl != null) {
          final cachePx =
              (size * MediaQuery.devicePixelRatioOf(context)).round();
          return AppCachedImage(
            imageUrl: photoUrl,
            width: size,
            height: size,
            borderRadius: borderRadius,
            memCacheWidth: cachePx,
            memCacheHeight: cachePx,
            fallbackIcon: currentType.icon,
          );
        }
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: currentType.color.withValues(alpha: 0.12),
            borderRadius: borderRadius,
          ),
          child: Icon(
            currentType.icon,
            color: currentType.color,
            size: iconSize ?? size / 2,
          ),
        );
      },
    );
  }
}
