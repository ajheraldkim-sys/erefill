import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _themeModeKey = 'theme_mode';
  static const _outdoorModeKey = 'is_outdoor_mode';
  static const _textScaleKey = 'text_scale';

  /// App text size range offered by the settings slider.
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.5;

  /// Combined OS x app scale is capped so layouts stay usable.
  static double combinedScale(double osScale, double appScale) =>
      (osScale * appScale).clamp(minTextScale, 1.8).toDouble();

  /// Fresh installs follow the system theme; users can switch in settings.
  ThemeMode _themeMode = ThemeMode.system;
  bool _isOutdoorMode = false;
  bool _isLoading = true;
  double _textScale = 1.0;

  ThemeProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isOutdoorMode => _isOutdoorMode;
  bool get isLoading => _isLoading;

  /// User-chosen text size multiplier (1.0 = default).
  double get textScale => _textScale;
  bool get isDarkMode =>
      !_isOutdoorMode &&
      (_themeMode == ThemeMode.dark ||
          (_themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark));

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system && !_isOutdoorMode) {
      SystemChrome.setSystemUIOverlayStyle(
        AppTheme.baseOverlayStyle(isDarkMode),
      );
      notifyListeners();
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);
    _isOutdoorMode = prefs.getBool(_outdoorModeKey) ?? false;
    _textScale = (prefs.getDouble(_textScaleKey) ?? 1.0)
        .clamp(minTextScale, maxTextScale)
        .toDouble();

    _themeMode = switch (savedMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.system,
    };

    _isLoading = false;
    SystemChrome.setSystemUIOverlayStyle(
      _isOutdoorMode
          ? AppTheme.baseOverlayStyle(false)
          : AppTheme.baseOverlayStyle(isDarkMode),
    );
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_isOutdoorMode) {
      await setOutdoorMode(false);
    }
    await setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setOutdoorMode(bool enabled) async {
    if (_isOutdoorMode == enabled) return;
    _isOutdoorMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_outdoorModeKey, enabled);

    SystemChrome.setSystemUIOverlayStyle(
      enabled
          ? AppTheme.baseOverlayStyle(false)
          : AppTheme.baseOverlayStyle(isDarkMode),
    );
    notifyListeners();
  }

  Future<void> setTextScale(double scale) async {
    final next = scale.clamp(minTextScale, maxTextScale).toDouble();
    if (next == _textScale) return;
    _textScale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, next);
  }

  Future<void> toggleOutdoorMode() => setOutdoorMode(!_isOutdoorMode);

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    SystemChrome.setSystemUIOverlayStyle(
      _isOutdoorMode
          ? AppTheme.baseOverlayStyle(false)
          : AppTheme.baseOverlayStyle(isDarkMode),
    );
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeModeKey, value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

