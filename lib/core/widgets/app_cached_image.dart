import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:erefill/core/constants.dart';
import 'package:erefill/core/widgets/skeleton.dart';

/// Production-ready cached image widget utilizing Supabase CDN & cached_network_image.
///
/// Automatically limits memory footprint via [memCacheWidth] & [memCacheHeight]
/// to prevent rasterization lag and memory bloat on low-end devices.
class AppCachedImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final int memCacheWidth;
  final int memCacheHeight;
  final IconData fallbackIcon;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.memCacheWidth = 400,
    this.memCacheHeight = 400,
    this.fallbackIcon = Icons.water_drop_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();

    Widget imageContent;

    if (url == null || url.isEmpty || !url.startsWith('http')) {
      imageContent = _buildFallback(context);
    } else {
      imageContent = CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) =>
            placeholder ??
            Skeleton(
              width: width ?? double.infinity,
              height: height ?? double.infinity,
              borderRadius: borderRadius != null ? borderRadius!.topLeft.x : 8,
            ),
        errorWidget: (context, url, error) =>
            errorWidget ?? _buildFallback(context),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageContent,
      );
    }

    return imageContent;
  }

  Widget _buildFallback(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: AppUi.chipBgOf(context),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: (height != null && height! < 50) ? 20 : 32,
          color: AppUi.textSecondaryOf(context).withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
