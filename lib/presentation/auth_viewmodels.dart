import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/activity.dart';
import '../domain/repositories.dart';
import '../domain/sync.dart';
import '../domain/users.dart';

/// Signing in and out. Also creates the very first user (the owner).
class AuthViewModel extends ChangeNotifier {
  final UserRepository _users;
  final Session _session;
  final ActivityNotifier? _activity;
  final _wiped = StreamController<void>.broadcast();
  StreamSubscription<void>? _erasedSubscription;

  AuthViewModel(this._users, this._session, [this._activity, DataEraser? eraser]) {
    _erasedSubscription = eraser?.erased.listen((_) => _afterErase());
  }

  /// Fires after all data was erased (here or from another phone), once the
  /// person has been signed out. Screens opened on top should close.
  Stream<void> get wiped => _wiped.stream;

  Future<void> _afterErase() async {
    _session.signOut();
    await load();
    if (!_wiped.isClosed) _wiped.add(null);
  }

  @override
  void dispose() {
    _erasedSubscription?.cancel();
    _wiped.close();
    super.dispose();
  }

  bool loading = true;
  bool hasUsers = false;

  /// People who can sign in (switched-off users are not offered).
  List<AppUser> users = [];

  AppUser? get user => _session.user;
  bool get signedIn => _session.user != null;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    hasUsers = await _users.hasUsers();
    users = (await _users.all()).where((u) => u.active).toList();
    loading = false;
    notifyListeners();
  }

  /// First run: creates the owner and signs them in. Throws [AuthException].
  Future<void> createOwner(String name, String pin) async {
    final owner = await _users.create(name: name, pin: pin, role: UserRole.owner);
    _session.signIn(owner);
    notifyListeners();
  }

  /// Throws [AuthException] (wrongPin, inactive, unknownUser).
  Future<void> signIn(AppUser who, String pin) async {
    final user = await _users.signIn(who.id, pin);
    _session.signIn(user);
    _activity?.signedIn(user); // never waits, never fails
    notifyListeners();
  }

  Future<void> signOut() async {
    _session.signOut();
    await load();
  }
}

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
