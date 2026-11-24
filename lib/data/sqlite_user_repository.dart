import '../domain/customer_rules.dart';
import '../domain/repositories.dart';
import '../domain/services.dart';
import '../domain/settings.dart';
import '../domain/users.dart';
import 'app_database.dart';

/// Users in the shop's database. PINs are never stored, only a salted hash.
class SqliteUserRepository implements UserRepository {
  final DatabaseProvider _database;
  final PinHasher _hasher;
  final Clock _clock;
  SqliteUserRepository(this._database, this._hasher, this._clock);

  AppUser _fromRow(Map<String, Object?> r) => AppUser(
        id: r['id'] as int,
        name: r['name'] as String,
        role: r['role'] == UserRole.owner.name ? UserRole.owner : UserRole.staff,
        active: (r['active'] as int) == 1,
        mobile: r['mobile'] as String? ?? '',
        phone: r['phone'] as String? ?? '',
        address: r['address'] as String? ?? '',
      );

  @override
  Future<bool> hasUsers() async {
    final db = await _database.db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM users');
    return (rows.first['n'] as int) > 0;
  }

  @override
  Future<List<AppUser>> all() async {
    final db = await _database.db;
    final rows = await db.query('users', orderBy: 'active DESC, name COLLATE NOCASE');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<AppUser> create({required String name, required String pin, required UserRole role}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw const AuthException(AuthProblem.invalidName);
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    final db = await _database.db;
    final taken = await db.query('users', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [cleanName], limit: 1);
    if (taken.isNotEmpty) throw const AuthException(AuthProblem.nameTaken);
    final salt = _hasher.newSalt();
    final id = await db.insert('users', {
      'name': cleanName,
      'role': role.name,
      'pin_salt': salt,
      'pin_hash': _hasher.hash(normalizePin(pin), salt),
      'active': 1,
      'created_at': _clock.now().millisecondsSinceEpoch,
    });
    return AppUser(id: id, name: cleanName, role: role);
  }

  @override
  Future<AppUser> signIn(int userId, String pin) async {
    final db = await _database.db;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw const AuthException(AuthProblem.unknownUser);
    final row = rows.first;
    final user = _fromRow(row);
    if (!user.active) throw const AuthException(AuthProblem.inactive);
    final expected = row['pin_hash'] as String;
    if (_hasher.hash(normalizePin(pin), row['pin_salt'] as String) != expected) {
      throw const AuthException(AuthProblem.wrongPin);
    }
    return user;
  }

  @override
  Future<void> setPin(int userId, String pin) async {
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    final db = await _database.db;
    final salt = _hasher.newSalt();
    final changed = await db.update(
      'users',
      {'pin_salt': salt, 'pin_hash': _hasher.hash(normalizePin(pin), salt)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (changed == 0) throw const AuthException(AuthProblem.unknownUser);
  }

  @override
  Future<void> changePin(int userId, {required String currentPin, required String newPin}) async {
    final db = await _database.db;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) throw const AuthException(AuthProblem.unknownUser);
    final row = rows.first;
    if (_hasher.hash(normalizePin(currentPin), row['pin_salt'] as String) != row['pin_hash'] as String) {
      throw const AuthException(AuthProblem.wrongPin);
    }
    await setPin(userId, newPin);
  }

  @override
  Future<AppUser> updateProfile(
    int userId, {
    required String name,
    String mobile = '',
    String phone = '',
    String address = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw const AuthException(AuthProblem.invalidName);
    final cleanMobile = mobile.trim().isEmpty ? '' : normalizeMobile(mobile);
    if (cleanMobile.isNotEmpty && !isValidMobile(cleanMobile)) throw const AuthException(AuthProblem.invalidPhone);
    final cleanPhone = phone.trim();
    if (cleanPhone.isNotEmpty && !isValidOtherPhone(cleanPhone)) throw const AuthException(AuthProblem.invalidPhone);

    final db = await _database.db;
    return db.transaction((txn) async {
      final rows = await txn.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
      if (rows.isEmpty) throw const AuthException(AuthProblem.unknownUser);
      final taken = await txn.query(
        'users',
        columns: ['id'],
        where: 'name = ? COLLATE NOCASE AND id <> ?',
        whereArgs: [cleanName, userId],
        limit: 1,
      );
      if (taken.isNotEmpty) throw const AuthException(AuthProblem.nameTaken);
      await txn.update(
        'users',
        {'name': cleanName, 'mobile': cleanMobile, 'phone': cleanPhone, 'address': address.trim()},
        where: 'id = ?',
        whereArgs: [userId],
      );
      return _fromRow((await txn.query('users', where: 'id = ?', whereArgs: [userId], limit: 1)).single);
    });
  }

  @override
  Future<void> setActive(int userId, bool active) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final rows = await txn.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
      if (rows.isEmpty) throw const AuthException(AuthProblem.unknownUser);
      final user = _fromRow(rows.first);
      if (!active && user.isOwner && user.active) {
        final others = await txn.rawQuery(
          "SELECT COUNT(*) AS n FROM users WHERE role = 'owner' AND active = 1 AND id <> ?",
          [userId],
        );
        if ((others.first['n'] as int) == 0) throw const AuthException(AuthProblem.lastOwner);
      }
      await txn.update('users', {'active': active ? 1 : 0}, where: 'id = ?', whereArgs: [userId]);
    });
  }
}
