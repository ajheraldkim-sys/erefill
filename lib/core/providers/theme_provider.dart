import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _themeModeKey = 'theme_mode';

  /// Fresh installs follow the system theme; users can switch in settings.
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = true;

  ThemeProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  bool get isDarkMode =>
      _themeMode == ThemeMode.dark ||
      (_themeMode == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);

  @override
  void didChangePlatformBrightness() {
    if (_themeMode == ThemeMode.system) {
      SystemChrome.setSystemUIOverlayStyle(
        AppTheme.baseOverlayStyle(isDarkMode),
      );
      notifyListeners();
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);

    _themeMode = switch (savedMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.system,
    };

    _isLoading = false;
    SystemChrome.setSystemUIOverlayStyle(AppTheme.baseOverlayStyle(isDarkMode));
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    await setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    SystemChrome.setSystemUIOverlayStyle(AppTheme.baseOverlayStyle(isDarkMode));
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
