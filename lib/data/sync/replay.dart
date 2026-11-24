import 'package:sqflite/sqflite.dart';

import '../../domain/services.dart';
import '../../domain/settings.dart';
import '../../domain/users.dart';
import '../app_database.dart';

// What it takes to run a repository against a change from the log so that it
// gives the same result on every phone: the time, the person and any random
// value all come from the entry instead of from this phone.

/// The clock reads the time written in the entry being replayed.
class ReplayClock implements Clock {
  DateTime current = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  DateTime now() => current;
}

/// The person who did the change being replayed.
class ReplayActor implements CurrentUser {
  @override
  AppUser? user;
}

/// A location's QR code, chosen on the phone that made it.
class ReplayCodes implements LocationCodeGenerator {
  String? next;

  @override
  String generate() => next ?? (throw StateError('no recorded location code'));
}

/// A PIN's salt and hash, worked out on the phone where the PIN was typed. The
/// PIN itself never goes in the log, so replay must not (and cannot) hash it.
class ReplayHasher implements PinHasher {
  String? salt;
  String? hashOverride;

  @override
  String newSalt() => salt ?? (throw StateError('no recorded salt'));

  @override
  String hash(String pin, String salt) => hashOverride ?? (throw StateError('no recorded hash'));
}

/// Gives repositories a database whose "transactions" all join the one real
/// transaction opened by [inTransaction]. That makes a replayed change and
/// the note of how far we have got commit together (or not at all), however
/// many statements the repository uses.
class ReplayDatabase implements DatabaseProvider {
  final AppDatabase _app;
  Transaction? _current;
  late final _JoiningDatabase _joining = _JoiningDatabase(this);

  ReplayDatabase(this._app);

  @override
  Future<Database> get db async => _joining;

  Transaction get _txn => _current ?? (throw StateError('replay used outside its transaction'));

  /// Runs [body] in one real transaction. If it throws, everything it did is
  /// undone.
  Future<T> inTransaction<T>(Future<T> Function() body) async {
    final real = await _app.db;
    return real.transaction((txn) async {
      _current = txn;
      try {
        return await body();
      } finally {
        _current = null;
      }
    });
  }

  /// A note kept beside the data (never shared). Inside [inTransaction] it is
  /// part of that transaction.
  Future<void> setState(String key, String value) async {
    final executor = _current ?? await _app.db;
    await executor.insert('sync_state', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getState(String key) async {
    final db = await _app.db;
    final rows = await db.query('sync_state', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }
}

/// A [Database] that sends everything to the transaction replay has open.
/// Only what the shop's repositories use is provided.
class _JoiningDatabase implements Database {
  final ReplayDatabase _owner;
  _JoiningDatabase(this._owner);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) =>
      action(_owner._txn);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _owner._txn.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
      _owner._txn.rawQuery(sql, arguments);

  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _owner._txn.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) => _owner._txn.rawInsert(sql, arguments);

  @override
  Future<int> update(String table, Map<String, Object?> values,
          {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) =>
      _owner._txn.update(table, values, where: where, whereArgs: whereArgs, conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) => _owner._txn.rawUpdate(sql, arguments);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _owner._txn.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) => _owner._txn.rawDelete(sql, arguments);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => _owner._txn.execute(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not available during replay');
}
