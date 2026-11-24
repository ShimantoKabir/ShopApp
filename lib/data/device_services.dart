import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/settings.dart';

/// Salted SHA-256. (A 4-6 digit PIN is only as strong as its length: this
/// keeps PINs unreadable in the database file, it does not make them
/// unguessable by someone who copies the file.)
class Sha256PinHasher implements PinHasher {
  final Random _random;
  Sha256PinHasher([Random? random]) : _random = random ?? Random.secure();

  @override
  String newSalt() => base64Url.encode(List<int>.generate(16, (_) => _random.nextInt(256)));

  @override
  String hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
}

/// Settings kept on this phone (not in the shop database, so a shared
/// database never forces one phone's theme on another).
class PreferencesSettingsStore implements SettingsStore {
  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
