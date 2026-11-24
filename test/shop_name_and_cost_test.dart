import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_dashboard_repository.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/data/sqlite_shop_repository.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/shop.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/home_shell/home_shell.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/settings/settings_page.dart';
import 'package:hardware_shop/presentation/settings/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/settings/shop_name_viewmodel.dart';
import 'package:hardware_shop/presentation/widgets/sell_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

class _Shop implements ShopRepository {
  String? stored;
  final renames = <String>[];
  Object? failWith;

  @override
  Future<String?> name() async => stored;

  @override
  Future<void> rename(String name) async {
    if (failWith != null) throw failWith!;
    final clean = name.trim();
    if (clean.isEmpty) throw const ShopException(ShopProblem.emptyName);
    if (clean.length > maxShopNameLength) throw const ShopException(ShopProblem.nameTooLong);
    renames.add(clean);
    stored = clean;
  }
}

class _Sync implements SyncService {
  final _changes = StreamController<void>.broadcast();
  bool get hasListener => _changes.hasListener;
  void announce() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _MemorySettings implements SettingsStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Screens implements ScreenFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('shop name (stored)', () {
    const dbFile = 'shop_name_test.db';
    late AppDatabase db;
    late SqliteShopRepository shop;

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      db = AppDatabase(fileName: dbFile);
      shop = SqliteShopRepository(db);
    });

    tearDown(() async => (await db.db).close());

    test('is empty until chosen, then kept, and changed in place', () async {
      expect(await shop.name(), isNull);
      await shop.rename('  হাসান হার্ডওয়্যার ');
      expect(await shop.name(), 'হাসান হার্ডওয়্যার');
      await shop.rename('আরেক নাম');
      expect(await shop.name(), 'আরেক নাম');
      expect(await (await db.db).query('shop_settings'), hasLength(1));
    });

    test('empty, spaces only or longer than 60 is refused and the old name stays', () async {
      await shop.rename('ঠিক নাম');
      await expectLater(shop.rename(''), throwsA(isA<ShopException>().having((e) => e.problem, 'p', ShopProblem.emptyName)));
      await expectLater(shop.rename('   '), throwsA(isA<ShopException>()));
      await expectLater(shop.rename('ক' * 61), throwsA(isA<ShopException>().having((e) => e.problem, 'p', ShopProblem.nameTooLong)));
      expect(await shop.name(), 'ঠিক নাম');
      await shop.rename('ক' * 60);
      expect((await shop.name())!.length, 60);
    });

    test('a database from before shop names gets the table, and everything else is untouched', () async {
      final raw = await db.db;
      await raw.insert('categories', {'name': 'আগের ক্যাটাগরি'});
      await raw.execute('DROP TABLE shop_settings');
      await raw.execute('PRAGMA user_version = 12');
      await raw.close();

      db = AppDatabase(fileName: dbFile);
      shop = SqliteShopRepository(db);
      expect(await shop.name(), isNull);
      await shop.rename('হাসান');
      expect(await shop.name(), 'হাসান');
      expect(await (await db.db).query('categories', where: 'name = ?', whereArgs: ['আগের ক্যাটাগরি']), hasLength(1));
    });
  });

  group('shop name (view model)', () {
    late _Shop repo;
    late _Sync sync;
    late ShopNameViewModel vm;

    setUp(() {
      repo = _Shop();
      sync = _Sync();
      vm = ShopNameViewModel(repo, sync);
    });

    tearDown(() => vm.dispose());

    test('until the owner chooses one it is the app\'s own name', () async {
      await vm.load();
      expect((vm.name, vm.hasName), (Bn.appTitle, false));
    });

    test('renaming changes it everywhere that listens, at once', () async {
      var heard = 0;
      vm.addListener(() => heard++);
      await vm.rename('হাসান হার্ডওয়্যার');
      expect((vm.name, vm.hasName, heard), ('হাসান হার্ডওয়্যার', true, 1));
    });

    test('a refused name changes nothing and tells nobody', () async {
      await vm.rename('ভালো নাম');
      var heard = 0;
      vm.addListener(() => heard++);
      await expectLater(vm.rename(''), throwsA(isA<ShopException>()));
      expect((vm.name, heard), ('ভালো নাম', 0));
    });

    test('a rename made on another phone shows up after the next sync', () async {
      await vm.load();
      repo.stored = 'অন্য ফোনের দেওয়া নাম';
      sync.announce();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.name, 'অন্য ফোনের দেওয়া নাম');
    });

    test('it stops listening when it is thrown away', () async {
      vm.dispose();
      expect(sync.hasListener, isFalse);
      vm = ShopNameViewModel(repo); // (so tearDown has something to dispose)
    });
  });

  group('settings screen', () {
    late _Shop repo;
    late ShopNameViewModel shopName;

    setUp(() async {
      repo = _Shop();
      shopName = ShopNameViewModel(repo);
    });

    Future<void> open(WidgetTester tester, {bool owner = true}) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await shopName.load();
      await tester.pumpWidget(MaterialApp(
        home: SettingsPage(theme: ThemeViewModel(_MemorySettings()), shopName: shopName, canEditShop: owner),
      ));
      await _settle(tester);
    }

    Finder nameField() => find.widgetWithText(TextFormField, Bn.shopNameLabel);

    testWidgets('the owner can rename the shop, and sees it saved', (tester) async {
      await open(tester);
      expect(tester.widget<TextFormField>(nameField()).controller!.text, '', reason: 'nothing chosen yet');
      await tester.enterText(nameField(), '  হাসান হার্ডওয়্যার ');
      await tester.tap(find.text(Bn.save));
      await _settle(tester);
      expect(repo.renames, ['হাসান হার্ডওয়্যার']);
      expect(find.text(Bn.shopNameSaved), findsOneWidget);
      expect(shopName.name, 'হাসান হার্ডওয়্যার');
      expect(tester.widget<TextFormField>(nameField()).controller!.text, 'হাসান হার্ডওয়্যার', reason: 'tidied in the box too');
    });

    testWidgets('it starts with the name that is there now', (tester) async {
      repo.stored = 'আগের নাম';
      await open(tester);
      expect(tester.widget<TextFormField>(nameField()).controller!.text, 'আগের নাম');
    });

    testWidgets('an empty name, a name that is too long, or no connection is explained and nothing changes', (tester) async {
      repo.stored = 'ভালো নাম';
      await open(tester);
      await tester.enterText(nameField(), '   ');
      await tester.tap(find.text(Bn.save));
      await _settle(tester);
      expect(find.text(Bn.shopNameEmpty), findsOneWidget);

      await tester.enterText(nameField(), 'ক' * 61);
      await tester.tap(find.text(Bn.save));
      await _settle(tester);
      expect(find.text(Bn.shopNameTooLong), findsOneWidget);

      repo.failWith = const SyncException(SyncProblem.offline);
      await tester.enterText(nameField(), 'নতুন');
      await tester.tap(find.text(Bn.save));
      await _settle(tester);
      expect(find.text(Bn.syncOffline), findsOneWidget);
      expect(shopName.name, 'ভালো নাম');
    });

    testWidgets('staff do not get to rename the shop, but still choose their theme', (tester) async {
      await open(tester, owner: false);
      expect(find.text(Bn.shopNameSection), findsNothing);
      expect(nameField(), findsNothing);
      expect(find.text(Bn.themeSection), findsOneWidget);
    });
  });

  group('the menu title', () {
    late _Shop repo;
    late ShopNameViewModel shopName;

    setUp(() async {
      repo = _Shop();
      shopName = ShopNameViewModel(repo);
    });

    Future<void> openMenu(WidgetTester tester, {ShopNameViewModel? name}) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(const AppUser(id: 1, name: 'মালিক', role: UserRole.owner));
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _Screens(), currentUser: session, onSignOut: () {}, shopName: name),
      ));
      await _settle(tester);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await _settle(tester);
    }

    Finder inMenu(String text) => find.descendant(of: find.byType(NavigationDrawer), matching: find.text(text));

    testWidgets('shows the shop\'s own name once the owner has chosen it', (tester) async {
      repo.stored = 'হাসান হার্ডওয়্যার';
      await shopName.load();
      await openMenu(tester, name: shopName);
      expect(inMenu('হাসান হার্ডওয়্যার'), findsOneWidget);
      expect(inMenu(Bn.appTitle), findsNothing);
    });

    testWidgets('shows the app\'s name until then', (tester) async {
      await openMenu(tester, name: shopName);
      expect(inMenu(Bn.appTitle), findsOneWidget);
    });

    testWidgets('changes the moment the name does, even with the menu open', (tester) async {
      await openMenu(tester, name: shopName);
      await shopName.rename('নতুন দোকান');
      await _settle(tester);
      expect(inMenu('নতুন দোকান'), findsOneWidget);
      expect(inMenu(Bn.appTitle), findsNothing);
    });

    testWidgets('a very long name keeps to two lines and does not break the menu', (tester) async {
      repo.stored = 'অনেক লম্বা একটি দোকানের নাম ' * 2;
      await shopName.load();
      await openMenu(tester, name: shopName);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a name source it still shows the app\'s name', (tester) async {
      await openMenu(tester);
      expect(inMenu(Bn.appTitle), findsOneWidget);
    });
  });

  group('selling at what it cost (no profit)', () {
    const nails = Product(
      id: 1,
      name: 'পেরেক',
      purchasePrice: 80,
      sellingPrice: 100,
      stock: 10,
      unit: 'কেজি',
    );

    Future<SellInput?> Function() open(WidgetTester tester, Product product) {
      SellInput? result;
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> pump() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showSellSheet(context, product: product, locationName: (_) => 'তাক'),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await _settle(tester);
      }

      return () async {
        await pump();
        return result;
      };
    }

    Finder price() => find.widgetWithText(TextField, Bn.unitPrice);
    Finder costChip() => find.widgetWithText(ChoiceChip, '${Bn.sellAtCost} ৳৮০');
    Finder priceChip() => find.widgetWithText(ChoiceChip, '${Bn.sellAtPrice} ৳১০০');

    testWidgets('offers both: the usual price, and the price it cost', (tester) async {
      await open(tester, nails)();
      expect(priceChip(), findsOneWidget);
      expect(costChip(), findsOneWidget);
      expect(tester.widget<ChoiceChip>(priceChip()).selected, isTrue, reason: 'the usual price is the starting point');
      expect(find.text('${Bn.profit}: ৳২০'), findsOneWidget);
    });

    testWidgets('one tap sells at the buying price: no profit, said plainly', (tester) async {
      await open(tester, nails)();
      await tester.tap(costChip());
      await _settle(tester);
      expect(tester.widget<TextField>(price()).controller!.text, '৮০');
      expect(find.text(Bn.noProfit), findsOneWidget);
      expect(find.textContaining(Bn.loss), findsNothing);
      expect(tester.widget<ChoiceChip>(costChip()).selected, isTrue);
    });

    testWidgets('and the cart gets exactly the buying price', (tester) async {
      SellInput? got;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => got = await showSellSheet(context, product: nails, locationName: (_) => 'তাক'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.tap(find.text('open'));
      await _settle(tester);
      await tester.tap(costChip());
      await _settle(tester);
      await tester.tap(find.text(Bn.addToCart));
      await _settle(tester);
      expect(got?.unitPrice, 80);
      expect(got?.quantity, 1);
    });

    testWidgets('switching back to the usual price brings the profit back', (tester) async {
      await open(tester, nails)();
      await tester.tap(costChip());
      await _settle(tester);
      await tester.tap(priceChip());
      await _settle(tester);
      expect(tester.widget<TextField>(price()).controller!.text, '১০০');
      expect(find.text('${Bn.profit}: ৳২০'), findsOneWidget);
    });

    testWidgets('a typed price that happens to equal the cost is also "no profit", for any quantity', (tester) async {
      await open(tester, nails)();
      await tester.enterText(price(), '80');
      await tester.enterText(find.widgetWithText(TextField, '${Bn.quantity} (কেজি)'), '3');
      await _settle(tester);
      expect(find.text(Bn.noProfit), findsOneWidget);
      expect(find.text('${Bn.saleTotal}: ৳২৪০'), findsOneWidget);
    });

    testWidgets('below the cost is still shown as a loss (not mistaken for no profit)', (tester) async {
      await open(tester, nails)();
      await tester.enterText(price(), '70');
      await _settle(tester);
      expect(find.text('${Bn.loss}: ৳১০'), findsOneWidget);
      expect(find.text(Bn.noProfit), findsNothing);
    });

    testWidgets('the shortcut is not offered when the buying price is unknown (it would sell for nothing) or the same already', (tester) async {
      await open(tester, nails.copyWith(purchasePrice: 0))();
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('nor when both prices are the same', (tester) async {
      await open(tester, nails.copyWith(purchasePrice: 100))();
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.enterText(price(), '100');
      await _settle(tester);
      expect(find.text(Bn.noProfit), findsOneWidget, reason: 'still said plainly');
    });
  });

  group('a sale at cost (real database)', () {
    const dbFile = 'sale_at_cost_test.db';
    late AppDatabase db;
    late SqliteProductRepository products;
    late SqliteSalesRepository sales;
    final clock = FakeClock(DateTime(2026, 11, 22, 10));

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      db = AppDatabase(fileName: dbFile);
      products = SqliteProductRepository(db, clock);
      sales = SqliteSalesRepository(db, clock);
    });

    tearDown(() async => (await db.db).close());

    test('selling at exactly the buying price is allowed: the bill has no profit and nothing is wrong', () async {
      final nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 10, unit: 'কেজি'));
      final bill = await sales.checkout(
        [SaleLine(productId: nails.id!, quantity: 3, unitPrice: 80)],
        customer: const CustomerInfo(whatsapp: '01911111111'),
      );
      expect((bill.total, bill.cost, bill.profit, bill.due), (240, 240, 0, 0));
      expect((await products.byId(nails.id!))!.stock, 7);
      expect((await sales.billById(bill.id!))!.profit, 0);
    });

    test('the books agree: that day shows the sale with no profit, and mixed with a normal sale only the normal one earns', () async {
      final nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 10, unit: 'কেজি'));
      const customer = CustomerInfo(whatsapp: '01911111111');
      await sales.checkout([SaleLine(productId: nails.id!, quantity: 2, unitPrice: 80)], customer: customer);
      var summary = await SqliteDashboardRepository(db).summary(DateTime(2026, 11, 22), DateTime(2026, 11, 23));
      expect((summary.revenue, summary.cost, summary.profit), (160, 160, 0));

      await sales.checkout([SaleLine(productId: nails.id!, quantity: 1, unitPrice: 100)], customer: customer);
      summary = await SqliteDashboardRepository(db).summary(DateTime(2026, 11, 22), DateTime(2026, 11, 23));
      expect((summary.revenue, summary.cost, summary.profit), (260, 240, 20));
    });

    test('the buying price and the selling price may be saved as the same number', () async {
      final saved = await products.save(const Product(
          name: 'বোল্ট', purchasePrice: 50, sellingPrice: 50, stock: 5, unit: 'পিস'));
      final read = (await products.byId(saved.id!))!;
      expect((read.purchasePrice, read.sellingPrice, read.profitPerUnit), (50, 50, 0));
    });
  });
}
