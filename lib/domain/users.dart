import 'customer_rules.dart';

/// Owners can do everything (including the dashboard and managing staff);
/// staff sell, restock and look after customers.
enum UserRole { owner, staff }

class AppUser {
  final int id;
  final String name;
  final UserRole role;

  /// Someone who has left cannot sign in, but what they did stays on record.
  final bool active;

  /// Simple details the person keeps up to date themselves. All optional.
  final String mobile;
  final String phone;
  final String address;

  const AppUser({
    required this.id,
    required this.name,
    required this.role,
    this.active = true,
    this.mobile = '',
    this.phone = '',
    this.address = '',
  });

  bool get isOwner => role == UserRole.owner;
}

enum AuthProblem {
  /// The name is empty.
  invalidName,

  /// A PIN is 4 to 6 digits.
  invalidPin,

  /// Someone already has this name.
  nameTaken,

  /// The PIN does not match.
  wrongPin,

  /// There is no such user.
  unknownUser,

  /// The user has been switched off.
  inactive,

  /// There must always be an active owner.
  lastOwner,

  /// A phone number that is not a real number.
  invalidPhone,
}

class AuthException implements Exception {
  final AuthProblem problem;
  const AuthException(this.problem);

  @override
  String toString() => 'AuthException($problem)';
}

/// PINs are 4 to 6 digits (Bangla digits are fine).
String normalizePin(String input) => digitsOnly(input);
bool isValidPin(String input) {
  final pin = normalizePin(input);
  return pin.length >= 4 && pin.length <= 6;
}

/// A phone number other than a mobile: just digits, 6 to 15 of them.
bool isValidOtherPhone(String input) {
  final n = digitsOnly(input).length;
  return n >= 6 && n <= 15;
}

/// Who is using the app right now. Repositories ask this to record who sold
/// or stocked something; they never know how anyone signed in.
abstract class CurrentUser {
  AppUser? get user;
}

/// Nobody signed in (used by tests and anything that runs without a login).
class NoUser implements CurrentUser {
  const NoUser();
  @override
  AppUser? get user => null;
}

/// The signed-in user for this run of the app.
class Session implements CurrentUser {
  AppUser? _user;

  @override
  AppUser? get user => _user;

  void signIn(AppUser user) => _user = user;
  void signOut() => _user = null;
}
