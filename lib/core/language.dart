import '../domain/settings.dart';

/// Which language the app is shown in right now.
///
/// All of the app's text asks this when it is built (see `Bn`), so changing
/// [current] and rebuilding the screens switches everything.
abstract final class Language {
  static AppLanguage current = AppLanguage.bangla;

  /// Numbers are always shown with English digits (0-9), in Bangla text too:
  /// that is what shopkeepers and customers read most easily on prices and
  /// quantities. (Tests of the old Bangla-digit behaviour switch this off.)
  static bool englishDigits = true;

  static bool get isBangla => current == AppLanguage.bangla;

  /// Runs [action] as if the app were in [language], then puts the language back.
  /// For things that must not change with the screen's language, e.g. the
  /// receipt a customer gets, which stays in Bangla. [action] must be
  /// synchronous: the language is only switched while it runs.
  static T runAs<T>(AppLanguage language, T Function() action) {
    final before = current;
    current = language;
    try {
      return action();
    } finally {
      current = before;
    }
  }
}

/// The text for the language in use: [bangla] or [english].
String tr(String bangla, String english) => Language.isBangla ? bangla : english;
