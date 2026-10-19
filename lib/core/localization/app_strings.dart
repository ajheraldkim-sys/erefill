import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported languages across Cantilan, Madrid, and Caraga Region.
enum AppLanguage {
  english('en', 'English', 'English'),
  filipino('fil', 'Filipino', 'Tagalog'),
  bisaya('ceb', 'Bisaya', 'Cebuano / Surigaonon');

  final String code;
  final String label;
  final String subtitle;

  const AppLanguage(this.code, this.label, this.subtitle);

  static AppLanguage fromCode(String? code) {
    return switch (code) {
      'fil' => AppLanguage.filipino,
      'ceb' => AppLanguage.bisaya,
      _ => AppLanguage.english,
    };
  }
}

/// Central localized terminology focusing on plain, accessible wording for water refilling operations.
class AppStrings {
  // Common terms
  static String gallons(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Mga Galon',
        AppLanguage.bisaya => 'Mga Galon',
        AppLanguage.english => 'Gallons',
      };

  static String total(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Kabuuan',
        AppLanguage.bisaya => 'Tanan',
        AppLanguage.english => 'Total',
      };

  static String payOnDelivery(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Bayad pagka-deliver',
        AppLanguage.bisaya => 'Bayad inig abot',
        AppLanguage.english => 'Pay on delivery',
      };

  static String reorder(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Ulitin ang Order',
        AppLanguage.bisaya => 'Ordera Pag-usab',
        AppLanguage.english => 'Reorder',
      };

  static String swapContainer(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Ibigay ang basyong galon, walang deposito',
        AppLanguage.bisaya => 'Ihatag ang haw-ang nga galon, walay deposito',
        AppLanguage.english => 'Hand over your empty gallon, no deposit',
      };

  static String buyContainer(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Bumili o magdeposito ng bagong galon',
        AppLanguage.bisaya => 'Palit o magdeposito ug bag-ong galon',
        AppLanguage.english => 'Buy or deposit new container',
      };

  static String offlineSaved(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino =>
          'Walang signal. Naka-save ang iyong order at ipadadala pag online ka na.',
        AppLanguage.bisaya =>
          'Walay signal. Na-save imong order ug ipadala inig balik sa signal.',
        AppLanguage.english =>
          'No signal. Your order is saved and will send when you are online.',
      };

  static String verifiedStation(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Beripikadong Istasyon',
        AppLanguage.bisaya => 'Beripikadong Estasyon',
        AppLanguage.english => 'Verified Station',
      };

  static String sanitaryPermitValid(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'May Balidong Sanitary Permit',
        AppLanguage.bisaya => 'May Balidong Sanitary Permit',
        AppLanguage.english => 'Sanitary Permit Valid',
      };

  static String confirmed(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Kumpirmado',
        AppLanguage.bisaya => 'Kumpirmado',
        AppLanguage.english => 'Confirmed',
      };

  static String preparing(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Inihahanda',
        AppLanguage.bisaya => 'Gipreparar',
        AppLanguage.english => 'Preparing',
      };

  static String onTheWay(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Paparating na',
        AppLanguage.bisaya => 'Padulong na',
        AppLanguage.english => 'On the way',
      };

  static String delivered(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Naihatid na',
        AppLanguage.bisaya => 'Nahatud na',
        AppLanguage.english => 'Delivered',
      };

  static String riderNearby(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'Malapit na ang rider sa inyong bahay!',
        AppLanguage.bisaya => 'Duol na ang rider sa inyong balay!',
        AppLanguage.english => 'Rider is nearby your doorstep!',
      };

  static String collectCash(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'MANINGIL NG CASH',
        AppLanguage.bisaya => 'SINGILA ANG CASH',
        AppLanguage.english => 'COLLECT CASH',
      };

  static String paidOnline(AppLanguage lang) => switch (lang) {
        AppLanguage.filipino => 'BAYAD NA ONLINE (HUWAG MANINGIL)',
        AppLanguage.bisaya => 'BAYAD NA ONLINE (AYAW SINGILA)',
        AppLanguage.english => 'PAID ONLINE (DO NOT COLLECT)',
      };
}

/// Provider managing active language selection across customer, rider, and owner portals.
class AppLanguageProvider extends ChangeNotifier {
  static const _key = 'app_language';
  AppLanguage _language = AppLanguage.english;

  AppLanguage get language => _language;
  String get code => _language.code;

  AppLanguageProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString(_key);
      if (savedCode != null) {
        _language = AppLanguage.fromCode(savedCode);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading app language: $e');
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, language.code);
    } catch (e) {
      debugPrint('Error saving app language: $e');
    }
  }
}

