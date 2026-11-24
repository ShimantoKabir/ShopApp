/// How the app looks. Kept per device (never shared with other phones).
enum ThemePreference { system, light, dark }

/// Which language the app is shown in. Kept per device, like the theme.
enum AppLanguage { bangla, english }

/// Remembers small settings on this device.
abstract class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Turns a PIN into something safe to store.
abstract class PinHasher {
  /// A new random salt for one user.
  String newSalt();

  /// The hash to store for [pin] with [salt]. Same inputs, same output.
  String hash(String pin, String salt);
}
