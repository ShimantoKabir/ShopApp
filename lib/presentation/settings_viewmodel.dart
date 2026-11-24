import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter/foundation.dart';

import '../domain/settings.dart';

/// Light, dark or follow the phone. Remembered on this device.
class ThemeViewModel extends ChangeNotifier {
  static const _key = 'theme';
  final SettingsStore _store;
  ThemeViewModel(this._store);

  ThemePreference preference = ThemePreference.system;

  ThemeMode get mode => switch (preference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      };

  Future<void> load() async {
    final saved = await _store.read(_key);
    preference = ThemePreference.values.firstWhere((p) => p.name == saved, orElse: () => ThemePreference.system);
    notifyListeners();
  }

  Future<void> choose(ThemePreference chosen) async {
    if (chosen == preference) return;
    preference = chosen;
    notifyListeners();
    await _store.write(_key, chosen.name);
  }
}
