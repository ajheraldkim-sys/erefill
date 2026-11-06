import 'package:erefill/core/widgets/map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  for (final style in AppMapStyle.values) {
    testWidgets('$style basemap renders inside a map with its credit line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 300,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(9.33, 125.97),
                  initialZoom: 14,
                ),
                children: [AppMapTiles.layer(style: style)],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(AppMapTiles.attribution(style)), findsOneWidget);
      expect(
        find.byType(TileLayer),
        findsNWidgets(1 + AppMapTiles.overlays(style).length),
      );
    });
  }
}
