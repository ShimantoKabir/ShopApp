import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/repositories.dart';
import '../../domain/users.dart';

/// The owner's list of people who can use the app.
class UsersViewModel extends ChangeNotifier {
  final UserRepository _users;
  final CurrentUser _current;
  UsersViewModel(this._users, this._current);

  List<AppUser> users = [];
  bool loading = true;

  AppUser? get me => _current.user;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    users = await _users.all();
    loading = false;
    notifyListeners();
  }

  /// Throws [AuthException] (invalidName, invalidPin, nameTaken).
  Future<void> add(String name, String pin, UserRole role) async {
    await _users.create(name: name, pin: pin, role: role);
    await load();
  }

  Future<void> resetPin(AppUser user, String pin) => _users.setPin(user.id, pin);

  /// Throws [AuthException] (lastOwner). You cannot switch yourself off.
  Future<void> setActive(AppUser user, bool active) async {
    if (!active && user.id == me?.id) throw const AuthException(AuthProblem.lastOwner);
    await _users.setActive(user.id, active);
    await load();
  }
}
