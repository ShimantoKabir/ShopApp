import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/activity.dart';
import '../../domain/repositories.dart';
import '../../domain/sync.dart';
import '../../domain/users.dart';

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
