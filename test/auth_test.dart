import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/device_services.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/data/sqlite_user_repository.dart';
import 'package:hardware_shop/domain/customer_rules.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/main.dart';
import 'package:hardware_shop/presentation/auth/auth_pages.dart';
import 'package:hardware_shop/presentation/auth/auth_viewmodel.dart';
import 'package:hardware_shop/presentation/users/users_viewmodel.dart';
import 'package:hardware_shop/presentation/profile/profile_viewmodel.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/profile/profile_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/settings/settings_page.dart';
import 'package:hardware_shop/presentation/settings/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/users/users_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Clock implements Clock {
  DateTime current;
  _Clock(this.current);
  @override
  DateTime now() => current;
}

Matcher throwsAuth(AuthProblem problem) => throwsA(isA<AuthException>().having((e) => e.problem, 'problem', problem));

/// A plain, readable hasher so tests can see what is stored.
class _ReversingHasher implements PinHasher {
  int _n = 0;
  @override
  String newSalt() => 'salt${_n++}';
  @override
  String hash(String pin, String salt) => '$salt|$pin';
}

/// The same rules as the real thing, in memory (for screens).
class _MemoryUsers implements UserRepository {
  final List<({AppUser user, String pin})> rows = [];
  int _id = 1;

  @override
  Future<bool> hasUsers() async => rows.isNotEmpty;

  @override
  Future<List<AppUser>> all() async => [for (final r in rows) r.user];

  @override
  Future<AppUser> create({required String name, required String pin, required UserRole role}) async {
    if (name.trim().isEmpty) throw const AuthException(AuthProblem.invalidName);
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    if (rows.any((r) => r.user.name.toLowerCase() == name.trim().toLowerCase())) {
      throw const AuthException(AuthProblem.nameTaken);
    }
    final user = AppUser(id: _id++, name: name.trim(), role: role);
    rows.add((user: user, pin: normalizePin(pin)));
    return user;
  }

  int _index(int id) {
    final i = rows.indexWhere((r) => r.user.id == id);
    if (i == -1) throw const AuthException(AuthProblem.unknownUser);
    return i;
  }

  @override
  Future<AppUser> signIn(int userId, String pin) async {
    final r = rows[_index(userId)];
    if (!r.user.active) throw const AuthException(AuthProblem.inactive);
    if (r.pin != normalizePin(pin)) throw const AuthException(AuthProblem.wrongPin);
    return r.user;
  }

  @override
  Future<void> setPin(int userId, String pin) async {
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    final i = _index(userId);
    rows[i] = (user: rows[i].user, pin: normalizePin(pin));
  }

  @override
  Future<void> changePin(int userId, {required String currentPin, required String newPin}) async {
    final r = rows[_index(userId)];
    if (r.pin != normalizePin(currentPin)) throw const AuthException(AuthProblem.wrongPin);
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
    final i = _index(userId);
    if (name.trim().isEmpty) throw const AuthException(AuthProblem.invalidName);
    if (rows.any((r) => r.user.id != userId && r.user.name.toLowerCase() == name.trim().toLowerCase())) {
      throw const AuthException(AuthProblem.nameTaken);
    }
    if (mobile.trim().isNotEmpty && !isValidMobile(mobile)) throw const AuthException(AuthProblem.invalidPhone);
    final u = rows[i].user;
    final updated = AppUser(
      id: u.id,
      name: name.trim(),
      role: u.role,
      active: u.active,
      mobile: mobile.trim(),
      phone: phone.trim(),
      address: address.trim(),
    );
    rows[i] = (user: updated, pin: rows[i].pin);
    return updated;
  }

  @override
  Future<void> setActive(int userId, bool active) async {
    final i = _index(userId);
    final u = rows[i].user;
    if (!active && u.isOwner && rows.where((r) => r.user.isOwner && r.user.active && r.user.id != userId).isEmpty) {
      throw const AuthException(AuthProblem.lastOwner);
    }
    rows[i] = (user: AppUser(id: u.id, name: u.name, role: u.role, active: active), pin: rows[i].pin);
  }
}

class _MemorySettings implements SettingsStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Screens implements ScreenFactory {
  int signOuts = 0;
  @override
  Widget shell({required VoidCallback onSignOut}) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () {
              signOuts++;
              onSignOut();
            },
            child: const Text('APP-SHELL'),
          ),
        ),
      );

  @override
  Widget home() => const SizedBox(key: ValueKey('home'));

  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PIN hashing', () {
    final hasher = Sha256PinHasher();

    test('the same PIN and salt always give the same hash; a different salt or PIN does not', () {
      final salt = hasher.newSalt();
      expect(hasher.hash('1234', salt), hasher.hash('1234', salt));
      expect(hasher.hash('1234', salt), isNot(hasher.hash('1235', salt)));
      expect(hasher.hash('1234', salt), isNot(hasher.hash('1234', hasher.newSalt())));
    });

    test('the hash does not contain the PIN, and salts are not repeated', () {
      final salt = hasher.newSalt();
      expect(hasher.hash('1234', salt), isNot(contains('1234')));
      expect({for (var i = 0; i < 50; i++) hasher.newSalt()}, hasable(50));
    });

    test('PIN rules: 4 to 6 digits, Bangla digits count', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('১২৩৪'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('abcd'), isFalse);
      expect(normalizePin('১২৩৪'), '1234');
    });
  });

  group('users (SQL)', () {
    const dbFile = 'auth_test.db';
    late AppDatabase appDb;
    late _Clock clock;
    late SqliteUserRepository users;

    Future<String> path() async => p.join(await getDatabasesPath(), dbFile);

    setUp(() async {
      await deleteDatabase(await path());
      clock = _Clock(DateTime(2026, 11, 22, 10));
      appDb = AppDatabase(fileName: dbFile);
      users = SqliteUserRepository(appDb, _ReversingHasher(), clock);
    });

    tearDown(() async => (await appDb.db).close());

    test('a new install has no users; creating one changes that', () async {
      expect(await users.hasUsers(), isFalse);
      final owner = await users.create(name: '  মালিক ', pin: '1234', role: UserRole.owner);
      expect(owner.name, 'মালিক', reason: 'trimmed');
      expect(owner.isOwner, isTrue);
      expect(await users.hasUsers(), isTrue);
    });

    test('the PIN is never stored, only its salted hash', () async {
      await users.create(name: 'রহিম', pin: '4321', role: UserRole.staff);
      final row = (await (await appDb.db).query('users')).single;
      expect(row['pin_hash'], 'salt0|4321');
      expect(row.values.whereType<String>().where((v) => v == '4321'), isEmpty);
    });

    test('names and PINs are checked', () async {
      await expectLater(users.create(name: '  ', pin: '1234', role: UserRole.staff), throwsAuth(AuthProblem.invalidName));
      await expectLater(users.create(name: 'ক', pin: '12', role: UserRole.staff), throwsAuth(AuthProblem.invalidPin));
      await users.create(name: 'Karim', pin: '1234', role: UserRole.staff);
      await expectLater(users.create(name: 'karim', pin: '5678', role: UserRole.staff), throwsAuth(AuthProblem.nameTaken),
          reason: 'names are not case sensitive');
      expect(await users.all(), hasLength(1));
    });

    test('the right PIN signs in (Bangla digits too); a wrong one or an unknown user is refused', () async {
      final u = await users.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
      expect((await users.signIn(u.id, '1234')).name, 'রহিম');
      expect((await users.signIn(u.id, '১২৩৪')).id, u.id);
      await expectLater(users.signIn(u.id, '1235'), throwsAuth(AuthProblem.wrongPin));
      await expectLater(users.signIn(u.id, ''), throwsAuth(AuthProblem.wrongPin));
      await expectLater(users.signIn(999, '1234'), throwsAuth(AuthProblem.unknownUser));
    });

    test('changing a PIN replaces the old one', () async {
      final u = await users.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
      await users.setPin(u.id, '9999');
      await expectLater(users.signIn(u.id, '1234'), throwsAuth(AuthProblem.wrongPin));
      expect((await users.signIn(u.id, '9999')).id, u.id);
      await expectLater(users.setPin(u.id, '12'), throwsAuth(AuthProblem.invalidPin));
      await expectLater(users.setPin(999, '1234'), throwsAuth(AuthProblem.unknownUser));
    });

    test('a switched-off user cannot sign in, and can be switched back on', () async {
      await users.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      final staff = await users.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
      await users.setActive(staff.id, false);
      await expectLater(users.signIn(staff.id, '1234'), throwsAuth(AuthProblem.inactive));
      expect((await users.all()).firstWhere((u) => u.id == staff.id).active, isFalse);
      await users.setActive(staff.id, true);
      expect((await users.signIn(staff.id, '1234')).id, staff.id);
    });

    test('the last active owner cannot be switched off, but another owner can', () async {
      final a = await users.create(name: 'ক', pin: '1111', role: UserRole.owner);
      await expectLater(users.setActive(a.id, false), throwsAuth(AuthProblem.lastOwner));
      final b = await users.create(name: 'খ', pin: '2222', role: UserRole.owner);
      await users.setActive(a.id, false);
      await expectLater(users.setActive(b.id, false), throwsAuth(AuthProblem.lastOwner));
      expect((await users.signIn(b.id, '2222')).id, b.id);
    });

    test('a staff member can always be switched off, whatever else is true', () async {
      final s = await users.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
      await users.setActive(s.id, false);
      await expectLater(users.setActive(999, false), throwsAuth(AuthProblem.unknownUser));
    });
  });

  group('who did it (SQL)', () {
    const dbFile = 'tracking_test.db';
    late AppDatabase appDb;
    late _Clock clock;
    late Session session;
    late SqliteProductRepository products;
    late SqliteStockRepository stock;
    late SqliteSalesRepository sales;
    late SqliteCustomerRepository customers;
    late Product nails;

    const rahim = AppUser(id: 7, name: 'রহিম', role: UserRole.staff);
    const karim = AppUser(id: 8, name: 'করিম', role: UserRole.staff);

    Future<String> path() async => p.join(await getDatabasesPath(), dbFile);

    setUp(() async {
      await deleteDatabase(await path());
      clock = _Clock(DateTime(2026, 11, 22, 10));
      appDb = AppDatabase(fileName: dbFile);
      session = Session()..signIn(rahim);
      products = SqliteProductRepository(appDb, clock, actor: session);
      stock = SqliteStockRepository(appDb, clock, actor: session);
      sales = SqliteSalesRepository(appDb, clock, actor: session);
      customers = SqliteCustomerRepository(appDb, clock, actor: session);
      nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 50, unit: 'কেজি'));
    });

    tearDown(() async => (await appDb.db).close());

    Future<Bill> sell({CustomerInfo? who, double? paid}) => sales.checkout(
          [SaleLine(productId: nails.id!, quantity: 2, unitPrice: 100)],
          customer: who ?? const CustomerInfo(whatsapp: '01911111111'),
          paid: paid,
        );

    test('a bill remembers who sold it, on the bill itself and when read back', () async {
      final bill = await sell();
      expect(bill.soldBy, 'রহিম');
      session.signIn(karim);
      await sell();
      final bills = await sales.billsOn(DateTime(2026, 11, 22));
      expect(bills.map((b) => b.soldBy).toSet(), {'রহিম', 'করিম'});
      expect((await sales.billById(bill.id!))!.soldBy, 'রহিম');
    });

    test('stock history names who added, restocked and sold', () async {
      await stock.restock(nails.id!, 10);
      session.signIn(karim);
      await sell();
      final history = await stock.history(nails.id!);
      final byReason = {for (final e in history) e.reason.name: e.userName};
      expect(byReason['initial'], 'রহিম', reason: 'who created the product with its stock');
      expect(byReason['restock'], 'রহিম');
      expect(byReason['sale'], 'করিম');
    });

    test('cancelling a bill is also on record, under whoever cancelled it', () async {
      final bill = await sell();
      session.signIn(karim);
      await sales.voidBill(bill.id!);
      final history = await stock.history(nails.id!);
      expect(history.firstWhere((e) => e.reason.name == 'saleVoid').userName, 'করিম');
    });

    test('a payment remembers who took the money', () async {
      const who = CustomerInfo(
        name: 'গ্রাহক',
        mobile: '01712345678',
        nid: '1234567890',
        address: 'কাজিপুর',
        whatsapp: '01712345678',
      );
      await sell(who: who, paid: 0);
      final id = (await customers.all()).single.id;
      session.signIn(karim);
      final payment = await customers.collectPayment(id, 50);
      expect(payment.receivedBy, 'করিম');
      expect((await customers.paymentsOf(id)).single.receivedBy, 'করিম');
    });

    test('with nobody signed in the name is simply empty (and nothing breaks)', () async {
      session.signOut();
      final bill = await sell();
      expect(bill.soldBy, '');
      expect((await sales.billById(bill.id!))!.soldBy, '');
    });

    test('a database from before logins upgrades; old rows have no name, new ones do', () async {
      await sell(); // a bill with a name
      final db = await appDb.db;
      // Make it look like version 8: no users table, no who-columns.
      await db.execute('DROP TABLE users');
      for (final table in ['bills', 'stock_log', 'payments']) {
        await db.execute('ALTER TABLE $table DROP COLUMN user_id');
        await db.execute('ALTER TABLE $table DROP COLUMN user_name');
      }
      await db.execute('PRAGMA user_version = 8');
      await db.close();

      appDb = AppDatabase(fileName: dbFile);
      sales = SqliteSalesRepository(appDb, clock, actor: session);
      final old = (await sales.billsOn(DateTime(2026, 11, 22))).single;
      expect(old.soldBy, '', reason: 'nobody was recorded then');
      expect(old.total, 200, reason: 'old data is intact');
      final fresh = await sell();
      expect(fresh.soldBy, 'রহিম');
      expect(await SqliteUserRepository(appDb, _ReversingHasher(), clock).hasUsers(), isFalse);
    });
  });

  group('sign in screens', () {
    late _MemoryUsers repo;
    late Session session;
    late _Screens screens;

    setUp(() {
      repo = _MemoryUsers();
      session = Session();
      screens = _Screens();
    });

    Future<AuthViewModel> open(WidgetTester tester) async {
      final vm = AuthViewModel(repo, session);
      await tester.pumpWidget(MaterialApp(home: AuthGate(viewModel: vm, screens: screens)));
      await tester.pumpAndSettle();
      return vm;
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('a new shop is asked for its owner first', (tester) async {
      await open(tester);
      expect(find.text(Bn.setupTitle), findsOneWidget);
      expect(find.text('APP-SHELL'), findsNothing);
    });

    testWidgets('creating the owner signs them in and opens the app', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.ownerName), 'মালিক');
      await tester.enterText(field(Bn.pinLabel), '1234');
      await tester.enterText(field(Bn.pinConfirm), '1234');
      await tester.tap(find.text(Bn.createOwner));
      await tester.pumpAndSettle();

      expect(find.text('APP-SHELL'), findsOneWidget);
      expect(session.user!.name, 'মালিক');
      expect(session.user!.isOwner, isTrue);
      expect(repo.rows, hasLength(1));
    });

    testWidgets('PINs that differ, or that are too short, or a missing name, are refused', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.pinLabel), '1234');
      await tester.enterText(field(Bn.pinConfirm), '1235');
      await tester.tap(find.text(Bn.createOwner));
      await tester.pumpAndSettle();
      expect(find.text(Bn.pinMismatch), findsOneWidget);
      expect(find.text(Bn.required), findsOneWidget, reason: 'no name');

      await tester.enterText(field(Bn.pinLabel), '12');
      await tester.tap(find.text(Bn.createOwner));
      await tester.pumpAndSettle();
      expect(find.text(Bn.authInvalidPin), findsOneWidget);
      expect(repo.rows, isEmpty);
      expect(session.user, isNull);
    });

    testWidgets('the PIN is hidden and limited to 6 digits', (tester) async {
      await open(tester);
      expect(tester.widget<EditableText>(find.descendant(of: field(Bn.pinLabel), matching: find.byType(EditableText))).obscureText, isTrue);
      await tester.enterText(field(Bn.pinLabel), '1234567890');
      expect(tester.widget<TextFormField>(field(Bn.pinLabel)).controller!.text, '123456');
    });

    Future<void> addPeople() async {
      await repo.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      await repo.create(name: 'রহিম', pin: '2222', role: UserRole.staff);
      final off = await repo.create(name: 'গেছে', pin: '3333', role: UserRole.staff);
      await repo.setActive(off.id, false);
    }

    testWidgets('sign in: pick who you are, type the PIN, and the app opens', (tester) async {
      await addPeople();
      await open(tester);
      expect(find.text(Bn.chooseUser), findsOneWidget);
      expect(find.text('গেছে'), findsNothing, reason: 'switched-off people are not offered');

      await tester.tap(find.text('রহিম'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2222');
      await tester.tap(find.text(Bn.signIn));
      await tester.pumpAndSettle();

      expect(find.text('APP-SHELL'), findsOneWidget);
      expect(session.user!.name, 'রহিম');
    });

    testWidgets('the sign in button waits until someone is picked', (tester) async {
      await addPeople();
      await open(tester);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, Bn.signIn)).onPressed, isNull);
    });

    testWidgets('a wrong PIN is refused, the field is cleared, and nobody is signed in', (tester) async {
      await addPeople();
      await open(tester);
      await tester.tap(find.text('রহিম'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '9999');
      await tester.tap(find.text(Bn.signIn));
      await tester.pumpAndSettle();

      expect(find.text(Bn.authWrongPin), findsOneWidget);
      expect(find.text('APP-SHELL'), findsNothing);
      expect(session.user, isNull);
      expect(tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text, '');
    });

    testWidgets('a single user is already picked', (tester) async {
      await repo.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      await open(tester);
      await tester.enterText(find.byType(TextFormField), '1111');
      await tester.tap(find.text(Bn.signIn));
      await tester.pumpAndSettle();
      expect(find.text('APP-SHELL'), findsOneWidget);
    });

    testWidgets('signing out returns to the sign in screen, and nobody is signed in', (tester) async {
      await repo.create(name: 'মালিক', pin: '1111', role: UserRole.owner);
      await open(tester);
      await tester.enterText(find.byType(TextFormField), '1111');
      await tester.tap(find.text(Bn.signIn));
      await tester.pumpAndSettle();
      expect(session.user, isNotNull);

      await tester.tap(find.text('APP-SHELL')); // the fake shell signs out
      await tester.pumpAndSettle();
      expect(session.user, isNull);
      expect(find.text(Bn.chooseUser), findsOneWidget);
      expect(find.text('APP-SHELL'), findsNothing);
    });

    testWidgets('if everyone has been switched off, it says so instead of showing an empty form', (tester) async {
      final a = await repo.create(name: 'ক', pin: '1111', role: UserRole.owner);
      await repo.create(name: 'খ', pin: '2222', role: UserRole.owner);
      await repo.setActive(a.id, false);
      repo.rows.removeWhere((r) => r.user.name == 'খ');
      await open(tester);
      expect(find.text(Bn.noActiveUsers), findsOneWidget);
    });
  });

  group('staff screen', () {
    late _MemoryUsers repo;
    late Session session;

    setUp(() async {
      repo = _MemoryUsers();
      session = Session();
      final owner = await repo.create(name: 'আবদুল', pin: '1111', role: UserRole.owner);
      session.signIn(owner);
      await repo.create(name: 'রহিম', pin: '2222', role: UserRole.staff);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: UsersPage(viewModel: UsersViewModel(repo, session))));
      await tester.pumpAndSettle();
    }

    Finder card(String name) => find.ancestor(of: find.text(name), matching: find.byType(ItemCard));

    testWidgets('lists everyone with their role, and marks you', (tester) async {
      await open(tester);
      expect(find.text('আবদুল'), findsOneWidget);
      expect(find.text('রহিম'), findsOneWidget);
      expect(find.text(Bn.youChip), findsOneWidget);
      expect(find.text(Bn.roleOwner), findsOneWidget);
      expect(find.descendant(of: find.byType(ItemCard), matching: find.text(Bn.roleStaff)), findsOneWidget);
    });

    testWidgets('adding a person: name, PIN, role', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.addUser));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, Bn.userName), 'সালমা');
      await tester.enterText(find.widgetWithText(TextFormField, Bn.pinLabel), '5555');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();

      expect(find.text('সালমা'), findsOneWidget);
      expect(find.text(Bn.userAdded), findsOneWidget);
      final added = repo.rows.firstWhere((r) => r.user.name == 'সালমা');
      expect(added.user.role, UserRole.staff, reason: 'staff unless owner is picked');
      expect(added.pin, '5555');
    });

    testWidgets('a new owner can be added by picking the owner role', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.addUser));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, Bn.userName), 'ভাই');
      await tester.enterText(find.widgetWithText(TextFormField, Bn.pinLabel), '5555');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(Bn.roleOwner)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(repo.rows.firstWhere((r) => r.user.name == 'ভাই').user.role, UserRole.owner);
    });

    testWidgets('a taken name or a short PIN is explained and nothing is added', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.addUser));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, Bn.userName), 'রহিম');
      await tester.enterText(find.widgetWithText(TextFormField, Bn.pinLabel), '12');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(find.text(Bn.authInvalidPin), findsOneWidget, reason: 'the dialog stays open');

      await tester.enterText(find.widgetWithText(TextFormField, Bn.pinLabel), '5555');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(find.text(Bn.authNameTaken), findsOneWidget);
      expect(repo.rows, hasLength(2));
    });

    testWidgets('changing someone\'s PIN', (tester) async {
      await open(tester);
      await tester.tap(card('রহিম'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.resetPin));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, Bn.newPinLabel), '7777');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(repo.rows.firstWhere((r) => r.user.name == 'রহিম').pin, '7777');
      expect(find.text(Bn.pinChanged), findsOneWidget);
    });

    testWidgets('switching someone off and on again', (tester) async {
      await open(tester);
      await tester.tap(card('রহিম'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.switchOff));
      await tester.pumpAndSettle();
      expect(repo.rows.firstWhere((r) => r.user.name == 'রহিম').user.active, isFalse);
      expect(find.text(Bn.inactiveChip), findsOneWidget);

      await tester.tap(card('রহিম'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.switchOn));
      await tester.pumpAndSettle();
      expect(repo.rows.firstWhere((r) => r.user.name == 'রহিম').user.active, isTrue);
    });

    testWidgets('you cannot switch yourself off: the option is not even offered', (tester) async {
      await open(tester);
      await tester.tap(card('আবদুল'));
      await tester.pumpAndSettle();
      expect(find.text(Bn.resetPin), findsOneWidget);
      expect(find.text(Bn.switchOff), findsNothing);
    });

    test('and the view model refuses it too', () async {
      final vm = UsersViewModel(repo, session);
      await vm.load();
      await expectLater(vm.setActive(vm.users.first, false), throwsAuth(AuthProblem.lastOwner));
    });
  });

  group('profile (SQL)', () {
    const dbFile = 'profile_test.db';
    late AppDatabase appDb;
    late SqliteUserRepository users;
    late AppUser rahim;

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      appDb = AppDatabase(fileName: dbFile);
      users = SqliteUserRepository(appDb, _ReversingHasher(), _Clock(DateTime(2026, 11, 22)));
      rahim = await users.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
    });

    tearDown(() async => (await appDb.db).close());

    test('a new person has an empty profile', () {
      expect((rahim.mobile, rahim.phone, rahim.address), ('', '', ''));
    });

    test('name, mobile, other phone and address are saved and come back at sign in and in the list', () async {
      final saved = await users.updateProfile(
        rahim.id,
        name: '  রহিম মিয়া ',
        mobile: '+৮৮০ ১৭১২ ৩৪৫৬৭৮',
        phone: '02-9876543',
        address: ' কাজিপুর, সিরাজগঞ্জ ',
      );
      expect(saved.name, 'রহিম মিয়া');
      expect(saved.mobile, '01712345678', reason: 'tidied to the usual 11 digits');
      expect(saved.phone, '02-9876543');
      expect(saved.address, 'কাজিপুর, সিরাজগঞ্জ');
      expect(saved.role, UserRole.staff, reason: 'nobody can change their own role');

      final signedIn = await users.signIn(rahim.id, '1234');
      expect(signedIn.name, 'রহিম মিয়া');
      expect(signedIn.mobile, '01712345678');
      expect((await users.all()).single.address, 'কাজিপুর, সিরাজগঞ্জ');
    });

    test('everything but the name may be left blank, and cleared again', () async {
      await users.updateProfile(rahim.id, name: 'রহিম', mobile: '01712345678', address: 'এক জায়গা');
      final cleared = await users.updateProfile(rahim.id, name: 'রহিম');
      expect((cleared.mobile, cleared.phone, cleared.address), ('', '', ''));
    });

    test('a blank name, a taken name or a bad number is refused and nothing changes', () async {
      await users.create(name: 'Karim', pin: '2222', role: UserRole.staff);
      await expectLater(users.updateProfile(rahim.id, name: '   '), throwsAuth(AuthProblem.invalidName));
      await expectLater(users.updateProfile(rahim.id, name: 'karim'), throwsAuth(AuthProblem.nameTaken));
      await expectLater(users.updateProfile(rahim.id, name: 'রহিম', mobile: '12345'), throwsAuth(AuthProblem.invalidPhone));
      await expectLater(users.updateProfile(rahim.id, name: 'রহিম', phone: '12'), throwsAuth(AuthProblem.invalidPhone));
      await expectLater(users.updateProfile(999, name: 'কেউ'), throwsAuth(AuthProblem.unknownUser));
      expect((await users.signIn(rahim.id, '1234')).name, 'রহিম');
    });

    test('keeping your own name is not "taken", and only the letters\' case may change', () async {
      await users.updateProfile(rahim.id, name: 'রহিম', address: 'ক');
      final cased = await users.create(name: 'Salma', pin: '3333', role: UserRole.staff);
      final saved = await users.updateProfile(cased.id, name: 'SALMA');
      expect(saved.name, 'SALMA');
    });

    test('changing your own PIN needs the current one', () async {
      await expectLater(users.changePin(rahim.id, currentPin: '0000', newPin: '5678'), throwsAuth(AuthProblem.wrongPin));
      await expectLater(users.changePin(rahim.id, currentPin: '1234', newPin: '12'), throwsAuth(AuthProblem.invalidPin));
      await users.changePin(rahim.id, currentPin: '১২৩৪', newPin: '5678');
      await expectLater(users.signIn(rahim.id, '1234'), throwsAuth(AuthProblem.wrongPin));
      expect((await users.signIn(rahim.id, '5678')).id, rahim.id);
      await expectLater(users.changePin(999, currentPin: '1', newPin: '5678'), throwsAuth(AuthProblem.unknownUser));
    });

    test('a database from before profiles upgrades, and existing users keep working', () async {
      final db = await appDb.db;
      for (final column in ['mobile', 'phone', 'address']) {
        await db.execute('ALTER TABLE users DROP COLUMN $column');
      }
      await db.execute('PRAGMA user_version = 9');
      await db.close();

      appDb = AppDatabase(fileName: dbFile);
      users = SqliteUserRepository(appDb, _ReversingHasher(), _Clock(DateTime(2026, 11, 22)));
      expect((await users.signIn(rahim.id, '1234')).mobile, '');
      final saved = await users.updateProfile(rahim.id, name: 'রহিম', mobile: '01712345678');
      expect(saved.mobile, '01712345678');
    });
  });

  group('profile screen', () {
    late _MemoryUsers repo;
    late Session session;
    late ProfileViewModel vm;

    setUp(() async {
      repo = _MemoryUsers();
      await repo.create(name: 'করিম', pin: '9999', role: UserRole.staff);
      final me = await repo.create(name: 'রহিম', pin: '1234', role: UserRole.staff);
      session = Session()..signIn(me);
      vm = ProfileViewModel(repo, session);
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ProfilePage(viewModel: vm)));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);

    testWidgets('starts with what is known about you', (tester) async {
      await repo.updateProfile(session.user!.id, name: 'রহিম', mobile: '01712345678', address: 'কাজিপুর');
      session.signIn((await repo.all()).firstWhere((u) => u.name == 'রহিম'));
      await open(tester);
      expect(tester.widget<TextFormField>(field(Bn.userName)).controller!.text, 'রহিম');
      expect(tester.widget<TextFormField>(field(Bn.profileMobile)).controller!.text, '01712345678');
      expect(tester.widget<TextFormField>(field(Bn.profileAddress)).controller!.text, 'কাজিপুর');
    });

    testWidgets('saving updates the person, and the signed-in name used on bills follows at once', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.userName), 'রহিম মিয়া');
      await tester.enterText(field(Bn.profileMobile), '01712345678');
      await tester.enterText(field(Bn.profilePhone), '029876543');
      await tester.enterText(field(Bn.profileAddress), 'কাজিপুর');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();

      expect(find.text(Bn.profileSaved), findsOneWidget);
      expect(session.user!.name, 'রহিম মিয়া');
      final saved = (await repo.all()).firstWhere((u) => u.id == session.user!.id);
      expect((saved.mobile, saved.phone, saved.address), ('01712345678', '029876543', 'কাজিপুর'));
    });

    testWidgets('a blank name, a name someone else has, or a bad number is explained', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.userName), '');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(find.text(Bn.required), findsOneWidget);

      await tester.enterText(field(Bn.userName), 'করিম');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(find.text(Bn.authNameTaken), findsOneWidget);

      await tester.enterText(field(Bn.userName), 'রহিম');
      await tester.enterText(field(Bn.profileMobile), '123');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(find.text(Bn.authInvalidPhone), findsOneWidget);
      expect(session.user!.name, 'রহিম');
    });

    Future<void> tapPinButton(WidgetTester tester) async {
      final button = find.widgetWithText(FilledButton, Bn.profilePinSection);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('changing the PIN: current PIN, new PIN twice', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.currentPinLabel), '1234');
      await tester.enterText(field(Bn.newPinLabel), '4321');
      await tester.enterText(field(Bn.pinConfirm), '4321');
      await tapPinButton(tester);

      expect(find.text(Bn.pinChanged), findsOneWidget);
      expect(repo.rows.firstWhere((r) => r.user.name == 'রহিম').pin, '4321');
      expect(tester.widget<TextFormField>(field(Bn.currentPinLabel)).controller!.text, '', reason: 'the fields are cleared');
    });

    testWidgets('a wrong current PIN, PINs that differ, or a short PIN change nothing', (tester) async {
      await open(tester);
      await tester.enterText(field(Bn.currentPinLabel), '0000');
      await tester.enterText(field(Bn.newPinLabel), '4321');
      await tester.enterText(field(Bn.pinConfirm), '4321');
      await tapPinButton(tester);
      expect(find.text(Bn.authWrongPin), findsOneWidget);

      await tester.enterText(field(Bn.currentPinLabel), '1234');
      await tester.enterText(field(Bn.pinConfirm), '4322');
      await tapPinButton(tester);
      expect(find.text(Bn.pinMismatch), findsOneWidget);

      await tester.enterText(field(Bn.newPinLabel), '12');
      await tester.enterText(field(Bn.pinConfirm), '12');
      await tapPinButton(tester);
      expect(find.text(Bn.authInvalidPin), findsWidgets);
      expect(repo.rows.firstWhere((r) => r.user.name == 'রহিম').pin, '1234');
    });
  });

  group('theme', () {
    late _MemorySettings settings;
    late ThemeViewModel theme;

    setUp(() {
      settings = _MemorySettings();
      theme = ThemeViewModel(settings);
    });

    test('follows the phone until told otherwise', () async {
      await theme.load();
      expect(theme.preference, ThemePreference.system);
      expect(theme.mode, ThemeMode.system);
    });

    test('light and dark are applied and remembered', () async {
      await theme.choose(ThemePreference.dark);
      expect(theme.mode, ThemeMode.dark);
      expect(settings.values['theme'], 'dark');

      final later = ThemeViewModel(settings);
      await later.load();
      expect(later.mode, ThemeMode.dark, reason: 'still dark after a restart');
      await later.choose(ThemePreference.light);
      expect(later.mode, ThemeMode.light);
      expect(settings.values['theme'], 'light');
    });

    test('an unknown saved value falls back to the phone\'s setting', () async {
      settings.values['theme'] = 'purple';
      await theme.load();
      expect(theme.mode, ThemeMode.system);
    });

    test('listeners hear about a change, and about nothing when the choice is the same', () async {
      var heard = 0;
      theme.addListener(() => heard++);
      await theme.choose(ThemePreference.system);
      expect(heard, 0);
      await theme.choose(ThemePreference.dark);
      expect(heard, 1);
    });

    testWidgets('the settings page shows the choice and changes it', (tester) async {
      await tester.pumpWidget(MaterialApp(home: SettingsPage(theme: theme)));
      await tester.tap(find.text(Bn.themeDark));
      await tester.pumpAndSettle();
      expect(theme.preference, ThemePreference.dark);
      expect(tester.widget<SegmentedButton<ThemePreference>>(find.byType(SegmentedButton<ThemePreference>)).selected, {ThemePreference.dark});

      await tester.tap(find.text(Bn.themeLight));
      await tester.pumpAndSettle();
      expect(theme.preference, ThemePreference.light);
    });

    testWidgets('the whole app switches theme straight away', (tester) async {
      await tester.pumpWidget(HardwareShopApp(screens: _Screens(), theme: theme));
      MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app().themeMode, ThemeMode.system);
      await theme.choose(ThemePreference.dark);
      await tester.pump();
      expect(app().themeMode, ThemeMode.dark);
      await theme.choose(ThemePreference.light);
      await tester.pump();
      expect(app().themeMode, ThemeMode.light);
    });
  });
}

/// A matcher for "this many distinct values".
Matcher hasable(int n) => hasLength(n);
