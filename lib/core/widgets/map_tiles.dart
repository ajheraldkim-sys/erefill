import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Basemap style options supported by [AppMapTiles].
enum AppMapStyle {
  /// Satellite Hybrid basemap: real high-res satellite photography with roads,
  /// highways, barangay borders, and street labels (Google Maps Hybrid).
  satelliteHybrid,

  /// Pure satellite photography without roads or text overlays (ESRI World Imagery).
  satellitePure,

  /// Standard vector streets basemap (OpenStreetMap).
  streets,
}

/// Shared map tile configuration across all screens in the mobile app and admin console.
/// Configured to default to Satellite Mode everywhere.
abstract final class AppMapTiles {
  /// Google Maps Hybrid Satellite tile template (satellite imagery + roads + labels).
  static const String googleSatelliteHybridUrl =
      'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
  static const List<String> googleSatelliteSubdomains = ['0', '1', '2', '3'];

  /// Esri World Imagery (ArcGIS satellite photography).
  static const String esriSatelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Standard OpenStreetMap fallback.
  static const String osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const List<String> osmSubdomains = ['a', 'b', 'c'];

  /// Active default basemap style: Satellite Hybrid mode.
  static const AppMapStyle defaultStyle = AppMapStyle.satelliteHybrid;

  static const String userAgentPackageName = 'com.erefill.app';

  /// URL template for the active satellite hybrid basemap.
  static String get urlTemplate => googleSatelliteHybridUrl;

  /// Subdomains for the active satellite hybrid basemap.
  static List<String> get subdomains => googleSatelliteSubdomains;

  /// Creates a [TileLayer] configured with satellite hybrid imagery.
  ///
  /// Defaults to satellite mode ([AppMapStyle.satelliteHybrid]).
  static TileLayer layer({
    BuildContext? context,
    AppMapStyle style = AppMapStyle.satelliteHybrid,
  }) {
    final useDarkTiles =
        context != null && Theme.of(context).brightness == Brightness.dark;

    final String effectiveUrl;
    final List<String> effectiveSubdomains;
    final double maxZoom;
    final int maxNativeZoom;

    switch (style) {
      case AppMapStyle.satelliteHybrid:
        effectiveUrl = googleSatelliteHybridUrl;
        effectiveSubdomains = googleSatelliteSubdomains;
        maxZoom = 20.0;
        maxNativeZoom = 19;
      case AppMapStyle.satellitePure:
        effectiveUrl = esriSatelliteUrl;
        effectiveSubdomains = const [];
        maxZoom = 19.0;
        maxNativeZoom = 18;
      case AppMapStyle.streets:
        effectiveUrl = osmUrl;
        effectiveSubdomains = osmSubdomains;
        maxZoom = 19.0;
        maxNativeZoom = 18;
    }

    return TileLayer(
      urlTemplate: effectiveUrl,
      subdomains: effectiveSubdomains,
      userAgentPackageName: userAgentPackageName,
      maxZoom: maxZoom,
      maxNativeZoom: maxNativeZoom,
      tileBuilder: useDarkTiles && style == AppMapStyle.streets
          ? darkModeTileBuilder
          : null,
      retinaMode: false,
    );
  }
}
