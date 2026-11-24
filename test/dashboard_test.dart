import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_dashboard_repository.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/domain/dashboard.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/dashboard_page.dart';
import 'package:hardware_shop/presentation/dashboard_viewmodel.dart';
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

class _Codes implements LocationCodeGenerator {
  int _n = 0;
  @override
  String generate() => 'D-${_n++}';
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
const walkIn = CustomerInfo(address: 'বাজার রোড', whatsapp: '01911111111');

/// A repository that returns canned figures and records what it was asked.
class _FakeDashboard implements DashboardRepository {
  final calls = <String>[];
  DaySummary current = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  DaySummary before = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  Receivables owed = Receivables.none;
  InventoryHealth stock = InventoryHealth.empty;
  List<ProductSales> top = const [];

  @override
  Future<DaySummary> summary(DateTime from, DateTime to) async {
    calls.add('summary $from $to');
    // The first request is the period itself, the second the one before it.
    return calls.where((c) => c.startsWith('summary')).length.isOdd ? current : before;
  }

  @override
  Future<List<DailyTotal>> dailyTotals(DateTime from, int days) async {
    calls.add('daily $days');
    return [
      for (var i = 0; i < days; i++)
        DailyTotal(day: DateTime(from.year, from.month, from.day + i), revenue: i * 10.0, profit: 0, bills: 0),
    ];
  }

  @override
  Future<List<ProductSales>> topProducts(DateTime from, DateTime to, {int limit = 5}) async => top;

  @override
  Future<Receivables> receivables({int limit = 5}) async => owed;

  @override
  Future<InventoryHealth> inventoryHealth({int listLimit = 5}) async => stock;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQL figures', () {
    const dbFile = 'dashboard_test.db';
    late AppDatabase appDb;
    late _Clock clock;
    late SqliteProductRepository products;
    late SqliteSalesRepository sales;
    late SqliteLocationRepository locations;
    late SqliteDashboardRepository dashboard;
    late Product nails;
    late Product wire;

    final today = DateTime(2026, 11, 22, 10);
    final start = DateTime(2026, 11, 22);
    final end = DateTime(2026, 11, 23);

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      clock = _Clock(today);
      appDb = AppDatabase(fileName: dbFile);
      products = SqliteProductRepository(appDb, clock);
      sales = SqliteSalesRepository(appDb, clock);
      locations = SqliteLocationRepository(appDb, _Codes());
      dashboard = SqliteDashboardRepository(appDb);
      nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 50, unit: 'কেজি'));
      wire = await products.save(const Product(
          name: 'জিআই তার', kind: ProductKind.loose, purchasePrice: 100, sellingPrice: 150, stock: 50, unit: 'কেজি'));
    });

    tearDown(() async => (await appDb.db).close());

    Future<Bill> sell(Product product, double qty, double price, {CustomerInfo? customer, double? paid, DateTime? at}) {
      clock.current = at ?? today;
      return sales.checkout(
        [SaleLine(productId: product.id!, quantity: qty, unitPrice: price)],
        customer: customer ?? walkIn,
        paid: paid,
      );
    }

    /// Today: nails 2@100 (paid), wire 3@150 (Rahim paid 100 of 450).
    /// Yesterday: nails 1@100. Ten days ago: nails 5@100, Rahim paid nothing.
    Future<Bill> seed() async {
      await sell(nails, 2, 100);
      await sell(wire, 3, 150, customer: rahim, paid: 100);
      await sell(nails, 1, 100, at: DateTime(2026, 11, 21, 9));
      final old = await sell(nails, 5, 100, customer: rahim, paid: 0, at: DateTime(2026, 11, 12, 9));
      clock.current = today;
      return old;
    }

    test('an empty shop gives zeros everywhere, not errors', () async {
      final s = await dashboard.summary(start, end);
      expect(s.saleCount, 0);
      expect(s.revenue, 0);
      expect(s.cost, 0);
      expect(s.due, 0);
      expect(await dashboard.topProducts(start, end), isEmpty);
      final r = await dashboard.receivables();
      expect(r.totalDue, 0);
      expect(r.customerCount, 0);
      expect(r.top, isEmpty);
      final days = await dashboard.dailyTotals(start, 3);
      expect(days.map((d) => d.revenue), [0, 0, 0]);
    });

    test('summary adds up revenue, cost and due of the bills in the range only', () async {
      await seed();
      final s = await dashboard.summary(start, end);
      expect(s.saleCount, 2);
      expect(s.revenue, 200 + 450);
      expect(s.cost, 160 + 300);
      expect(s.profit, 190);
      expect(s.due, 350);

      final wholeMonth = await dashboard.summary(DateTime(2026, 11, 1), end);
      expect(wholeMonth.saleCount, 4);
      expect(wholeMonth.revenue, 650 + 100 + 500);
    });

    test('the range is half-open: a sale exactly at the end belongs to the next day', () async {
      await sell(nails, 1, 100, at: DateTime(2026, 11, 23));
      expect((await dashboard.summary(start, end)).saleCount, 0);
      expect((await dashboard.summary(end, DateTime(2026, 11, 24))).saleCount, 1);
    });

    test('daily totals: one entry per day, oldest first, empty days are zero', () async {
      await seed();
      final days = await dashboard.dailyTotals(DateTime(2026, 11, 16), 7);
      expect(days, hasLength(7));
      expect(days.first.day, DateTime(2026, 11, 16));
      expect(days.last.day, DateTime(2026, 11, 22));
      expect(days.map((d) => d.revenue), [0, 0, 0, 0, 0, 100, 650]);
      expect(days.last.bills, 2);
      expect(days.last.profit, 190);
      expect(days[5].bills, 1);
    });

    test('top products: ranked by revenue, with quantity and profit, limited', () async {
      await seed();
      final week = await dashboard.topProducts(DateTime(2026, 11, 16), end);
      expect(week.map((e) => e.name), ['জিআই তার', 'পেরেক']);
      expect(week.first.quantity, 3);
      expect(week.first.revenue, 450);
      expect(week.first.profit, 150);
      expect(week.last.quantity, 3);
      expect(week.last.revenue, 300);

      final month = await dashboard.topProducts(DateTime(2026, 11, 1), end);
      expect(month.first.name, 'পেরেক', reason: 'with the older sale, nails overtake wire');

      expect(await dashboard.topProducts(DateTime(2026, 11, 1), end, limit: 1), hasLength(1));
    });

    test('receivables: one entry per customer across all days, biggest first', () async {
      await seed();
      await sell(nails, 1, 100, customer: karim, paid: 80);
      final r = await dashboard.receivables();
      expect(r.customerCount, 2);
      expect(r.totalDue, 350 + 500 + 20);
      expect(r.top.map((d) => d.name), ['রহিম', 'করিম']);
      expect(r.top.first.due, 850, reason: "Rahim's two unpaid bills are one debt");
      expect(r.top.first.whatsapp, '01712345678');

      final one = await dashboard.receivables(limit: 1);
      expect(one.top, hasLength(1));
      expect(one.customerCount, 2, reason: 'the count is of everyone, not only those listed');
    });

    test('paid-up bills are not receivables', () async {
      await sell(nails, 2, 100);
      expect((await dashboard.receivables()).customerCount, 0);
    });

    test('a cancelled bill disappears from every figure', () async {
      final old = await seed();
      await sales.voidBill(old.id!);
      final r = await dashboard.receivables();
      expect(r.totalDue, 350);
      final month = await dashboard.summary(DateTime(2026, 11, 1), end);
      expect(month.saleCount, 3);
    });

    test('inventory health counts value, empty shelves, missing prices and unplaced stock', () async {
      final shelf = await locations.add('তাক ক', LocationType.shelf);
      // The fixture's own products are replaced by a controlled set.
      await products.delete(nails.id!);
      await products.delete(wire.id!);
      await products.save(Product(
        name: 'বোল্ট',
        kind: ProductKind.standard,
        purchasePrice: 50,
        sellingPrice: 70,
        stock: 10,
        unit: 'পিস',
        placements: [StockPlacement(locationId: shelf.id!, quantity: 10)],
      ));
      await products.save(const Product(
          name: 'কল', kind: ProductKind.standard, purchasePrice: 0, sellingPrice: 0, stock: 0, unit: 'পিস'));
      await products.save(const Product(
          name: 'তালা', kind: ProductKind.standard, purchasePrice: 10, sellingPrice: 15, stock: 4, unit: 'পিস'));

      final h = await dashboard.inventoryHealth();
      expect(h.productCount, 3);
      expect(h.stockValueAtCost, 540);
      expect(h.stockValueAtPrice, 760);
      expect(h.potentialProfit, 220);
      expect(h.outOfStockCount, 1);
      expect(h.outOfStock, ['কল']);
      expect(h.missingPriceCount, 1);
      expect(h.unplacedCount, 1, reason: 'only the lock has stock that is on no shelf; the empty tap has none to place');
    });
  });

  group('view model', () {
    late _FakeDashboard repo;
    late DashboardViewModel vm;

    setUp(() {
      repo = _FakeDashboard();
      vm = DashboardViewModel(repo, FakeClock(DateTime(2026, 11, 22, 15)));
    });

    test('starts on today, and week and month cover 7 and 30 days ending today', () async {
      expect(vm.period, DashboardPeriod.today);
      expect(vm.periodStart, DateTime(2026, 11, 22));
      await vm.choose(DashboardPeriod.week);
      expect(vm.periodStart, DateTime(2026, 11, 16));
      await vm.choose(DashboardPeriod.month);
      expect(vm.periodStart, DateTime(2026, 10, 24));
    });

    test('loading fills every section', () async {
      repo.current = const DaySummary(saleCount: 4, revenue: 1000, cost: 700, due: 50);
      repo.owed = const Receivables(totalDue: 50, customerCount: 1, top: [Debtor(name: 'রহিম', due: 50)]);
      await vm.load();
      expect(vm.loading, isFalse);
      expect(vm.summary.revenue, 1000);
      expect(vm.summary.profit, 300);
      expect(vm.averageBill, 250);
      expect(vm.receivables.customerCount, 1);
    });

    test('today still draws a week of bars; a month draws thirty', () async {
      await vm.load();
      expect(vm.trend, hasLength(7));
      expect(vm.trend.last.day, DateTime(2026, 11, 22));
      await vm.choose(DashboardPeriod.month);
      expect(vm.trend, hasLength(30));
    });

    test('sales change compares with the previous period, and is null with nothing to compare', () async {
      repo.current = const DaySummary(saleCount: 1, revenue: 150, cost: 0);
      repo.before = const DaySummary(saleCount: 1, revenue: 100, cost: 0);
      await vm.load();
      expect(vm.salesChange, closeTo(0.5, 1e-9));

      repo.before = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
      repo.calls.clear();
      await vm.load();
      expect(vm.salesChange, isNull);
    });

    test('average bill is zero with no bills', () async {
      await vm.load();
      expect(vm.averageBill, 0);
    });

    test('choosing the same period again does not reload', () async {
      await vm.load();
      repo.calls.clear();
      await vm.choose(DashboardPeriod.today);
      expect(repo.calls, isEmpty);
    });
  });

  group('components', () {
    testWidgets('BarChart gives the biggest bar full height and stays safe with all zeros', (tester) async {
      Future<void> show(List<BarItem> items) => tester.pumpWidget(
            MaterialApp(home: Scaffold(body: BarChart(items: items, height: 120))),
          );

      await show(const [BarItem('১', 50), BarItem('২', 100)]);
      final small = tester.getSize(find.byKey(const ValueKey('bar-0'))).height;
      final big = tester.getSize(find.byKey(const ValueKey('bar-1'))).height;
      expect(big, 82); // 120 - label - value text
      expect(small, closeTo(41, 0.01));

      await show(const [BarItem('১', 0), BarItem('২', 0)]);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const ValueKey('bar-1'))).height, 2);
    });

    testWidgets('BarChart shows the label of the last bar only', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BarChart(items: const [BarItem('১', 1), BarItem('২', 2)], valueLabel: (v) => 'V${v.toInt()}'),
        ),
      ));
      expect(find.text('V2'), findsOneWidget);
      expect(find.text('V1'), findsNothing);
    });
  });

  group('page', () {
    late _FakeDashboard repo;
    late DashboardViewModel vm;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      vm = DashboardViewModel(repo, FakeClock(DateTime(2026, 11, 22, 15)));
      await tester.pumpWidget(MaterialApp(home: DashboardPage(viewModel: vm)));
      await tester.pumpAndSettle();
    }

    setUp(() => repo = _FakeDashboard());

    testWidgets('the page is headed with the same word as its menu entry', (tester) async {
      await open(tester);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('ড্যাশবোর্ড')), findsOneWidget);
      expect(find.text('আমার ব্যবসা'), findsNothing);
    });

    testWidgets('a quiet shop shows empty messages rather than blanks', (tester) async {
      await open(tester);
      expect(find.text(Bn.dashNoSales), findsOneWidget);
      expect(find.text(Bn.dashNoDue), findsOneWidget);
      expect(find.text(Bn.dashAllInStock), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows sales, profit, best sellers, debtors and stock problems', (tester) async {
      repo.current = const DaySummary(saleCount: 4, revenue: 900, cost: 600, due: 100);
      repo.before = const DaySummary(saleCount: 2, revenue: 600, cost: 0);
      repo.top = const [ProductSales(name: 'জিআই তার', unit: 'কেজি', quantity: 4, revenue: 600, profit: 100)];
      repo.owed = const Receivables(
        totalDue: 100,
        customerCount: 1,
        top: [Debtor(name: 'রহিম', mobile: '01712345678', due: 100)],
      );
      repo.stock = const InventoryHealth(
        productCount: 12,
        stockValueAtCost: 5000,
        stockValueAtPrice: 6500,
        outOfStockCount: 2,
        outOfStock: ['কল', 'তালা'],
        missingPriceCount: 1,
        unplacedCount: 0,
      );
      await open(tester);

      expect(find.text('৳৯০০'), findsOneWidget, reason: 'sales');
      expect(find.text('৳৩০০'), findsOneWidget, reason: 'profit');
      expect(find.text('▲ ৫০% বেশি'), findsOneWidget);
      expect(find.textContaining('জিআই তার'), findsOneWidget);
      expect(find.text('রহিম'), findsOneWidget);
      expect(find.text('৳৫০০০'), findsOneWidget);
      expect(find.text('• কল'), findsOneWidget);
      expect(find.text('• তালা'), findsOneWidget);
      expect(find.text(Bn.dashAllInStock), findsNothing);
    });

    testWidgets('a fall in sales is shown as a fall', (tester) async {
      repo.current = const DaySummary(saleCount: 1, revenue: 50, cost: 0);
      repo.before = const DaySummary(saleCount: 1, revenue: 100, cost: 0);
      await open(tester);
      expect(find.text('▼ ৫০% কম'), findsOneWidget);
    });

    testWidgets('picking a period reloads with that period', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.periodMonth));
      await tester.pumpAndSettle();
      expect(vm.period, DashboardPeriod.month);
      expect(repo.calls, contains('daily 30'));
    });
  });
}
