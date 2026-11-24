import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/replicated_repositories.dart';
import 'package:hardware_shop/data/sqlite_activity_repository.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/data/sqlite_shop_repository.dart';
import 'package:hardware_shop/data/sync/activity_recorder.dart';
import 'package:hardware_shop/data/sqlite_user_repository.dart';
import 'package:hardware_shop/data/sync/http_sync_transport.dart';
import 'package:hardware_shop/data/sync/op_envelope.dart';
import 'package:hardware_shop/data/sync/snapshot.dart';
import 'package:hardware_shop/data/sync/sync_engine.dart';
import 'package:hardware_shop/domain/activity.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/shop.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hardware_shop/data/starter_categories.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// A pretend server: one ordered log shared by every phone in the test.
// ---------------------------------------------------------------------------

class _Server {
  final List<RemoteOp> log = [];
  int _last = 0; // numbers keep rising, even after an erase

  int get head => _last;

  int add(String opId, String device, int at, String payload) {
    final known = log.where((o) => o.opId == opId);
    if (known.isNotEmpty) return known.first.seq;
    log.add(RemoteOp(seq: ++_last, opId: opId, device: device, at: at, payload: payload));
    return _last;
  }

  /// Like the real one: everything goes, and only the notice stays.
  int erase(String opId, String device, int at, String payload) {
    final known = log.where((o) => o.opId == opId);
    if (known.isNotEmpty) return known.first.seq;
    log.clear();
    return add(opId, device, at, payload);
  }
}

/// One phone's connection to the pretend server, with switches for bad luck.
class _Link implements SyncTransport {
  final _Server server;
  _Link(this.server);

  bool offline = false;
  bool failReads = false;
  bool rejected = false;

  /// When 0 or more: that many entries can still be added, then the signal goes.
  int failAppendsAfter = -1;

  /// The entry reaches the server but the answer is lost on the way back.
  int loseAnswers = 0;
  int appends = 0;

  void _check({bool read = false}) {
    if (rejected) throw const SyncException(SyncProblem.unauthorized);
    if (offline || (read && failReads)) throw const SyncException(SyncProblem.offline);
  }

  @override
  Future<int> head() async {
    _check();
    return server.head;
  }

  @override
  Future<({List<RemoteOp> ops, int head})> fetch(int after, {int limit = 500}) async {
    _check(read: true);
    final ops = server.log.where((o) => o.seq > after).take(limit).toList();
    return (ops: ops, head: server.head);
  }

  @override
  Future<int> erase({required String opId, required String device, required int at, required String payload}) async {
    _check();
    erases++;
    return server.erase(opId, device, at, payload);
  }

  int erases = 0;

  @override
  Future<int> append({required String opId, required String device, required int at, required String payload}) async {
    _check();
    if (failAppendsAfter == 0) throw const SyncException(SyncProblem.offline);
    if (failAppendsAfter > 0) failAppendsAfter--;
    appends++;
    final seq = server.add(opId, device, at, payload);
    if (loseAnswers > 0) {
      loseAnswers--;
      throw const SyncException(SyncProblem.offline);
    }
    return seq;
  }
}

class _Clock implements Clock {
  DateTime current;
  _Clock(this.current);
  @override
  DateTime now() => current;
}

class _Codes implements LocationCodeGenerator {
  final String prefix;
  int _n = 0;
  _Codes(this.prefix);
  @override
  String generate() => '$prefix-${_n++}';
}

/// Repeatable salts, and a real one-way hash (so the PIN is not readable in it).
class _Hasher implements PinHasher {
  int _n = 0;
  @override
  String newSalt() => 'salt${_n++}';
  @override
  String hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
}

class _MemorySettings implements SettingsStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

const _url = 'https://shop.example';
const _key = 'secret';

/// A phone: its own database, its own repositories, its own connection.
class _Phone {
  final String name;
  final AppDatabase db;
  final _Clock clock;
  final Session session = Session();
  final _MemorySettings settings = _MemorySettings();
  final _Link link;
  late final SyncEngine engine;
  late final _Hasher hasher;

  late final ProductRepository products;
  late final StockRepository stock;
  late final SalesRepository sales;
  late final CustomerRepository customers;
  late final CategoryRepository categories;
  late final LocationRepository locations;
  late final UserRepository users;
  late final ActivityRepository activity;
  late final ShopRepository shop;
  late final ActivityNotifier notifier;

  _Phone._(this.name, this.db, this.clock, this.link);

  static Future<_Phone> start(String name, _Server server, {DateTime? now, SyncTransportFactory? transport}) async {
    final file = 'sync_test_$name.db';
    await deleteDatabase(p.join(await getDatabasesPath(), file));
    final phone = _Phone._(name, AppDatabase(fileName: file), _Clock(now ?? DateTime(2026, 11, 22, 10)), _Link(server));
    phone.hasher = _Hasher();
    phone.engine = SyncEngine(
      database: phone.db,
      settings: phone.settings,
      transportFactory: transport ?? (_) => phone.link,
      clock: phone.clock,
      actor: phone.session,
      pause: (_) async {},
      newId: () => '$name-${phone._ids++}-padding',
    );
    final codes = _Codes(name);
    phone.products = ReplicatedProductRepository(SqliteProductRepository(phone.db, phone.clock, actor: phone.session), phone.engine);
    phone.stock = ReplicatedStockRepository(SqliteStockRepository(phone.db, phone.clock, actor: phone.session), phone.engine);
    phone.sales = ReplicatedSalesRepository(SqliteSalesRepository(phone.db, phone.clock, actor: phone.session), phone.engine);
    phone.customers = ReplicatedCustomerRepository(SqliteCustomerRepository(phone.db, phone.clock, actor: phone.session), phone.engine);
    phone.categories = ReplicatedCategoryRepository(SqliteCategoryRepository(phone.db), phone.engine);
    phone.locations = ReplicatedLocationRepository(SqliteLocationRepository(phone.db, codes), phone.engine, codes);
    phone.users = ReplicatedUserRepository(SqliteUserRepository(phone.db, phone.hasher, phone.clock), phone.engine, phone.hasher);
    phone.shop = ReplicatedShopRepository(SqliteShopRepository(phone.db), phone.engine);
    phone.activity = SqliteActivityRepository(phone.db);
    phone.notifier = GatewayActivityNotifier(phone.engine, ActivityRecorder(phone.db), () => phone.clock.now().millisecondsSinceEpoch);
    await phone.engine.load();
    return phone;
  }

  int _ids = 0;

  Future<void> connect() => engine.connect(url: _url, key: _key);

  /// Everything the shop holds, in a form that can be compared between phones.
  Future<String> dump() async {
    final d = await db.db;
    final out = <String, Object?>{};
    for (final table in replicatedTables) {
      out[table] = await d.query(table, orderBy: 'rowid');
    }
    out['sqlite_sequence'] = await d.rawQuery('SELECT name, seq FROM sqlite_sequence ORDER BY name');
    return jsonEncode(out);
  }

  Future<void> close() async => (await db.db).close();
}

Matcher throwsSync(SyncProblem problem) => throwsA(isA<SyncException>().having((e) => e.problem, 'problem', problem));
Matcher throwsStock(StockProblem problem) => throwsA(isA<StockException>().having((e) => e.problem, 'problem', problem));

const _rahim = CustomerInfo(
  name: 'রহিম',
  mobile: '01712345678',
  nid: '1234567890',
  address: 'কাজিপুর',
  whatsapp: '01712345678',
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _Server server;
  late _Phone a;
  late _Phone b;
  late _Phone c;

  setUp(() async {
    server = _Server();
    a = await _Phone.start('a', server);
    b = await _Phone.start('b', server, now: DateTime(2026, 11, 22, 11));
    c = await _Phone.start('c', server, now: DateTime(2026, 11, 22, 12));
  });

  tearDown(() async {
    for (final phone in [a, b, c]) {
      await phone.close();
    }
  });

  /// Phone A has run the shop alone: an owner, a category, a shelf, products.
  Future<({AppUser owner, Product nails, Product wire, StorageLocation shelf})> shopOnA({double nailsStock = 10}) async {
    final owner = await a.users.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
    a.session.signIn(owner);
    final cat = await a.categories.add('পেরেক');
    final shelf = await a.locations.add('তাক ক', LocationType.shelf);
    final nails = await a.products.save(Product(
      name: 'পেরেক',
      kind: ProductKind.loose,
      categoryId: cat.id,
      purchasePrice: 80,
      sellingPrice: 100,
      stock: nailsStock,
      unit: 'কেজি',
      placements: [StockPlacement(locationId: shelf.id!, quantity: nailsStock / 2)],
    ));
    final wire = await a.products.save(const Product(
        name: 'তার', kind: ProductKind.loose, purchasePrice: 50, sellingPrice: 70, stock: 5, unit: 'মিটার'));
    return (owner: owner, nails: nails, wire: wire, shelf: shelf);
  }

  /// A shares the shop and B and C join it.
  Future<void> shareAndJoin({bool joinC = false}) async {
    await a.connect();
    await a.engine.shareThisPhone();
    await b.connect();
    await b.engine.join();
    if (joinC) {
      await c.connect();
      await c.engine.join();
    }
  }

  group('starting to share', () {
    test('a phone that is not connected simply works on its own: nothing goes in the log', () async {
      final shop = await shopOnA();
      expect(a.engine.enabled, isFalse);
      expect(a.engine.state, SyncState.off);
      expect(server.log, isEmpty);
      expect((await a.products.byId(shop.nails.id!))!.stock, 10);
    });

    test('connecting checks the address and key first', () async {
      await expectLater(a.engine.connect(url: '', key: _key), throwsSync(SyncProblem.badSettings));
      await expectLater(a.engine.connect(url: 'ftp://x', key: _key), throwsSync(SyncProblem.badSettings));
      await expectLater(a.engine.connect(url: _url, key: '  '), throwsSync(SyncProblem.badSettings));
      a.link.rejected = true;
      await expectLater(a.engine.connect(url: _url, key: 'wrong'), throwsSync(SyncProblem.unauthorized));
      a.link.rejected = false;
      a.link.offline = true;
      await expectLater(a.engine.connect(url: _url, key: _key), throwsSync(SyncProblem.offline));
      expect(a.engine.enabled, isFalse, reason: 'nothing is remembered from a failed attempt');
    });

    test('the address and key are remembered, and a restart is still connected', () async {
      await a.engine.connect(url: '$_url/', key: ' $_key ');
      expect(a.settings.values['sync.url'], _url, reason: 'tidied');
      expect(a.settings.values['sync.key'], _key);
      await a.engine.load();
      expect(a.engine.enabled, isTrue);
    });

    test('the owner\'s phone uploads its data; a new phone joins and gets exactly the same shop', () async {
      await shopOnA();
      await shareAndJoin();
      expect(await b.dump(), await a.dump());
      expect(b.engine.appliedSeq, server.head);
      expect(a.engine.appliedSeq, server.head);
      expect(a.engine.state, SyncState.idle);
    });

    test('a shop that already has sales, dues and payments arrives complete (not just products)', () async {
      final shop = await shopOnA();
      final bill = await a.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 3, unitPrice: 100), SaleLine(productId: shop.wire.id!, quantity: 1, unitPrice: 70)],
        customer: _rahim,
        paid: 100,
      );
      final customerId = (await a.customers.all()).single.id;
      await a.customers.collectPayment(customerId, 120);
      await shareAndJoin();

      expect(b.engine.skipped, isEmpty);
      expect(await b.dump(), await a.dump());
      final onB = (await b.sales.billById(bill.id!))!;
      expect(onB.lines, hasLength(2));
      expect(onB.total, 370);
      final customer = (await b.customers.byId(customerId))!;
      expect((customer.totalSpent, customer.totalPaid, customer.due), (370, 220, 150));
      expect((await b.customers.paymentsOf(customerId)).single.amount, 120);
      expect((await b.stock.history(shop.nails.id!)).map((e) => e.reason), contains(StockReason.sale));
    });

    test('a phone upgraded from an old version (its products still have a retired column) shares fine', () async {
      final shop = await shopOnA();
      await a.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 2, unitPrice: 100)],
        customer: const CustomerInfo(whatsapp: '01911111111'),
      );
      final d = await a.db.db;
      await d.execute('ALTER TABLE products ADD COLUMN location_id INTEGER');
      await d.execute('UPDATE products SET location_id = 1');
      await shareAndJoin();

      expect(b.engine.skipped, isEmpty);
      final products = await (await b.db.db).query('products', orderBy: 'id');
      expect(products.map((r) => r['name']), ['পেরেক', 'তার']);
      expect(products.first.containsKey('location_id'), isFalse, reason: 'this phone has no such column, and does not need it');
      expect(products.first['stock'], 8);
      expect(await b.sales.billsOn(DateTime(2026, 11, 22)), hasLength(1));
      expect((await b.sales.billsOn(DateTime(2026, 11, 22))).single.total, 200);
    });

    test('a piece of the shop that cannot be read is NEVER skipped quietly: it stops, says so, and waits', () async {
      server.add('begin-1-padding', 'x', 1, OpEnvelope(name: 'import.begin', args: const {}, at: 1).encode());
      server.add(
        'rows-1-padding',
        'x',
        2,
        OpEnvelope(name: 'import.rows', args: {
          'table': 'products',
          'rows': [
            {'id': 1, 'name': null, 'unit': 'পিস', 'kind': 'standard', 'purchase_price': 1, 'selling_price': 2, 'stock': 1, 'updated_at': 0}
          ],
        }, at: 2)
            .encode(),
      );
      server.add('end-1-padding', 'x', 3, OpEnvelope(name: 'import.end', args: const {'sequences': []}, at: 3).encode());
      await b.connect();
      await expectLater(b.engine.join(), throwsSync(SyncProblem.failed));
      expect(b.engine.state, SyncState.failed);
      expect(b.engine.appliedSeq, 1, reason: 'it did not move past the piece it could not read');
      expect(b.engine.skipped, isEmpty);
      expect(await (await b.db.db).query('products'), isEmpty);
    });

    test('a refused change IS recorded as skipped on every phone, so it can be looked at', () async {
      final shop = await shopOnA(nailsStock: 1);
      await shareAndJoin();
      final line = [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)];
      const customer = CustomerInfo(whatsapp: '01911111111');
      await Future.wait([
        a.sales.checkout(line, customer: customer).then<Object>((x) => x, onError: (Object e) => e),
        b.sales.checkout(line, customer: customer).then<Object>((x) => x, onError: (Object e) => e),
      ]);
      await a.engine.syncNow();
      await b.engine.syncNow();
      for (final phone in [a, b]) {
        expect(phone.engine.skipped.map((s) => s.operation), ['sale.checkout'], reason: phone.name);
        expect(phone.engine.skipped.single.error, isA<StockException>());
      }
    });

    test('ids carry on identically even after deletes (the next id is the same on every phone)', () async {
      final shop = await shopOnA();
      final doomed = await a.products.save(const Product(
          name: 'বাদ', purchasePrice: 1, sellingPrice: 2, stock: 1, unit: 'পিস'));
      await a.products.delete(doomed.id!); // the highest id is gone, but must not be reused
      await shareAndJoin();

      final onB = await b.products.save(const Product(name: 'নতুন', purchasePrice: 1, sellingPrice: 2, stock: 1, unit: 'পিস'));
      await a.engine.syncNow();
      final onA = (await a.products.search(query: 'নতুন')).single;
      expect(onB.id, doomed.id! + 1, reason: 'not the deleted id again');
      expect(onA.id, onB.id);
      expect(await a.dump(), await b.dump());
      expect(shop.nails.id, isNotNull);
    });

    test('a big shop is uploaded in pieces that each fit, and arrives whole', timeout: const Timeout(Duration(minutes: 3)), () async {
      await a.users.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      final long = 'ক' * 600;
      for (var i = 0; i < 700; i++) {
        await a.products.save(Product(name: '$long $i', purchasePrice: 1, sellingPrice: 2, stock: 1, unit: 'পিস'));
      }
      await a.connect();
      await a.engine.shareThisPhone();
      expect(server.log.length, greaterThan(4), reason: 'begin + several chunks + end');
      expect(server.log.every((o) => o.payload.length < 900000), isTrue);
      await b.connect();
      await b.engine.join();
      expect(await b.dump(), await a.dump());
    });

    test('only an empty log can be shared into; only a fresh phone can join; an empty log has nothing to join', () async {
      await b.connect();
      await expectLater(b.engine.join(), throwsSync(SyncProblem.nothingToJoin));

      await shopOnA();
      await a.connect();
      await a.engine.shareThisPhone();
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.alreadyShared));

      await c.users.create(name: 'অন্য দোকান', pin: '2222', role: UserRole.owner);
      await c.connect();
      await expectLater(c.engine.join(), throwsSync(SyncProblem.notFresh), reason: 'it has a shop of its own');
      expect((await c.users.all()).single.name, 'অন্য দোকান', reason: 'and it was not touched');
    });

    test('an upload cut off half-way can simply be started again, and the shop still arrives whole', () async {
      await shopOnA();
      await a.connect();
      a.link.failAppendsAfter = 3;
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.offline));
      expect(server.head, 3, reason: 'only part of it got there');

      a.link.failAppendsAfter = -1;
      await a.engine.shareThisPhone(); // allowed: the log holds only this phone's unfinished upload
      await b.connect();
      await b.engine.join();
      expect(await b.dump(), await a.dump());
      expect(b.engine.state, SyncState.idle);
    });

    test('a phone that joined during a cut-off upload ends up right once the full upload lands', () async {
      await shopOnA();
      await a.connect();
      a.link.failAppendsAfter = 4;
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.offline));
      await b.connect();
      await b.engine.join(); // sees half a shop
      a.link.failAppendsAfter = -1;
      await a.engine.shareThisPhone();
      await b.engine.syncNow();
      expect(await b.dump(), await a.dump());
    });

    test('an unfinished upload is not restarted if anyone else has added to the log, nor after it finished', () async {
      await shopOnA();
      await a.connect();
      a.link.failAppendsAfter = 2;
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.offline));
      server.add('other-1-padding', 'someone-else', 5, OpEnvelope(name: 'stock.restock', args: const {}, at: 5).encode());
      a.link.failAppendsAfter = -1;
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.alreadyShared));
    });

    test('disconnecting forgets the address and key and leaves the data alone', () async {
      final shop = await shopOnA();
      await a.connect();
      await a.engine.disconnect();
      expect(a.engine.enabled, isFalse);
      expect(a.engine.state, SyncState.off);
      await a.engine.load();
      expect(a.engine.enabled, isFalse, reason: 'and it stays forgotten');
      expect((await a.products.byId(shop.nails.id!))!.stock, 10);
      await a.stock.restock(shop.nails.id!, 1);
      expect(server.log, isEmpty, reason: 'it works alone again');
    });

    test('sharing without being connected, or with no signal, is refused cleanly', () async {
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.notConnected));
      await expectLater(a.engine.join(), throwsSync(SyncProblem.notConnected));
      await a.connect();
      a.link.offline = true;
      await expectLater(a.engine.shareThisPhone(), throwsSync(SyncProblem.offline));
      expect(a.engine.state, SyncState.offline);
    });
  });

  group('working together', () {
    test('a change on one phone appears on the others, with who made it and when', () async {
      final shop = await shopOnA();
      await shareAndJoin(joinC: true);
      final staff = await b.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      b.session.signIn(staff);

      await b.stock.restock(shop.nails.id!, 5, locationId: shop.shelf.id, purchasePrice: 90);
      await a.engine.syncNow();
      await c.engine.syncNow();

      for (final phone in [a, b, c]) {
        final nails = (await phone.products.byId(shop.nails.id!))!;
        expect(nails.stock, 15, reason: phone.name);
        expect(nails.purchasePrice, 90, reason: phone.name);
      }
      final history = await a.stock.history(shop.nails.id!);
      expect(history.first.reason, StockReason.restock);
      expect(history.first.userName, 'করিম', reason: 'the person on the other phone, not the one reading it');
      expect(history.first.at, DateTime(2026, 11, 22, 11), reason: 'the other phone\'s time');
      expect(await a.dump(), await b.dump());
      expect(await a.dump(), await c.dump());
    });

    test('a sale on one phone: same bill, same stock, same seller and time everywhere', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final staff = await b.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      b.session.signIn(staff);

      final bill = await b.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 3, unitPrice: 100)],
        customer: const CustomerInfo(whatsapp: '01911111111'),
      );
      expect(bill.soldBy, 'করিম');
      expect(bill.at, DateTime(2026, 11, 22, 11));
      expect(bill.id, isNotNull);

      await a.engine.syncNow();
      final onA = (await a.sales.billsOn(DateTime(2026, 11, 22))).single;
      expect(onA.total, 300);
      expect(onA.soldBy, 'করিম');
      expect((await a.products.byId(shop.nails.id!))!.stock, 7);
      expect(await a.dump(), await b.dump());
    });

    test('two phones sell the LAST item at the same moment: one sale goes through, the other is refused', () async {
      final shop = await shopOnA(nailsStock: 1);
      await shareAndJoin();
      final line = [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)];
      const customer = CustomerInfo(whatsapp: '01911111111');

      final results = await Future.wait([
        a.sales.checkout(line, customer: customer).then<Object>((bill) => bill, onError: (Object e) => e),
        b.sales.checkout(line, customer: customer).then<Object>((bill) => bill, onError: (Object e) => e),
      ]);

      final sold = results.whereType<Bill>().toList();
      final refused = results.whereType<StockException>().toList();
      expect(sold, hasLength(1), reason: 'exactly one sale');
      expect(refused, hasLength(1), reason: 'the other is told there is not enough stock');
      expect(refused.single.problem, StockProblem.insufficientStock);

      await a.engine.syncNow();
      await b.engine.syncNow();
      for (final phone in [a, b]) {
        expect((await phone.products.byId(shop.nails.id!))!.stock, 0, reason: '${phone.name}: never below zero');
        expect(await phone.sales.billsOn(DateTime(2026, 11, 22)), hasLength(1), reason: phone.name);
      }
      expect(await a.dump(), await b.dump());
      expect(a.engine.appliedSeq, b.engine.appliedSeq, reason: 'the refused entry was skipped by both');
    });

    test('a refused change leaves no trace anywhere', () async {
      final shop = await shopOnA(nailsStock: 2);
      await shareAndJoin();
      final before = await b.dump();
      await expectLater(
        b.sales.checkout(
          [SaleLine(productId: shop.nails.id!, quantity: 5, unitPrice: 100)],
          customer: const CustomerInfo(whatsapp: '01911111111'),
        ),
        throwsStock(StockProblem.insufficientStock),
      );
      await a.engine.syncNow();
      expect(await b.dump(), before);
      expect(await a.dump(), before);
      expect(a.engine.appliedSeq, b.engine.appliedSeq);
    });

    test('rules that apply when not shared apply the same shared (e.g. due needs full details)', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      await expectLater(
        a.sales.checkout(
          [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)],
          customer: const CustomerInfo(whatsapp: '01911111111'),
          paid: 0,
        ),
        throwsA(isA<SaleException>().having((e) => e.problem, 'problem', SaleProblem.customerRequiredForDue)),
      );
    });

    test('taking money for a due from another phone, and cancelling a bill, replay everywhere', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final bill = await a.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 4, unitPrice: 100)],
        customer: _rahim,
        paid: 100,
      );
      await b.engine.syncNow();
      final customerId = (await b.customers.all()).single.id;
      final payment = await b.customers.collectPayment(customerId, 150);
      expect(payment.amount, 150);

      await a.engine.syncNow();
      expect((await a.customers.byId(customerId))!.due, 150);
      expect(await a.dump(), await b.dump());

      await b.sales.voidBill(bill.id!);
      await a.engine.syncNow();
      expect((await a.products.byId(shop.nails.id!))!.stock, 10);
      expect((await a.customers.byId(customerId))!.due, 0, reason: 'the cancelled bill no longer counts');
      expect(await a.dump(), await b.dump());
    });

    test('locations get one QR code on every phone, and deleting one is a shared rule too', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final made = await b.locations.add('স্টোর', LocationType.storeroom);
      await a.engine.syncNow();
      expect((await a.locations.findByCode(made.code))!.name, 'স্টোর');
      expect(made.code, startsWith('b-'), reason: 'chosen on the phone that made it');

      await expectLater(a.locations.delete(shop.shelf.id!), throwsA(isA<LocationNotEmptyException>()));
      await a.locations.delete(made.id!);
      await b.engine.syncNow();
      expect(await b.locations.findByCode(made.code), isNull);
    });

    test('moving, counting and placing stock replay the same way', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final other = await a.locations.add('তাক খ', LocationType.shelf);
      await b.engine.syncNow();
      await b.stock.move(shop.nails.id!, shop.shelf.id!, other.id!, 2);
      await b.stock.recount(shop.nails.id!, other.id!, 3);
      await b.stock.place(shop.nails.id!, shop.shelf.id!, 1);
      await b.products.adjustStock(shop.wire.id!, 8);
      await a.engine.syncNow();
      expect(await a.dump(), await b.dump());
      expect((await a.stock.placements(shop.nails.id!)).map((x) => x.quantity).fold(0.0, (s, q) => s + q), 4);
    });

    test('categories replay too', () async {
      await shopOnA();
      await shareAndJoin();
      final made = await b.categories.add('রং');
      await a.engine.syncNow();
      expect((await a.categories.all()).map((x) => x.name), contains('রং'));
      await a.categories.delete(made.id!);
      await b.engine.syncNow();
      expect((await b.categories.all()).map((x) => x.name), isNot(contains('রং')));
    });
  });

  group('PINs and people', () {
    test('a new person can sign in on another phone, and their PIN is never in the log', () async {
      await shopOnA();
      await shareAndJoin();
      await a.users.create(name: 'রহিম', pin: '4321', role: UserRole.staff);
      await b.engine.syncNow();

      final rahim = (await b.users.all()).firstWhere((u) => u.name == 'রহিম');
      expect((await b.users.signIn(rahim.id, '4321')).name, 'রহিম');
      await expectLater(b.users.signIn(rahim.id, '9999'), throwsA(isA<AuthException>()));
      expect(server.log.where((o) => o.payload.contains('4321')), isEmpty, reason: 'only a salt and hash are written');
    });

    test('changing your own PIN: needs the current one, the new one works on every phone, nothing readable is written', () async {
      await shopOnA();
      await shareAndJoin();
      final owner = (await b.users.all()).single;
      final before = server.head;
      await expectLater(
        b.users.changePin(owner.id, currentPin: '0000', newPin: '5678'),
        throwsA(isA<AuthException>().having((e) => e.problem, 'problem', AuthProblem.wrongPin)),
      );
      expect(server.head, before, reason: 'a wrong current PIN writes nothing');

      await b.users.changePin(owner.id, currentPin: '1111', newPin: '5678');
      await a.engine.syncNow();
      expect((await a.users.signIn(owner.id, '5678')).id, owner.id);
      await expectLater(a.users.signIn(owner.id, '1111'), throwsA(isA<AuthException>()));
      expect(server.log.where((o) => o.payload.contains('5678')), isEmpty);
    });

    test('profile edits and switching someone off replay everywhere', () async {
      await shopOnA();
      await shareAndJoin();
      final staff = await a.users.create(name: 'রহিম', pin: '4321', role: UserRole.staff);
      await b.engine.syncNow();
      await b.users.updateProfile(staff.id, name: 'রহিম মিয়া', mobile: '01712345678', address: 'কাজিপুর');
      await a.users.setActive(staff.id, false);
      await b.engine.syncNow();
      final seen = (await b.users.all()).firstWhere((u) => u.id == staff.id);
      expect((seen.name, seen.mobile, seen.address, seen.active), ('রহিম মিয়া', '01712345678', 'কাজিপুর', false));
      expect(await a.dump(), await b.dump());
    });

    test('the same name made on two phones at once: one wins, the other is told', () async {
      await shopOnA();
      await shareAndJoin();
      final results = await Future.wait([
        a.users.create(name: 'সালমা', pin: '1234', role: UserRole.staff).then<Object>((u) => u, onError: (Object e) => e),
        b.users.create(name: 'সালমা', pin: '5678', role: UserRole.staff).then<Object>((u) => u, onError: (Object e) => e),
      ]);
      expect(results.whereType<AppUser>(), hasLength(1));
      expect(results.whereType<AuthException>().single.problem, AuthProblem.nameTaken);
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(await a.dump(), await b.dump());
    });
  });

  group('bad connections', () {
    test('with no signal a change is refused, nothing is recorded, and reading still works', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final before = await b.dump();
      final head = server.head;
      b.link.offline = true;

      await expectLater(
        b.sales.checkout(
          [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)],
          customer: const CustomerInfo(whatsapp: '01911111111'),
        ),
        throwsSync(SyncProblem.offline),
      );
      expect(server.head, head);
      expect(await b.dump(), before, reason: 'not applied here either');
      expect(b.engine.state, SyncState.offline);
      expect((await b.products.search()).length, 2, reason: 'browsing works offline');

      b.link.offline = false;
      await b.stock.restock(shop.nails.id!, 1);
      expect(b.engine.state, SyncState.idle);
    });

    test('a lost answer is retried with the same id: exactly one entry, one sale', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.link.loseAnswers = 1;
      final head = server.head;

      final bill = await b.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)],
        customer: const CustomerInfo(whatsapp: '01911111111'),
      );
      expect(bill.total, 100);
      expect(server.head, head + 1, reason: 'the retry did not add a second copy');
      expect(b.link.appends, 2);
      await a.engine.syncNow();
      expect(await a.sales.billsOn(DateTime(2026, 11, 22)), hasLength(1));
      expect((await a.products.byId(shop.nails.id!))!.stock, 9);
    });

    test('if it never gets through, it gives up as offline after a few tries and records nothing', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.link.loseAnswers = 99; // the server hears it, but we never hear back
      await expectLater(b.stock.restock(shop.nails.id!, 1), throwsSync(SyncProblem.offline));
      expect(b.link.appends, 3);
      expect(server.log.where((o) => o.payload.contains('stock.restock')), hasLength(1), reason: 'recorded once, though sent three times');
      // The entry IS in the log, so it shows up when we are back.
      b.link.loseAnswers = 0;
      await b.engine.syncNow();
      expect((await b.products.byId(shop.nails.id!))!.stock, 11);
    });

    test('recorded but cannot read it back: "delayed", not lost, never repeated', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.link.failReads = true;
      await expectLater(
        b.stock.restock(shop.nails.id!, 5),
        throwsSync(SyncProblem.delayed),
      );
      expect((await b.products.byId(shop.nails.id!))!.stock, 10, reason: 'not here yet');
      b.link.failReads = false;
      await b.engine.syncNow();
      expect((await b.products.byId(shop.nails.id!))!.stock, 15, reason: 'arrives once');
      await b.engine.syncNow();
      expect((await b.products.byId(shop.nails.id!))!.stock, 15, reason: 'and not again');
      expect(server.log.where((o) => o.payload.contains('stock.restock')), hasLength(1));
    });

    test('a refused key is reported as such and changes nothing', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.link.rejected = true;
      await expectLater(b.stock.restock(shop.nails.id!, 1), throwsSync(SyncProblem.unauthorized));
      expect(b.engine.state, SyncState.rejected);
      await b.engine.syncNow(); // never throws
      expect(b.engine.state, SyncState.rejected);
    });

    test('syncing never throws, and recovers by itself when the connection returns', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      await a.stock.restock(shop.nails.id!, 2);
      b.link.offline = true;
      await b.engine.syncNow();
      expect(b.engine.state, SyncState.offline);
      b.link.offline = false;
      await b.engine.syncNow();
      expect(b.engine.state, SyncState.idle);
      expect(b.engine.lastSynced, isNotNull);
      expect((await b.products.byId(shop.nails.id!))!.stock, 12);
    });

    test('the screens hear about every state change', () async {
      await shopOnA();
      await shareAndJoin();
      var heard = 0;
      final sub = b.engine.changes.listen((_) => heard++);
      b.link.offline = true;
      await b.engine.syncNow();
      final whileOffline = heard;
      expect(b.engine.state, SyncState.offline);
      b.link.offline = false;
      await b.engine.syncNow();
      await Future<void>.delayed(Duration.zero); // let the last notice arrive
      await sub.cancel();
      expect(whileOffline, greaterThan(0));
      expect(heard, greaterThan(whileOffline));
      expect(b.engine.state, SyncState.idle);
    });
  });

  group('newer versions and odd entries', () {
    test('an entry this version does not know stops syncing with "update the app", and later entries wait', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      server.add('future-1-padding', 'z', 1, jsonEncode({'v': 1, 'op': 'time.travel', 'args': {}, 'at': 1}));
      // ...and, from a newer phone, a perfectly good entry after it.
      server.add(
        'later-1-padding',
        'z',
        2,
        OpEnvelope(name: 'stock.restock', args: {'productId': shop.nails.id, 'quantity': 1.0}, at: 2).encode(),
      );
      await b.engine.syncNow();
      expect(b.engine.state, SyncState.needsUpdate);
      expect((await b.products.byId(shop.nails.id!))!.stock, 10, reason: 'it did not skip ahead');
      expect(b.engine.appliedSeq, lessThan(server.head));
    });

    test('an entry written by a newer version of the format is refused the same way', () async {
      await shopOnA();
      await shareAndJoin();
      server.add('future-2-padding', 'z', 1, jsonEncode({'v': 99, 'op': 'sale.void', 'args': {'billId': 1}, 'at': 1}));
      await b.engine.syncNow();
      expect(b.engine.state, SyncState.needsUpdate);
    });

    test('an unreadable entry is treated as unsupported, not a crash', () async {
      await shopOnA();
      await shareAndJoin();
      server.add('garbage-1-padding', 'z', 1, 'not json at all');
      await b.engine.syncNow();
      expect(b.engine.state, SyncState.needsUpdate);
    });

    test('catching up many entries takes several pages and lands exactly on the newest', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      for (var i = 0; i < 130; i++) {
        await a.stock.restock(shop.nails.id!, 1);
      }
      await b.engine.syncNow();
      expect((await b.products.byId(shop.nails.id!))!.stock, 140);
      expect(b.engine.appliedSeq, server.head);
    });

    test('a replayed entry is never applied twice, even if asked to sync repeatedly', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      await a.stock.restock(shop.nails.id!, 5);
      for (var i = 0; i < 3; i++) {
        await b.engine.syncNow();
      }
      expect((await b.products.byId(shop.nails.id!))!.stock, 15);
    });

    test('where a phone has read up to survives a restart (no entry is replayed again)', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      await a.stock.restock(shop.nails.id!, 5);
      await b.engine.syncNow();
      final applied = b.engine.appliedSeq;
      await b.engine.load();
      expect(b.engine.appliedSeq, applied);
      await b.engine.syncNow();
      expect((await b.products.byId(shop.nails.id!))!.stock, 15);
    });
  });

  group('erasing all data', () {
    Future<int> rows(_Phone phone, String table) async =>
        ((await (await phone.db.db).rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n'] as int);

    Future<void> expectEmpty(_Phone phone) async {
      for (final table in ['users', 'products', 'locations', 'bills', 'sales', 'customers', 'stock_log', 'activity_log', 'shop_settings']) {
        expect(await rows(phone, table), 0, reason: '${phone.name}: $table');
      }
      expect((await phone.categories.all()).map((c) => c.name), containsAll(starterCategories), reason: 'starting categories are back');
      expect(await (await phone.db.db).rawQuery('SELECT * FROM sqlite_sequence WHERE name = ?', ['products']), isEmpty, reason: 'numbering restarts');
    }

    test('only the owner can do it, and nothing is erased when someone else tries', () async {
      final shop = await shopOnA();
      final staff = await a.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      a.session.signIn(staff);
      await expectLater(a.engine.eraseEverything(), throwsSync(SyncProblem.notOwner));
      a.session.signOut();
      await expectLater(a.engine.eraseEverything(), throwsSync(SyncProblem.notOwner), reason: 'nobody signed in');
      expect((await a.products.byId(shop.nails.id!))!.name, 'পেরেক');
    });

    test('on its own: this phone is emptied like a new install, and the app is told', () async {
      await shopOnA();
      var told = 0;
      final listening = a.engine.erased.listen((_) => told++);
      await a.engine.eraseEverything();
      await Future<void>.delayed(Duration.zero);
      await listening.cancel();
      expect(told, 1);
      await expectEmpty(a);
      expect(a.link.erases, 0, reason: 'nothing to tell a server that is not used');
    });

    test('shared: with no signal nothing is erased anywhere', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      a.link.offline = true;
      await expectLater(a.engine.eraseEverything(), throwsSync(SyncProblem.offline));
      expect((await a.products.byId(shop.nails.id!))!.name, 'পেরেক');
      expect(a.engine.enabled, isTrue);
      expect(server.log, isNotEmpty);
    });

    test('shared: the live database is erased, this phone disconnects, other phones follow when they next read', () async {
      await shopOnA();
      await shareAndJoin(joinC: true);
      final before = server.head;
      await a.engine.eraseEverything();

      expect(server.log, hasLength(1), reason: 'only the notice is left');
      expect(server.log.single.seq, greaterThan(before), reason: 'numbers keep rising');
      expect(OpEnvelope.decode(server.log.single.payload).name, 'shop.erase');
      expect(a.engine.enabled, isFalse);
      expect(a.settings.values['sync.key'], '');
      await expectEmpty(a);

      var told = 0;
      final listening = b.engine.erased.listen((_) => told++);
      await b.engine.syncNow();
      await c.engine.syncNow();
      await Future<void>.delayed(Duration.zero);
      await listening.cancel();
      for (final phone in [b, c]) {
        await expectEmpty(phone);
        expect(phone.engine.enabled, isFalse, reason: '${phone.name} works on its own again');
        expect(phone.engine.state, SyncState.off);
        expect(phone.engine.appliedSeq, 0);
      }
      expect(told, 1);
    });

    test('a shop can be set up and shared again afterwards; a phone that missed the erase is emptied, not mixed in', () async {
      await shopOnA();
      await shareAndJoin(joinC: true);
      await a.engine.eraseEverything();
      await b.engine.syncNow(); // b saw it; c was away

      // A starts over.
      final owner = await a.users.create(name: 'নতুন মালিক', pin: '3333', role: UserRole.owner);
      a.session.signIn(owner);
      final cat = await a.categories.add('নতুন');
      await a.products.save(Product(name: 'রড', kind: ProductKind.standard, categoryId: cat.id, purchasePrice: 1, sellingPrice: 2, stock: 3, unit: 'পিস'));
      await a.connect();
      await a.engine.shareThisPhone();

      await b.connect();
      await b.engine.join();
      expect(await a.dump(), await b.dump());
      expect(b.engine.enabled, isTrue, reason: 'the old notice does not disconnect a phone that is joining now');

      await c.engine.syncNow(); // c still thinks it is in the old shop
      expect((await (await c.db.db).query('products')), isEmpty, reason: 'the old shop is gone from c');
      expect(c.engine.enabled, isFalse);
      await c.connect();
      await c.engine.join();
      expect(await a.dump(), await c.dump());
    });

    test('a log with only the erase notice has no shop to join', () async {
      await shopOnA();
      await shareAndJoin();
      await a.engine.eraseEverything();
      final fresh = await _Phone.start('d', server);
      addTearDown(fresh.close);
      await fresh.connect();
      await expectLater(fresh.engine.join(), throwsSync(SyncProblem.nothingToJoin));
    });
  });

  group('location types', () {
    Matcher throwsLocation(LocationProblem problem) =>
        throwsA(isA<LocationException>().having((e) => e.problem, 'problem', problem));

    Future<void> twoCabinets() async {
      await a.locations.add('আলমারি ১', LocationType.custom('আলমারি'));
      await a.locations.add('আলমারি ২', LocationType.custom('আলমারি'));
      await a.locations.add('তাক ১', LocationType.shelf);
    }

    test('renaming a type changes it on every location that has it, and nothing else', () async {
      await shopOnA();
      await twoCabinets();
      final changed = await a.locations.renameType(LocationType.custom('আলমারি'), '  র‍্যাক ');
      expect(changed, 2);
      final all = await a.locations.all();
      expect(all.where((l) => l.type == LocationType.custom('র‍্যাক')).map((l) => l.name), unorderedEquals(['আলমারি ১', 'আলমারি ২']));
      expect(all.where((l) => l.type == LocationType.custom('আলমারি')), isEmpty);
      expect(all.firstWhere((l) => l.name == 'তাক ১').type, LocationType.shelf);
    });

    test('deleting a type makes its locations shelves, with their codes and stock untouched', () async {
      final shop = await shopOnA();
      final cabinet = await a.locations.add('আলমারি ১', LocationType.custom('আলমারি'));
      await a.stock.place(shop.wire.id!, cabinet.id!, 2);
      final changed = await a.locations.deleteType(LocationType.custom('আলমারি'));
      expect(changed, 1);
      final after = (await a.locations.all()).firstWhere((l) => l.id == cabinet.id);
      expect((after.type, after.code), (LocationType.shelf, cabinet.code));
      expect((await a.locations.stockedProductCounts())[cabinet.id], 1);
    });

    test('the built-in types and an empty name are refused, before anything is sent', () async {
      await shopOnA();
      await twoCabinets();
      await shareAndJoin();
      final head = server.head;
      await expectLater(a.locations.renameType(LocationType.yard, 'নতুন'), throwsLocation(LocationProblem.builtInType));
      await expectLater(a.locations.deleteType(LocationType.shelf), throwsLocation(LocationProblem.builtInType));
      await expectLater(a.locations.renameType(LocationType.custom('আলমারি'), '  '), throwsLocation(LocationProblem.emptyName));
      expect(server.head, head);
    });

    test('shared: other phones follow a rename and a delete, and both are on record', () async {
      await shopOnA();
      await twoCabinets();
      await shareAndJoin();
      await a.locations.renameType(LocationType.custom('আলমারি'), 'র‍্যাক');
      await b.engine.syncNow();
      expect((await b.locations.all()).where((l) => l.type == LocationType.custom('র‍্যাক')), hasLength(2));
      await b.locations.deleteType(LocationType.custom('র‍্যাক'));
      await a.engine.syncNow();
      expect((await a.locations.all()).every((l) => l.type.isBuiltIn), isTrue);
      expect(await a.dump(), await b.dump());
      final kinds = (await a.activity.recent(limit: 50)).map((e) => e.kind);
      expect(kinds, containsAll([ActivityKind.locationTypeRenamed, ActivityKind.locationTypeDeleted]));
    });
  });

  group('category rename', () {
    Matcher throwsCategory(CategoryProblem problem) =>
        throwsA(isA<CategoryException>().having((e) => e.problem, 'problem', problem));

    test('a category that has products can be renamed', () async {
      await shopOnA();
      final category = await a.categories.add('পেরেক');
      final renamed = await a.categories.update(category.id!, '  পেরেক ও স্ক্রু ');
      expect((renamed.id, renamed.name), (category.id, 'পেরেক ও স্ক্রু'));
      expect((await a.categories.all()).map((c) => c.name), contains('পেরেক ও স্ক্রু'));
    });

    test('empty, unknown and already-used names are refused', () async {
      await shopOnA();
      final one = await a.categories.add('এক');
      final two = await a.categories.add('দুই');
      await expectLater(a.categories.update(one.id!, '  '), throwsCategory(CategoryProblem.emptyName));
      await expectLater(a.categories.update(999, 'কিছু'), throwsCategory(CategoryProblem.unknownCategory));
      await expectLater(a.categories.update(one.id!, 'দুই'), throwsCategory(CategoryProblem.nameTaken));
      expect((await a.categories.update(two.id!, 'দুই')).name, 'দুই', reason: 'its own name is not a clash');
    });

    test('the new name reaches the other phones, and it is on record', () async {
      await shopOnA();
      final category = await a.categories.add('রং');
      await shareAndJoin();
      await b.categories.update(category.id!, 'রঙ ও বার্নিশ');
      await a.engine.syncNow();
      expect((await a.categories.all()).firstWhere((c) => c.id == category.id).name, 'রঙ ও বার্নিশ');
      expect(await a.dump(), await b.dump());
      final entry = (await a.activity.recent(limit: 50)).firstWhere((e) => e.kind == ActivityKind.categoryEdited);
      expect((entry.detail['previous'], entry.detail['name']), ('রং', 'রঙ ও বার্নিশ'));
    });

    test('with an empty name nothing is sent; with no signal nothing changes', () async {
      await shopOnA();
      final category = await a.categories.add('রং');
      await shareAndJoin();
      final head = server.head;
      await expectLater(b.categories.update(category.id!, ' '), throwsCategory(CategoryProblem.emptyName));
      expect(server.head, head);
      b.link.offline = true;
      await expectLater(b.categories.update(category.id!, 'নতুন'), throwsSync(SyncProblem.offline));
      expect((await b.categories.all()).firstWhere((c) => c.id == category.id).name, 'রং');
    });
  });

  group('shelf rename', () {
    Matcher throwsLocation(LocationProblem problem) =>
        throwsA(isA<LocationException>().having((e) => e.problem, 'problem', problem));

    test('a shelf that holds stock can be renamed: the stock stays and the QR code does not change', () async {
      final shop = await shopOnA();
      final before = (await a.locations.all()).firstWhere((l) => l.id == shop.shelf.id);
      final renamed = await a.locations.update(shop.shelf.id!, name: ' তাক নতুন ', type: LocationType.storeroom);
      expect((renamed.name, renamed.type, renamed.code), ('তাক নতুন', LocationType.storeroom, before.code));
      expect((await a.stock.placements(shop.nails.id!)).single.locationId, shop.shelf.id, reason: 'the stock is still there');
      expect((await a.locations.findByCode(before.code))!.name, 'তাক নতুন', reason: 'the printed label still finds it');
      expect((await a.locations.stockedProductCounts())[shop.shelf.id], 1);
    });

    test('an empty name or a shelf that does not exist is refused, before anything is sent', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final head = server.head;
      await expectLater(a.locations.update(shop.shelf.id!, name: '  ', type: LocationType.shelf), throwsLocation(LocationProblem.emptyName));
      expect(server.head, head, reason: 'nothing reached the shared log');
      await expectLater(a.locations.update(999, name: 'কোথাও নেই', type: LocationType.shelf), throwsLocation(LocationProblem.unknownLocation));
      expect((await a.locations.all()).firstWhere((l) => l.id == shop.shelf.id).name, 'তাক ক');
    });

    test('the new name reaches the other phones, with the same QR code, and who did it is on record', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final owner = (await b.users.all()).firstWhere((u) => u.id == shop.owner.id);
      b.session.signIn(owner);
      await b.locations.update(shop.shelf.id!, name: 'বাম দেয়ালের তাক', type: LocationType.shelf);
      await a.engine.syncNow();
      final onA = (await a.locations.all()).firstWhere((l) => l.id == shop.shelf.id);
      expect((onA.name, onA.code), ('বাম দেয়ালের তাক', shop.shelf.code));
      expect(await a.dump(), await b.dump());
      final entry = (await a.activity.recent(limit: 50)).firstWhere((e) => e.kind == ActivityKind.locationEdited);
      expect((entry.detail['previous'], entry.detail['name'], entry.userName), ('তাক ক', 'বাম দেয়ালের তাক', 'মালিক'));
    });

    test('a shelf type the shop made up is kept, shared, and offered again', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final cabinet = LocationType.custom('  আলমারি ');
      final made = await a.locations.add('আলমারি ১', cabinet);
      expect(made.type, LocationType.custom('আলমারি'));
      expect(made.type.isBuiltIn, isFalse);
      await a.engine.syncNow();
      await b.engine.syncNow();
      final onB = (await b.locations.all()).firstWhere((l) => l.name == 'আলমারি ১');
      expect(onB.type, LocationType.custom('আলমারি'));
      expect(LocationType.offered(await b.locations.all()), [...LocationType.builtIn, LocationType.custom('আলমারি')]);
      await a.locations.update(shop.shelf.id!, name: 'তাক ক', type: LocationType.custom('আলমারি'));
      expect(await a.dump(), await b.dump().then((_) async { await b.engine.syncNow(); return b.dump(); }));
    });

    test('built-in names still mean the built-in types, and nothing means shelf', () {
      expect(LocationType.parse('yard'), LocationType.yard);
      expect(LocationType.custom('yard'), LocationType.yard);
      expect(LocationType.parse(null), LocationType.shelf);
      expect(LocationType.parse('  '), LocationType.shelf);
    });

    test('with no signal it is not renamed anywhere', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.link.offline = true;
      await expectLater(b.locations.update(shop.shelf.id!, name: 'নতুন', type: LocationType.shelf), throwsSync(SyncProblem.offline));
      expect((await b.locations.all()).firstWhere((l) => l.id == shop.shelf.id).name, 'তাক ক');
    });

    test('a shelf deleted on another phone: the rename is refused cleanly', () async {
      final shop = await shopOnA();
      final empty = await a.locations.add('খালি', LocationType.yard);
      await shareAndJoin();
      await a.locations.delete(empty.id!);
      await expectLater(
        b.locations.update(empty.id!, name: 'নতুন', type: LocationType.yard),
        throwsLocation(LocationProblem.unknownLocation),
      );
      expect(shop.shelf.id, isNotNull);
    });
  });

  group('shop name', () {
    Matcher throwsShop(ShopProblem problem) => throwsA(isA<ShopException>().having((e) => e.problem, 'problem', problem));

    test('there is no name until the owner chooses one; then it is kept (and tidied)', () async {
      expect(await a.shop.name(), isNull);
      await a.shop.rename('  হাসান হার্ডওয়্যার  ');
      expect(await a.shop.name(), 'হাসান হার্ডওয়্যার');
      await a.shop.rename('নতুন নাম');
      expect(await a.shop.name(), 'নতুন নাম');
      expect(await (await a.db.db).query('shop_settings'), hasLength(1), reason: 'one name, not a pile of them');
    });

    test('an empty or too long name is refused, before anything is sent, and changes nothing', () async {
      await shopOnA();
      await shareAndJoin();
      await a.shop.rename('ভালো নাম');
      final head = server.head;
      await expectLater(a.shop.rename('   '), throwsShop(ShopProblem.emptyName));
      await expectLater(a.shop.rename('ক' * 61), throwsShop(ShopProblem.nameTooLong));
      expect(server.head, head, reason: 'nothing reached the shared log');
      expect(await a.shop.name(), 'ভালো নাম');
      await a.shop.rename('ক' * 60); // exactly the limit is fine
      expect((await a.shop.name())!.length, 60);
    });

    test('the same rules apply when the shop is not shared', () async {
      await expectLater(a.shop.rename(''), throwsShop(ShopProblem.emptyName));
      await expectLater(a.shop.rename('ক' * 61), throwsShop(ShopProblem.nameTooLong));
      expect(await a.shop.name(), isNull);
    });

    test('a rename on one phone reaches the others', () async {
      await shopOnA();
      await shareAndJoin(joinC: true);
      await b.shop.rename('হাসান হার্ডওয়্যার');
      await a.engine.syncNow();
      await c.engine.syncNow();
      for (final phone in [a, b, c]) {
        expect(await phone.shop.name(), 'হাসান হার্ডওয়্যার', reason: phone.name);
      }
      expect(await a.dump(), await b.dump());
    });

    test('a new phone gets the name when it joins', () async {
      await shopOnA();
      await a.shop.rename('হাসান হার্ডওয়্যার');
      await shareAndJoin();
      expect(await b.shop.name(), 'হাসান হার্ডওয়্যার');
      expect(await b.dump(), await a.dump());
    });

    test('with no signal the name is not changed anywhere, and the reason is clear', () async {
      await shopOnA();
      await shareAndJoin();
      await a.shop.rename('আগের নাম');
      await b.engine.syncNow();
      b.link.offline = true;
      await expectLater(b.shop.rename('নতুন নাম'), throwsSync(SyncProblem.offline));
      expect(await b.shop.name(), 'আগের নাম');
    });

    test('who renamed the shop, and from what, is in the activity log on every phone', () async {
      final shop = await shopOnA();
      await a.shop.rename('প্রথম নাম');
      await shareAndJoin();
      final owner = (await b.users.all()).firstWhere((u) => u.id == shop.owner.id);
      b.session.signIn(owner);
      await b.shop.rename('দ্বিতীয় নাম');
      await a.engine.syncNow();
      final renamed = (await a.activity.recent(limit: 100)).where((e) => e.kind == ActivityKind.shopRenamed).toList();
      expect(renamed, hasLength(2));
      expect((renamed.first.detail['name'], renamed.first.detail['previous'], renamed.first.userName), ('দ্বিতীয় নাম', 'প্রথম নাম', 'মালিক'));
      expect(renamed.last.detail['previous'], isNull);
    });
  });

  group('activity log', () {
    /// Waits for something that happens in the background (a note nobody awaits).
    Future<void> eventually(Future<bool> Function() condition) async {
      for (var i = 0; i < 150; i++) {
        if (await condition()) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('it did not happen in time');
    }

    Future<List<ActivityEntry>> all(_Phone phone, {ActivityGroup group = ActivityGroup.all}) =>
        phone.activity.recent(limit: 1000, group: group);

    test('everything people do is written down with who and when, whether or not the shop is shared', () async {
      final shop = await shopOnA();
      final extra = await a.locations.add('তাক খ', LocationType.shelf);
      final empty = await a.locations.add('খালি', LocationType.yard);
      await a.stock.restock(shop.nails.id!, 5, locationId: shop.shelf.id);
      await a.products.adjustStock(shop.wire.id!, 8);
      await a.stock.place(shop.nails.id!, shop.shelf.id!, 4);
      await a.stock.recount(shop.nails.id!, shop.shelf.id!, 6);
      await a.stock.move(shop.nails.id!, shop.shelf.id!, extra.id!, 2);
      final bill = await a.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 3, unitPrice: 100)],
        customer: _rahim,
        paid: 100,
      );
      final customerId = (await a.customers.all()).single.id;
      await a.customers.collectPayment(customerId, 50);
      await a.sales.voidBill(bill.id!);
      await a.products.save((await a.products.byId(shop.nails.id!))!.copyWith(sellingPrice: 120));
      await a.products.delete(shop.wire.id!);
      await a.locations.delete(empty.id!);
      final cat = await a.categories.add('রং');
      await a.categories.delete(cat.id!);
      final staff = await a.users.create(name: 'রহিম', pin: '4321', role: UserRole.staff);
      await a.users.setPin(staff.id, '9999');
      await a.users.updateProfile(staff.id, name: 'রহিম মিয়া', mobile: '01712345678');
      await a.users.setActive(staff.id, false);

      final entries = await all(a);
      expect(entries.map((e) => e.kind).toSet(), {
        for (final kind in [
          ActivityKind.sale,
          ActivityKind.saleVoided,
          ActivityKind.paymentCollected,
          ActivityKind.restocked,
          ActivityKind.stockAdjusted,
          ActivityKind.stockPlaced,
          ActivityKind.stockCounted,
          ActivityKind.stockMoved,
          ActivityKind.productAdded,
          ActivityKind.productEdited,
          ActivityKind.productDeleted,
          ActivityKind.categoryAdded,
          ActivityKind.categoryDeleted,
          ActivityKind.locationAdded,
          ActivityKind.locationDeleted,
          ActivityKind.userAdded,
          ActivityKind.pinChanged,
          ActivityKind.profileUpdated,
          ActivityKind.userSwitched,
        ])
          kind,
      });
      expect(entries.first.kind, ActivityKind.userSwitched, reason: 'newest first');

      final sale = entries.firstWhere((e) => e.kind == ActivityKind.sale);
      expect((sale.userName, sale.at), ('মালিক', DateTime(2026, 11, 22, 10)));
      expect((sale.detail['total'], sale.detail['items'], sale.detail['customer'], sale.detail['due']), (300, 1, 'রহিম', 200));
      final voided = entries.firstWhere((e) => e.kind == ActivityKind.saleVoided);
      expect((voided.detail['billId'], voided.detail['total'], voided.detail['customer']), (bill.id, 300, 'রহিম'));
      expect(entries.firstWhere((e) => e.kind == ActivityKind.paymentCollected).detail, {'amount': 50, 'customer': 'রহিম'});
      expect(entries.firstWhere((e) => e.kind == ActivityKind.restocked).detail, {'product': 'পেরেক', 'location': 'তাক ক', 'quantity': 5});
      expect(entries.firstWhere((e) => e.kind == ActivityKind.stockMoved).detail, {'product': 'পেরেক', 'from': 'তাক ক', 'to': 'তাক খ', 'quantity': 2});
      expect(entries.firstWhere((e) => e.kind == ActivityKind.productDeleted).detail['product'], 'তার',
          reason: 'the name is written down before it is deleted');
      expect(entries.firstWhere((e) => e.kind == ActivityKind.locationDeleted).detail['name'], 'খালি');
      expect(entries.firstWhere((e) => e.kind == ActivityKind.userSwitched).detail, {'name': 'রহিম মিয়া', 'active': false});
      expect(entries.firstWhere((e) => e.kind == ActivityKind.pinChanged).detail['name'], 'রহিম');
      expect(entries.where((e) => e.kind == ActivityKind.productAdded), hasLength(2));
    });

    test('someone who was not signed in yet (creating the owner) is recorded as nobody, not as someone else', () async {
      await a.users.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      final entry = (await all(a)).single;
      expect((entry.kind, entry.userId, entry.userName), (ActivityKind.userAdded, null, ''));
    });

    test('names are copied in, so an entry still reads right after the product is renamed', () async {
      final shop = await shopOnA();
      await a.products.save((await a.products.byId(shop.nails.id!))!.copyWith(name: 'পেরেক নতুন'));
      final added = (await all(a)).where((e) => e.kind == ActivityKind.productAdded).map((e) => e.detail['product']);
      expect(added, contains('পেরেক'));
      expect((await all(a)).first.detail['product'], 'পেরেক নতুন');
    });

    test('another phone\'s work shows up with that person and that phone\'s time', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      final staff = await b.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      b.session.signIn(staff);
      await b.stock.restock(shop.nails.id!, 5);
      await b.sales.checkout(
        [SaleLine(productId: shop.nails.id!, quantity: 2, unitPrice: 100)],
        customer: const CustomerInfo(whatsapp: '01911111111'),
      );

      await a.engine.syncNow();
      final seenOnA = await all(a);
      final restock = seenOnA.firstWhere((e) => e.kind == ActivityKind.restocked);
      expect((restock.userName, restock.at), ('করিম', DateTime(2026, 11, 22, 11)));
      expect(seenOnA.firstWhere((e) => e.kind == ActivityKind.sale).userName, 'করিম');
      expect(await a.dump(), await b.dump(), reason: 'the log itself is identical on both phones');
    });

    test('a refused action leaves no entry on any phone', () async {
      final shop = await shopOnA(nailsStock: 1);
      await shareAndJoin();
      final line = [SaleLine(productId: shop.nails.id!, quantity: 1, unitPrice: 100)];
      const customer = CustomerInfo(whatsapp: '01911111111');
      await Future.wait([
        a.sales.checkout(line, customer: customer).then<Object>((x) => x, onError: (Object e) => e),
        b.sales.checkout(line, customer: customer).then<Object>((x) => x, onError: (Object e) => e),
      ]);
      await a.engine.syncNow();
      await b.engine.syncNow();
      for (final phone in [a, b]) {
        expect((await all(phone)).where((e) => e.kind == ActivityKind.sale), hasLength(1), reason: phone.name);
      }
      expect(await a.dump(), await b.dump());

      final before = (await all(a)).length;
      await expectLater(
        b.sales.checkout([SaleLine(productId: shop.nails.id!, quantity: 9, unitPrice: 100)], customer: customer),
        throwsStock(StockProblem.insufficientStock),
      );
      expect((await all(b)).length, before);
    });

    test('a refused action leaves no entry when the shop is not shared either', () async {
      final shop = await shopOnA(nailsStock: 1);
      final before = (await all(a)).length;
      await expectLater(
        a.sales.checkout(
          [SaleLine(productId: shop.nails.id!, quantity: 5, unitPrice: 100)],
          customer: const CustomerInfo(whatsapp: '01911111111'),
        ),
        throwsStock(StockProblem.insufficientStock),
      );
      expect((await all(a)).length, before);
    });

    test('a new phone gets the whole history when it joins', () async {
      final shop = await shopOnA();
      await a.stock.restock(shop.nails.id!, 3);
      await shareAndJoin();
      final onA = await all(a);
      final onB = await all(b);
      expect(onB.map((e) => e.id), onA.map((e) => e.id));
      expect(onB.map((e) => e.userName), onA.map((e) => e.userName));
      expect(onB, isNotEmpty);
    });

    test('signing in is noted: here when alone, and on every phone when shared', () async {
      final shop = await shopOnA();
      a.session.signIn(shop.owner);
      a.notifier.signedIn(shop.owner);
      await eventually(() async => (await all(a)).any((e) => e.kind == ActivityKind.signIn));
      expect((await all(a)).firstWhere((e) => e.kind == ActivityKind.signIn).userName, 'মালিক');

      await shareAndJoin();
      final staff = await b.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      b.session.signIn(staff);
      b.notifier.signedIn(staff);
      await eventually(() async {
        await a.engine.syncNow();
        return (await all(a)).any((e) => e.kind == ActivityKind.signIn && e.userName == 'করিম');
      });
      expect((await all(a)).firstWhere((e) => e.userName == 'করিম' && e.kind == ActivityKind.signIn).at, DateTime(2026, 11, 22, 11));
    });

    test('with no connection a sign-in note is simply not made: it never fails and never holds anything up', () async {
      final shop = await shopOnA();
      await shareAndJoin();
      b.session.signIn(shop.owner);
      b.link.offline = true;
      final head = server.head;
      expect(() => b.notifier.signedIn(shop.owner), returnsNormally);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.head, head);
      expect(b.engine.state, SyncState.offline);
    });
  });

  group('log entries', () {
    test('every kind of value survives being written down and read back', () {
      const product = Product(
        id: 7,
        name: 'রঙ',
        kind: ProductKind.bulky,
        categoryId: 3,
        brand: 'ব্র্যান্ড',
        size: '১ লিটার',
        model: 'M1',
        finish: 'লাল',
        purchasePrice: 100.5,
        sellingPrice: 150,
        stock: 12.25,
        unit: 'ক্যান',
        placements: [StockPlacement(locationId: 2, quantity: 4.5)],
      );
      final back = productFromJson(jsonDecode(jsonEncode(productToJson(product))) as Map<String, dynamic>);
      expect(productToJson(back), productToJson(product));

      const line = SaleLine(productId: 1, quantity: 2.5, unitPrice: 10, fromLocationId: 4);
      expect(saleLineToJson(saleLineFromJson(jsonDecode(jsonEncode(saleLineToJson(line))) as Map<String, dynamic>)), saleLineToJson(line));
      expect(customerFromJson(null), isNull);
      expect(customerToJson(customerFromJson((jsonDecode(jsonEncode(customerToJson(_rahim))) as Map).cast<String, dynamic>())), customerToJson(_rahim));
    });

    test('an entry round-trips with who made it, and without', () {
      final withActor = OpEnvelope(name: 'x', args: const {'a': 1}, at: 5, actor: (id: 3, name: 'রহিম'));
      final back = OpEnvelope.decode(withActor.encode());
      expect((back.name, back.at, back.actor?.id, back.actor?.name), ('x', 5, 3, 'রহিম'));
      expect(back.args, {'a': 1});
      expect(OpEnvelope.decode(const OpEnvelope(name: 'y', args: {}, at: 1).encode()).actor, isNull);
      expect(() => OpEnvelope.decode('[]'), throwsFormatException);
    });
  });

  // Opt-in: runs two phones against a REAL Worker over HTTP. Use a Worker with
  // an empty log (e.g. `wrangler dev --local --persist-to <new folder>`), never the
  // shop's own: it writes test data.
  //   SYNC_E2E_URL=http://127.0.0.1:8787 SYNC_E2E_KEY=test-key flutter test test/sync_test.dart
  final e2eUrl = Platform.environment['SYNC_E2E_URL'];
  final e2eKey = Platform.environment['SYNC_E2E_KEY'] ?? '';
  group('against a real Worker', skip: e2eUrl == null ? 'set SYNC_E2E_URL and SYNC_E2E_KEY to run' : false, () {
    test('two phones share a shop over HTTP: upload, join, sell, read back, and the last item race', () async {
      final phoneA = await _Phone.start('e2ea', server, transport: (config) => HttpSyncTransport(config));
      final phoneB = await _Phone.start('e2eb', server, now: DateTime(2026, 11, 22, 11), transport: (config) => HttpSyncTransport(config));
      addTearDown(() async {
        await phoneA.close();
        await phoneB.close();
      });

      final owner = await phoneA.users.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      phoneA.session.signIn(owner);
      final nails = await phoneA.products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 1, unit: 'কেজি'));

      await phoneA.engine.connect(url: e2eUrl!, key: e2eKey);
      await phoneA.engine.shareThisPhone();
      await phoneB.engine.connect(url: e2eUrl, key: e2eKey);
      await phoneB.engine.join();
      expect(await phoneB.dump(), await phoneA.dump(), reason: 'Bangla text and numbers survive the trip');

      final staff = await phoneB.users.create(name: 'করিম', pin: '2222', role: UserRole.staff);
      phoneB.session.signIn(staff);
      final line = [SaleLine(productId: nails.id!, quantity: 1, unitPrice: 100)];
      const customer = CustomerInfo(whatsapp: '01911111111');
      final results = await Future.wait([
        phoneA.sales.checkout(line, customer: customer).then<Object>((b) => b, onError: (Object e) => e),
        phoneB.sales.checkout(line, customer: customer).then<Object>((b) => b, onError: (Object e) => e),
      ]);
      expect(results.whereType<Bill>(), hasLength(1));
      expect(results.whereType<StockException>(), hasLength(1));

      await phoneA.engine.syncNow();
      await phoneB.engine.syncNow();
      expect(await phoneA.dump(), await phoneB.dump());
      expect((await phoneA.products.byId(nails.id!))!.stock, 0);
      expect(phoneA.engine.appliedSeq, phoneB.engine.appliedSeq);
    });

    test('a wrong key is refused by the real server', () async {
      final phoneA = await _Phone.start('e2ec', server, transport: (config) => HttpSyncTransport(config));
      addTearDown(phoneA.close);
      await expectLater(phoneA.engine.connect(url: e2eUrl!, key: 'definitely-wrong'), throwsSync(SyncProblem.unauthorized));
    });
  });

  group('the HTTP link', () {
    HttpSyncTransport link(http.Client client) =>
        HttpSyncTransport(const SyncConfig(url: 'https://x.test/', key: 'k'), client: client);

    test('sends the key, and reads the newest number and the entries', () async {
      final seen = <http.Request>[];
      final t = link(MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/v1/ping') return http.Response('{"ok":true,"head":7}', 200);
        return http.Response(
          jsonEncode({
            'ops': [
              {'seq': 8, 'opId': 'o1', 'device': 'd', 'at': 5, 'payload': 'পে লোড'}
            ],
            'head': 8,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }));
      expect(await t.head(), 7);
      final page = await t.fetch(7, limit: 10);
      expect(page.head, 8);
      expect((page.ops.single.seq, page.ops.single.opId, page.ops.single.payload), (8, 'o1', 'পে লোড'));
      expect(seen.every((r) => r.headers['authorization'] == 'Bearer k'), isTrue);
      expect(seen.last.url.toString(), 'https://x.test/v1/ops?after=7&limit=10');
    });

    test('adding an entry sends everything the server needs and returns its number', () async {
      late http.Request seen;
      final t = link(MockClient((request) async {
        seen = request;
        return http.Response('{"seq":42}', 200);
      }));
      expect(await t.append(opId: 'id-1', device: 'd1', at: 9, payload: '{"x":1}'), 42);
      expect(seen.method, 'POST');
      expect(jsonDecode(seen.body), {'opId': 'id-1', 'device': 'd1', 'at': 9, 'payload': '{"x":1}'});
    });

    test('what goes wrong is named: wrong key, wrong address, server trouble, no signal, not our server', () async {
      Future<Object?> outcome(http.Client client) async {
        try {
          await link(client).head();
          return 'fine';
        } on SyncException catch (e) {
          return e.problem;
        }
      }

      expect(await outcome(MockClient((_) async => http.Response('{}', 401))), SyncProblem.unauthorized);
      expect(await outcome(MockClient((_) async => http.Response('', 404))), SyncProblem.badSettings);
      expect(await outcome(MockClient((_) async => http.Response('oops', 500))), SyncProblem.offline);
      expect(await outcome(MockClient((_) async => http.Response('oops', 503))), SyncProblem.offline);
      expect(await outcome(MockClient((_) async => throw http.ClientException('no route'))), SyncProblem.offline);
      expect(await outcome(MockClient((_) async => http.Response('<html>', 200))), SyncProblem.badSettings);
    });
  });
}
