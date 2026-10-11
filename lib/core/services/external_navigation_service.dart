import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Robust cross-platform service for launching external GPS navigation (Google Maps, Waze, Apple Maps).
class ExternalNavigationService {
  ExternalNavigationService._();

  /// Opens turn-by-turn navigation or location pin in external maps.
  static Future<bool> openNavigation({
    required double? latitude,
    required double? longitude,
    String? title,
    String? addressFallback,
  }) async {
    final validCoords = latitude != null &&
        longitude != null &&
        latitude != 0 &&
        longitude != 0 &&
        !latitude.isNaN &&
        !longitude.isNaN;

    final encodedTitle = Uri.encodeComponent(title ?? 'Delivery Location');

    if (validCoords) {
      final lat = latitude;
      final lng = longitude;

      // 1. Android Native turn-by-turn Navigation Intent
      if (!kIsWeb && Platform.isAndroid) {
        final googleNavUri = Uri.parse(
          'google.navigation:q=$lat,$lng&mode=d',
        );
        try {
          if (await canLaunchUrl(googleNavUri)) {
            final launched = await launchUrl(
              googleNavUri,
              mode: LaunchMode.externalNonBrowserApplication,
            );
            if (launched) return true;
          }
        } catch (e) {
          debugPrint('google.navigation failed: $e');
        }

        // 2. Android geo: URI
        final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedTitle)');
        try {
          if (await canLaunchUrl(geoUri)) {
            final launched = await launchUrl(
              geoUri,
              mode: LaunchMode.externalNonBrowserApplication,
            );
            if (launched) return true;
          }
        } catch (e) {
          debugPrint('geo URI failed: $e');
        }
      }

      // 3. iOS Apple Maps
      if (!kIsWeb && Platform.isIOS) {
        final appleMapsUri = Uri.parse(
          'http://maps.apple.com/?daddr=$lat,$lng&dirflg=d',
        );
        try {
          if (await canLaunchUrl(appleMapsUri)) {
            final launched = await launchUrl(
              appleMapsUri,
              mode: LaunchMode.externalApplication,
            );
            if (launched) return true;
          }
        } catch (e) {
          debugPrint('Apple Maps failed: $e');
        }
      }

      // 4. Universal Google Maps Directions Web / App URL
      final universalDirUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      );
      try {
        final launched = await launchUrl(
          universalDirUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (e) {
        debugPrint('Universal directions failed: $e');
      }
    }

    // 5. Fallback via address search query
    final query = [
      if (title != null && title.isNotEmpty) title,
      if (addressFallback != null && addressFallback.isNotEmpty) addressFallback,
      'Philippines',
    ].join(', ');

    if (query.trim().isNotEmpty) {
      final searchUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
      );
      try {
        return await launchUrl(
          searchUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        debugPrint('Maps search query failed: $e');
      }
    }

    return false;
  }
}

