import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/domain/customers.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/customer_detail/customer_detail_page.dart';
import 'package:hardware_shop/presentation/customers/customers_viewmodel.dart';
import 'package:hardware_shop/presentation/customer_detail/customer_detail_viewmodel.dart';
import 'package:hardware_shop/presentation/customers/customers_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

class _Clock implements Clock {
  DateTime current;
  _Clock(this.current);
  @override
  DateTime now() => current;
}

const rahim = CustomerInfo(
  name: 'রহিম',
  mobile: '01712345678',
  nid: '1234567890',
  address: 'কাজিপুর',
  whatsapp: '01712345678',
);
const karim = CustomerInfo(
  name: 'করিম',
  mobile: '01811111111',
  nid: '1234567890123',
  address: 'বাজার',
  whatsapp: '01811111111',
);
const stranger = CustomerInfo(address: 'নদীর পাড়', whatsapp: '01911111111');

class _Screens implements ScreenFactory {
  final opened = <int>[];
  @override
  Widget customerDetail(int id) {
    opened.add(id);
    return Scaffold(body: Center(child: Text('DETAIL-$id')));
  }

  @override
  Widget receipt(Bill bill) => Scaffold(body: Center(child: Text('RECEIPT-${bill.id}')));

  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQL customer figures', () {
    const dbFile = 'customers_test.db';
    late AppDatabase appDb;
    late _Clock clock;
    late SqliteProductRepository products;
    late SqliteSalesRepository sales;
    late SqliteCustomerRepository customers;
    late Product nails;
    late Product wire;

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      clock = _Clock(DateTime(2026, 11, 22, 10));
      appDb = AppDatabase(fileName: dbFile);
      products = SqliteProductRepository(appDb, clock);
      sales = SqliteSalesRepository(appDb, clock);
      customers = SqliteCustomerRepository(appDb, clock);
      nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 100, unit: 'কেজি'));
      wire = await products.save(const Product(
          name: 'জিআই তার', kind: ProductKind.loose, purchasePrice: 100, sellingPrice: 150, stock: 100, unit: 'কেজি'));
    });

    tearDown(() async => (await appDb.db).close());

    Future<Bill> buy(CustomerInfo who, Product product, double qty, {double? paid, DateTime? at}) {
      clock.current = at ?? DateTime(2026, 11, 22, 10);
      return sales.checkout(
        [SaleLine(productId: product.id!, quantity: qty, unitPrice: product.sellingPrice)],
        customer: who,
        paid: paid,
      );
    }

    test('no customers yet: an empty list, and no customer for an unknown id', () async {
      expect(await customers.all(), isEmpty);
      expect(await customers.byId(99), isNull);
    });

    test('a repeat customer is one customer; totals add up across all their bills', () async {
      await buy(rahim, nails, 2, at: DateTime(2026, 11, 10)); // 200, paid in full
      await buy(rahim, wire, 3, paid: 100, at: DateTime(2026, 11, 20)); // 450, 350 due
      await buy(rahim, nails, 1, paid: 40, at: DateTime(2026, 11, 22)); // 100, 60 due
      final all = await customers.all();
      expect(all, hasLength(1));
      final c = all.single;
      expect(c.name, 'রহিম');
      expect(c.billCount, 3);
      expect(c.productCount, 2, reason: 'nails and wire; nails twice counts once');
      expect(c.totalSpent, 750);
      expect(c.totalPaid, 200 + 100 + 40);
      expect(c.due, 350 + 60);
      expect(c.lastPurchase, DateTime(2026, 11, 22));
      expect(c.address, 'কাজিপুর');
      expect(c.nid, '1234567890');
    });

    test('a bill paid more than its total never makes the due negative, and a paid-up bill owes nothing', () async {
      await buy(rahim, nails, 1);
      final c = (await customers.all()).single;
      expect(c.due, 0);
      expect(c.owes, isFalse);
    });

    test('customers are kept apart, most recent buyer first', () async {
      await buy(rahim, nails, 1, at: DateTime(2026, 11, 1));
      await buy(karim, wire, 1, paid: 0, at: DateTime(2026, 11, 20));
      final all = await customers.all();
      expect(all.map((c) => c.name), ['করিম', 'রহিম']);
      expect(all.first.due, 150);
      expect(all.last.due, 0);
    });

    test('a customer with no name shows their number', () async {
      await buy(stranger, nails, 1);
      final c = (await customers.all()).single;
      expect(c.name, '');
      expect(c.displayName, '01911111111');
    });

    test('byId gives the same figures as the list', () async {
      await buy(rahim, wire, 2, paid: 100);
      final fromList = (await customers.all()).single;
      final byId = (await customers.byId(fromList.id))!;
      expect(byId.totalSpent, fromList.totalSpent);
      expect(byId.due, 200);
    });

    test('cancelling a bill takes it out of the totals', () async {
      await buy(rahim, nails, 2);
      final bill = await buy(rahim, wire, 2, paid: 0);
      expect((await customers.all()).single.due, 300);
      await sales.voidBill(bill.id!);
      final c = (await customers.all()).single;
      expect(c.due, 0);
      expect(c.billCount, 1);
      expect(c.productCount, 1);
    });

    test("billsOfCustomer: only that customer's bills, newest first, with their lines", () async {
      await buy(rahim, nails, 1, at: DateTime(2026, 11, 1));
      await buy(karim, wire, 1, at: DateTime(2026, 11, 5));
      await buy(rahim, wire, 2, at: DateTime(2026, 11, 9));
      final rahimId = (await customers.all()).firstWhere((c) => c.name == 'রহিম').id;
      final bills = await sales.billsOfCustomer(rahimId);
      expect(bills, hasLength(2));
      expect(bills.first.at, DateTime(2026, 11, 9));
      expect(bills.first.lines.single.productName, 'জিআই তার');
      expect(bills.every((b) => b.customerId == rahimId), isTrue);
    });
  });

  group('list view model', () {
    late FakeCustomerRepository repo;
    late CustomerListViewModel vm;

    CustomerSummary c(int id, String name, {String whatsapp = '', String address = '', double due = 0}) =>
        CustomerSummary(id: id, name: name, whatsapp: whatsapp, mobile: whatsapp, address: address, due: due, billCount: 1);

    setUp(() async {
      repo = FakeCustomerRepository();
      repo.summaries.addAll([
        c(1, 'রহিম', whatsapp: '01712345678', address: 'কাজিপুর', due: 300),
        c(2, 'করিম', whatsapp: '01811111111', address: 'বাজার'),
        c(3, 'সালমা', whatsapp: '01911111111', address: 'নদীর পাড়', due: 900),
      ]);
      vm = CustomerListViewModel(repo);
      await vm.load();
    });

    test('lists everyone, and adds up the dues', () {
      expect(vm.customers, hasLength(3));
      expect(vm.totalCustomers, 3);
      expect(vm.totalDue, 1200);
    });

    test('search by name, by address, and by any part of a number in English or Bangla digits', () {
      vm.search('করিম');
      expect(vm.customers.map((e) => e.id), [2]);
      vm.search('নদীর');
      expect(vm.customers.map((e) => e.id), [3]);
      vm.search('0171234');
      expect(vm.customers.map((e) => e.id), [1]);
      vm.search('০১৯১১');
      expect(vm.customers.map((e) => e.id), [3]);
      vm.search('কেউ নেই');
      expect(vm.customers, isEmpty);
      vm.search('');
      expect(vm.customers, hasLength(3));
    });

    test('the "owes" filter keeps only debtors, biggest debt first, and combines with search', () {
      vm.setOnlyDue(true);
      expect(vm.customers.map((e) => e.id), [3, 1]);
      vm.search('রহিম');
      expect(vm.customers.map((e) => e.id), [1]);
    });
  });

  group('pages', () {
    late FakeCustomerRepository customers;
    late FakeSalesRepository sales;
    late _Screens screens;

    setUp(() {
      final clock = FakeClock(DateTime(2026, 11, 22, 12));
      customers = FakeCustomerRepository();
      sales = FakeSalesRepository(FakeProductRepository(), clock);
      screens = _Screens();
    });

    Future<void> bigScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('an empty list explains how customers appear', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: CustomersPage(viewModel: CustomerListViewModel(customers), screens: screens),
      ));
      await tester.pumpAndSettle();
      expect(find.text(Bn.noCustomers), findsOneWidget);
    });

    testWidgets('a customer with a number has call and share inside the card; one who owes shares the reminder', (tester) async {
      await bigScreen(tester);
      final contacts = FakeContactLauncher();
      customers.summaries.addAll(const [
        CustomerSummary(id: 1, name: 'রহিম', whatsapp: '01712345678', mobile: '01812345678', billCount: 3, totalSpent: 750, due: 410),
        CustomerSummary(id: 2, name: 'করিম', billCount: 1, totalSpent: 100), // gave no number
      ]);
      await tester.pumpWidget(MaterialApp(
        home: CustomersPage(viewModel: CustomerListViewModel(customers), screens: screens, contacts: contacts, shopName: 'হাসান স্টোর'),
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('ফোন করুন'), findsOneWidget, reason: 'only Rahim has a number');
      await tester.tap(find.byTooltip('ফোন করুন'));
      await tester.tap(find.byTooltip('শেয়ার করুন (যেকোনো অ্যাপে)'));
      await tester.pump();
      expect(contacts.calls, ['01812345678']);
      expect(contacts.shared.single, contains('৳৪১০'));
      final card = find.ancestor(of: find.text('রহিম'), matching: find.byType(Card)).first;
      expect(find.descendant(of: card, matching: find.byTooltip('ফোন করুন')), findsOneWidget, reason: 'inside the card');
    });

    testWidgets('a customer who owes nothing can be called; there is nothing to share', (tester) async {
      await bigScreen(tester);
      final contacts = FakeContactLauncher();
      customers.summaries.add(const CustomerSummary(id: 2, name: 'করিম', whatsapp: '01811111111', billCount: 1, totalSpent: 100));
      await tester.pumpWidget(MaterialApp(
        home: CustomersPage(viewModel: CustomerListViewModel(customers), screens: screens, contacts: contacts),
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('শেয়ার করুন (যেকোনো অ্যাপে)'), findsNothing);
      await tester.tap(find.byTooltip('ফোন করুন'));
      await tester.pump();
      expect(contacts.calls, ['01811111111']);
    });

    testWidgets('shows each customer with their purchases and due; tap opens the details', (tester) async {
      await bigScreen(tester);
      customers.summaries.addAll(const [
        CustomerSummary(id: 1, name: 'রহিম', whatsapp: '01712345678', billCount: 3, totalSpent: 750, due: 410),
        CustomerSummary(id: 2, name: 'করিম', whatsapp: '01811111111', billCount: 1, totalSpent: 100),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: CustomersPage(viewModel: CustomerListViewModel(customers), screens: screens),
      ));
      await tester.pumpAndSettle();

      expect(find.text('রহিম'), findsOneWidget);
      expect(find.text('৳৭৫০'), findsOneWidget);
      expect(find.text('বাকি: ৳৪১০'), findsOneWidget);
      expect(find.text('৩ বার'), findsOneWidget);
      expect(find.textContaining('বাকি: ৳১০০'), findsNothing, reason: 'Karim owes nothing');
      expect(find.text('২ জন গ্রাহক'), findsOneWidget);

      await tester.tap(find.text('রহিম'));
      await tester.pumpAndSettle();
      expect(screens.opened, [1]);
      expect(find.text('DETAIL-1'), findsOneWidget);
    });

    testWidgets('searching and the due filter narrow the list', (tester) async {
      await bigScreen(tester);
      customers.summaries.addAll(const [
        CustomerSummary(id: 1, name: 'রহিম', whatsapp: '01712345678', billCount: 1, totalSpent: 100, due: 50),
        CustomerSummary(id: 2, name: 'করিম', whatsapp: '01811111111', billCount: 1, totalSpent: 100),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: CustomersPage(viewModel: CustomerListViewModel(customers), screens: screens),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text(Bn.customerFilterDue));
      await tester.pumpAndSettle();
      expect(find.text('রহিম'), findsOneWidget);
      expect(find.text('করিম'), findsNothing);

      Finder inCard(String name) => find.descendant(of: find.byType(ItemCard), matching: find.text(name));
      await tester.tap(find.text(Bn.customerFilterAll));
      await tester.enterText(find.byType(TextField), 'করিম');
      await tester.pumpAndSettle();
      expect(inCard('করিম'), findsOneWidget);
      expect(inCard('রহিম'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(Bn.noCustomerMatch), findsOneWidget);
    });

    testWidgets('the detail page shows contact, totals and every bill; tapping a bill opens its receipt', (tester) async {
      await bigScreen(tester);
      customers.summaries.add(CustomerSummary(
        id: 1,
        name: 'রহিম',
        whatsapp: '01712345678',
        mobile: '01712345678',
        address: 'কাজিপুর, সিরাজগঞ্জ',
        nid: '1234567890',
        billCount: 2,
        productCount: 2,
        totalSpent: 750,
        totalPaid: 340,
        due: 410,
        lastPurchase: DateTime.now(), // "today" must stay today whenever the test runs
      ));
      sales.bills.add(Bill(
        id: 7,
        customerId: 1,
        customerName: 'রহিম',
        paid: 340,
        at: DateTime(2026, 11, 22, 9, 30),
        lines: [
          Sale(productName: 'পেরেক', unit: 'কেজি', quantity: 2, unitPrice: 200, unitCost: 0, at: DateTime(2026, 11, 22)),
        ],
      ));
      await tester.pumpWidget(MaterialApp(
        home: CustomerDetailPage(
          viewModel: CustomerDetailViewModel(customers, sales),
          customerId: 1,
          screens: screens,
          sender: FakeReceiptSender(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('কাজিপুর, সিরাজগঞ্জ'), findsOneWidget);
      expect(find.byTooltip('ফোন করুন'), findsNothing, reason: 'no launcher was given');
      expect(find.text('NID: 1234567890'), findsOneWidget);
      expect(find.text('৳৭৫০'), findsOneWidget, reason: 'total spent');
      expect(find.text('৳৪১০'), findsOneWidget, reason: 'due');
      expect(find.text('৳৩৪০'), findsOneWidget, reason: 'paid');
      expect(find.text('২ বার'), findsOneWidget);
      expect(find.text('আজ'), findsOneWidget, reason: 'last purchase');
      expect(find.text('২২/১১/২০২৬ ০৯:৩০'), findsOneWidget, reason: 'the bill, dated');

      await tester.tap(find.text('২২/১১/২০২৬ ০৯:৩০'));
      await tester.pumpAndSettle();
      expect(find.text('RECEIPT-7'), findsOneWidget);
    });

    testWidgets('a customer that no longer exists says so', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: CustomerDetailPage(
          viewModel: CustomerDetailViewModel(customers, sales),
          customerId: 42,
          screens: screens,
          sender: FakeReceiptSender(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(Bn.customerNotFound), findsOneWidget);
    });
  });
}
