import '../../domain/activity.dart';
import '../../domain/entities.dart';
import '../../domain/users.dart';
import '../app_database.dart';
import '../sqlite_repositories.dart';
import '../sqlite_user_repository.dart';
import 'activity_recorder.dart';
import '../sqlite_shop_repository.dart';
import 'op_envelope.dart';
import 'replay.dart';
import 'snapshot.dart';

typedef _Handler = Future<Object?> Function(Map<String, dynamic> args);

/// Replays log entries by calling the very same repositories the app uses when
/// it is not shared, so a sale or a stock change follows exactly the same
/// rules wherever it is replayed. (Those repositories are given the entry's
/// time, person and random values instead of this phone's own.)
class OpHandlers {
  final ReplayDatabase replay;
  final ReplayClock _clock = ReplayClock();
  final ReplayActor _actor = ReplayActor();
  final ReplayCodes _codes = ReplayCodes();
  final ReplayHasher _hasher = ReplayHasher();
  late final ActivityRecorder _activity;

  late final SqliteProductRepository _products;
  late final SqliteStockRepository _stock;
  late final SqliteSalesRepository _sales;
  late final SqliteCustomerRepository _customers;
  late final SqliteCategoryRepository _categories;
  late final SqliteLocationRepository _locations;
  late final SqliteUserRepository _users;
  late final SqliteShopRepository _shop;
  late final Map<String, _Handler> _handlers;

  OpHandlers(AppDatabase app) : replay = ReplayDatabase(app) {
    _products = SqliteProductRepository(replay, _clock, actor: _actor);
    _stock = SqliteStockRepository(replay, _clock, actor: _actor);
    _sales = SqliteSalesRepository(replay, _clock, actor: _actor);
    _customers = SqliteCustomerRepository(replay, _clock, actor: _actor);
    _categories = SqliteCategoryRepository(replay);
    _locations = SqliteLocationRepository(replay, _codes);
    _users = SqliteUserRepository(replay, _hasher, _clock);
    _shop = SqliteShopRepository(replay);
    _activity = ActivityRecorder(replay);

    int i(Map<String, dynamic> a, String k) => a[k] as int;
    double d(Map<String, dynamic> a, String k) => (a[k] as num).toDouble();
    String s(Map<String, dynamic> a, String k) => a[k] as String;

    /// A PIN is never in the log: only its salt and hash, worked out where it
    /// was typed. Replay hands the repository a stand-in PIN and the recorded
    /// salt and hash.
    Future<T> withCredentials<T>(Map<String, dynamic> a, Future<T> Function() body) async {
      _hasher
        ..salt = s(a, 'salt')
        ..hashOverride = s(a, 'hash');
      try {
        return await body();
      } finally {
        _hasher
          ..salt = null
          ..hashOverride = null;
      }
    }

    const stand = '0000'; // passes the PIN-length rule; its value is never used

    _handlers = {
      'product.save': (a) => _products.save(productFromJson((a['product'] as Map).cast<String, dynamic>())),
      'product.delete': (a) => _products.delete(i(a, 'id')),
      'product.adjustStock': (a) => _products.adjustStock(i(a, 'id'), d(a, 'newTotal')),
      'stock.place': (a) => _stock.place(i(a, 'productId'), i(a, 'locationId'), d(a, 'quantity')),
      'stock.recount': (a) => _stock.recount(i(a, 'productId'), i(a, 'locationId'), d(a, 'quantity')),
      'stock.move': (a) => _stock.move(i(a, 'productId'), i(a, 'from'), i(a, 'to'), d(a, 'quantity')),
      'stock.restock': (a) => _stock.restock(
            i(a, 'productId'),
            d(a, 'quantity'),
            locationId: a['locationId'] as int?,
            purchasePrice: (a['purchasePrice'] as num?)?.toDouble(),
          ),
      'sale.checkout': (a) => _sales.checkout(
            [for (final l in (a['lines'] as List)) saleLineFromJson((l as Map).cast<String, dynamic>())],
            customer: customerFromJson((a['customer'] as Map?)?.cast<String, dynamic>()),
            paid: (a['paid'] as num?)?.toDouble(),
          ),
      'sale.attachCustomer': (a) => _sales.attachCustomer(
            i(a, 'billId'),
            customerFromJson((a['customer'] as Map).cast<String, dynamic>())!,
          ),
      'sale.void': (a) => _sales.voidBill(i(a, 'billId')),
      'payment.collect': (a) => _customers.collectPayment(i(a, 'customerId'), d(a, 'amount')),
      'category.add': (a) => _categories.add(s(a, 'name')),
      'category.edit': (a) => _categories.update(i(a, 'id'), s(a, 'name')),
      'category.delete': (a) => _categories.delete(i(a, 'id')),
      'location.add': (a) {
        _codes.next = s(a, 'code');
        return _locations.add(s(a, 'name'), LocationType.parse(s(a, 'type')));
      },
      'location.edit': (a) =>
          _locations.update(i(a, 'id'), name: s(a, 'name'), type: LocationType.parse(s(a, 'type'))),
      'locationType.rename': (a) => _locations.renameType(LocationType.parse(s(a, 'from')), s(a, 'to')),
      'locationType.delete': (a) => _locations.deleteType(LocationType.parse(s(a, 'name'))),
      'location.delete': (a) => _locations.delete(i(a, 'id')),
      'user.create': (a) => withCredentials(
            a,
            () => _users.create(name: s(a, 'name'), pin: stand, role: UserRole.values.byName(s(a, 'role'))),
          ),
      'user.setPin': (a) => withCredentials(a, () => _users.setPin(i(a, 'userId'), stand)),
      'user.updateProfile': (a) => _users.updateProfile(
            i(a, 'userId'),
            name: s(a, 'name'),
            mobile: s(a, 'mobile'),
            phone: s(a, 'phone'),
            address: s(a, 'address'),
          ),
      'user.setActive': (a) => _users.setActive(i(a, 'userId'), a['active'] as bool),
      'shop.rename': (a) => _shop.rename(s(a, 'name')),
      'activity.signedIn': (a) =>
          _activity.add(at: _clock.current.millisecondsSinceEpoch, actor: _actor.user, kind: ActivityKind.signIn),
      'import.begin': (a) => _importBegin(),
      'import.rows': (a) => _importRows(a),
      'import.end': (a) => _importEnd(a),
    };
  }

  /// True if this version of the app knows how to replay [name].
  bool handles(String name) => _handlers.containsKey(name);

  /// Replays [entry]. Must be called inside [ReplayDatabase.inTransaction].
  Future<Object?> run(OpEnvelope entry) async {
    _clock.current = DateTime.fromMillisecondsSinceEpoch(entry.at);
    _actor.user = entry.actor == null ? null : AppUser(id: entry.actor!.id, name: entry.actor!.name, role: UserRole.staff);
    // The activity entry is written in the same transaction as the change, so
    // a change that is refused leaves no entry, and every phone writes the same.
    final before = await _activity.before(entry.name, entry.args);
    final result = await _handlers[entry.name]!(entry.args);
    await _activity.after(entry.name, entry.args, before, result, at: entry.at, actor: _actor.user);
    return result;
  }

  // ---- starting a phone from a snapshot ----------------------------------

  Future<Object?> _importBegin() async {
    final db = await replay.db;
    // Rows may point at each other; they are checked when the entry commits.
    await db.execute('PRAGMA defer_foreign_keys = ON');
    for (final table in replicatedTables.reversed) {
      await db.delete(table);
    }
    await db.rawDelete('DELETE FROM sqlite_sequence');
    return null;
  }

  Future<Object?> _importRows(Map<String, dynamic> a) async {
    final table = a['table'] as String;
    if (!replicatedTables.contains(table)) throw ArgumentError('not a shop table: $table');
    final db = await replay.db;
    await db.execute('PRAGMA defer_foreign_keys = ON');
    // The phone that uploaded may have columns this one does not (a database
    // that was upgraded from an old version keeps retired ones). Only what this
    // phone's tables have is kept.
    final known = {
      for (final c in await db.rawQuery('PRAGMA table_info($table)')) c['name'] as String,
    };
    for (final row in (a['rows'] as List)) {
      final values = (row as Map).cast<String, Object?>();
      await db.insert(table, {for (final e in values.entries) if (known.contains(e.key)) e.key: e.value});
    }
    return null;
  }

  Future<Object?> _importEnd(Map<String, dynamic> a) async {
    final db = await replay.db;
    for (final entry in (a['sequences'] as List)) {
      final name = (entry as Map)['name'];
      final seq = entry['seq'];
      final changed = await db.rawUpdate('UPDATE sqlite_sequence SET seq = ? WHERE name = ?', [seq, name]);
      if (changed == 0) await db.rawInsert('INSERT INTO sqlite_sequence(name, seq) VALUES (?, ?)', [name, seq]);
    }
    return null;
  }
}
