import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Basemap style options supported by [AppMapTiles].
enum AppMapStyle {
  /// Satellite photography with roads, borders and place labels on top
  /// (Esri World Imagery + Esri reference layers).
  satelliteHybrid,

  /// Satellite photography only (Esri World Imagery).
  satellitePure,

  /// Street map (OpenStreetMap, open data).
  streets,
}

/// Shared basemap for every map in the mobile app and the admin console.
///
/// Tiles come from public services that allow direct use with credit:
/// Esri (satellite and labels) and OpenStreetMap (streets). The credit line
/// they require is drawn on every map by [layer]. Google tile URLs are not
/// used: loading them without a paid key is against Google's terms.
abstract final class AppMapTiles {
  static const String esriSatelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String esriRoadsUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}';
  static const String esriLabelsUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

  /// OpenStreetMap standard tiles (no subdomains; a valid user agent and
  /// visible credit are required by the OSM tile policy).
  static const String osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Satellite look, as before, across the app and admin.
  static const AppMapStyle defaultStyle = AppMapStyle.satelliteHybrid;

  static const String userAgentPackageName = 'com.erefill.app';

  static const _esriCredit =
      'Powered by Esri · Imagery: Maxar, Earthstar Geographics';
  static const _osmCredit = '© OpenStreetMap contributors';
  static final Uri _osmCopyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  /// The credit line [style] requires.
  static String attribution([AppMapStyle style = defaultStyle]) =>
      style == AppMapStyle.streets ? _osmCredit : _esriCredit;

  /// Base imagery tiles for [style].
  static TileLayer baseLayer({
    BuildContext? context,
    AppMapStyle style = defaultStyle,
  }) {
    final dark =
        context != null && Theme.of(context).brightness == Brightness.dark;
    return switch (style) {
      AppMapStyle.streets => TileLayer(
        urlTemplate: osmUrl,
        userAgentPackageName: userAgentPackageName,
        maxZoom: 19,
        maxNativeZoom: 19,
        tileBuilder: dark ? darkModeTileBuilder : null,
      ),
      _ => TileLayer(
        urlTemplate: esriSatelliteUrl,
        userAgentPackageName: userAgentPackageName,
        maxZoom: 20,
        maxNativeZoom: 18,
      ),
    };
  }

  /// Road and label tiles drawn over the satellite photo.
  static List<TileLayer> overlays([AppMapStyle style = defaultStyle]) =>
      style == AppMapStyle.satelliteHybrid
      ? [
          for (final url in [esriRoadsUrl, esriLabelsUrl])
            TileLayer(
              urlTemplate: url,
              userAgentPackageName: userAgentPackageName,
              maxZoom: 20,
              maxNativeZoom: 18,
            ),
        ]
      : const [];

  /// The basemap for a `FlutterMap` children list: imagery, overlays and
  /// the required credit line.
  static Widget layer({
    BuildContext? context,
    AppMapStyle style = defaultStyle,
  }) => _Basemap(
    style: style,
    base: baseLayer(context: context, style: style),
  );
}

class _Basemap extends StatelessWidget {
  const _Basemap({required this.style, required this.base});

  final AppMapStyle style;
  final TileLayer base;

  @override
  Widget build(BuildContext context) {
    final text = AppMapTiles.attribution(style);
    final isOsm = style == AppMapStyle.streets;
    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        ...AppMapTiles.overlays(style),
        Align(
          alignment: Alignment.bottomRight,
          child: Semantics(
            label: 'Map credit: $text',
            button: isOsm,
            child: GestureDetector(
              onTap: isOsm
                  ? () => launchUrl(
                      AppMapTiles._osmCopyright,
                      mode: LaunchMode.externalApplication,
                    )
                  : null,
              child: Container(
                margin: const EdgeInsets.all(2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                color: const Color(0xCCFFFFFF),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
