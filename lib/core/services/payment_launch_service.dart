import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentLaunchService {
  const PaymentLaunchService._();

  /// Attempts to launch a checkout or payment URL using multiple modes
  /// in succession to maximize compatibility across Android and iOS browsers/apps.
  static Future<bool> launchCheckoutUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      debugPrint('[PaymentLaunchService] Invalid payment URL scheme: $url');
      return false;
    }

    // 1. Try external application (allows deep linking to wallet/banking apps or external Chrome/Safari)
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (launched) return true;
    } catch (e) {
      debugPrint('[PaymentLaunchService] externalApplication failed: $e');
    }

    // 2. Try platform default (system intent handler / default browser)
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (launched) return true;
    } catch (e) {
      debugPrint('[PaymentLaunchService] platformDefault failed: $e');
    }

    // 3. Fallback to in-app browser view (Custom Tabs on Android, SFSafariViewController on iOS)
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (launched) return true;
    } catch (e) {
      debugPrint('[PaymentLaunchService] inAppBrowserView failed: $e');
    }

    return false;
  }
}

