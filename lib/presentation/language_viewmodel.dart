import 'package:flutter/foundation.dart';

import '../core/language.dart';
import '../domain/settings.dart';

/// The language the app is shown in (Bangla or English). Remembered on this
/// phone only. Changing it switches [Language.current], which all the app's
/// text reads when it is built.
class LanguageViewModel extends ChangeNotifier {
  static const _key = 'language';
  final SettingsStore _store;
  LanguageViewModel(this._store);

  AppLanguage get language => Language.current;

  /// Reads what was chosen last time (Bangla if nothing was).
  Future<void> load() async {
    final saved = await _store.read(_key);
    Language.current = AppLanguage.values.firstWhere((l) => l.name == saved, orElse: () => AppLanguage.bangla);
    notifyListeners();
  }

  Future<void> choose(AppLanguage chosen) async {
    if (chosen == Language.current) return;
    Language.current = chosen;
    notifyListeners();
    await _store.write(_key, chosen.name);
  }
}
