import 'dart:async';
import 'dart:developer';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  final supabase = Supabase.instance.client;
  StreamSubscription<Position>? _positionStream;

  Future<void> startTracking() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    await _positionStream?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (position) {
            _updateDatabase(position.latitude, position.longitude);
          },
        );
  }

  Future<void> _updateDatabase(double lat, double lng) async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // 1. Update profile (for quick lookups)
      await supabase
          .from('profiles')
          .update({'latitude': lat, 'longitude': lng})
          .eq('id', myId);

      // 2. Insert into locations history (for real-time map streaming)
      await supabase.from('rider_locations').insert({
        'rider_id': myId,
        'latitude': lat,
        'longitude': lng,
      });
    } catch (e) {
      log('Location update failed: $e');
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      log('Get current position failed: $e');
      return null;
    }
  }

  Future<void> stopTracking() async {
    await _positionStream?.cancel();
    _positionStream = null;
  }
}
