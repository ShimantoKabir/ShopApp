import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/repositories.dart';
import '../../domain/users.dart';

/// The signed-in person's own details and PIN.
class ProfileViewModel extends ChangeNotifier {
  final UserRepository _users;
  final Session _session;
  ProfileViewModel(this._users, this._session);

  AppUser? get user => _session.user;

  /// Saves the details. The name used on bills and stock history follows at
  /// once. Throws [AuthException] (invalidName, nameTaken, invalidPhone).
  Future<void> save({required String name, String mobile = '', String phone = '', String address = ''}) async {
    final me = _session.user!;
    final updated = await _users.updateProfile(me.id, name: name, mobile: mobile, phone: phone, address: address);
    _session.signIn(updated);
    notifyListeners();
  }

  /// Throws [AuthException] (wrongPin, invalidPin).
  Future<void> changePin(String currentPin, String newPin) =>
      _users.changePin(_session.user!.id, currentPin: currentPin, newPin: newPin);
}
