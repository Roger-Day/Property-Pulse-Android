import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors iOS `@AppStorage("prefersDarkMode")` for explicit light/dark (not system).
class ThemeModeNotifier extends ChangeNotifier {
  ThemeModeNotifier();

  static const _prefsKey = 'prefersDarkMode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get themeMode => _mode;

  bool get prefersDarkMode => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_prefsKey) ?? false;
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDarkPreferred(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, dark);
  }
}
