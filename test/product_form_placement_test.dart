import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/presentation/product_form_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// Drives the product form the way staff do: open a saved product, use the
/// placement menu, answer the dialog, and check what the app asked the stock
/// repository to do and what the screen shows afterwards.

class _Screens implements ScreenFactory {
  @override
  Widget home() => const SizedBox();
  @override
  Widget sell() => const SizedBox();
  @override
  Widget shell({required VoidCallback onSignOut}) => const SizedBox();
  @override
  Widget users() => const SizedBox();
  @override
  Widget activity() => const SizedBox();
  @override
  Widget syncSettings() => const SizedBox();
  @override
  Widget joinShop() => const SizedBox();
  @override
  Widget profile() => const SizedBox();
  @override
  Widget settings() => const SizedBox();
  @override
  Widget dashboard() => const SizedBox();
  @override
  Widget customers() => const SizedBox();
  @override
  Widget customerDetail(int customerId) => const SizedBox();
  @override
  Widget dailySales() => const SizedBox();
  @override
  Widget productList({StorageLocation? location}) => const SizedBox();
  @override
  Widget productForm({Product? product, int? initialLocationId}) => const SizedBox();
  @override
  Widget categories() => const SizedBox();
  @override
  Widget locations() => const SizedBox();
  @override
  Widget locationTypes() => const SizedBox();
  @override
  Widget cart(SellViewModel cart) => const SizedBox();
  @override
  Widget locationQr(StorageLocation location) => const SizedBox();
  @override
  Widget scanner() => const SizedBox();
  @override
  Widget importProducts() => const SizedBox();
  @override
  Widget checkout(SellViewModel cart) => const SizedBox();
  @override
  Widget receipt(Bill bill) => const SizedBox();
}

/// Applies stock operations to the in-memory product store, so the page's
/// reload shows real changes. (The real rules are tested against SQL elsewhere.)
class _LinkedStock implements StockRepository {
  final FakeProductRepository products;
  final List<String> calls = [];
  StockException? failWith;
  _LinkedStock(this.products);

  int _index(int id) => products.items.indexWhere((p) => p.id == id);

  void _check(String call) {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  List<StockPlacement> _with(Product p, int locationId, double qty) => [
        for (final x in p.placements)
          if (x.locationId != locationId) x,
        if (qty > 0) StockPlacement(locationId: locationId, quantity: qty),
      ];

  @override
  Future<List<StockPlacement>> placements(int productId) async => products.items[_index(productId)].placements;

  @override
  Future<void> place(int productId, int locationId, double quantity) async {
    _check('place $productId $locationId $quantity');
    final i = _index(productId);
    products.items[i] = products.items[i].copyWith(placements: _with(products.items[i], locationId, quantity));
  }

  @override
  Future<void> recount(int productId, int locationId, double quantity) async {
    _check('recount $productId $locationId $quantity');
    final i = _index(productId);
    final p = products.items[i];
    final delta = quantity - p.quantityAt(locationId);
    products.items[i] = p.copyWith(stock: p.stock + delta, placements: _with(p, locationId, quantity));
  }

  @override
  Future<void> move(int productId, int from, int to, double quantity) async {
    _check('move $productId $from $to $quantity');
    final i = _index(productId);
    var p = products.items[i];
    p = p.copyWith(placements: _with(p, from, p.quantityAt(from) - quantity));
    p = p.copyWith(placements: _with(p, to, p.quantityAt(to) + quantity));
    products.items[i] = p;
  }

  @override
  Future<void> restock(int productId, double quantity, {int? locationId, double? purchasePrice}) async =>
      _check('restock $productId $quantity $locationId $purchasePrice');

  @override
  Future<List<StockLogEntry>> history(int productId, {int limit = 30}) async => [
        StockLogEntry(productId: productId, locationId: 5, delta: 4, reason: StockReason.move, at: DateTime(2026, 11, 22, 15, 52)),
        StockLogEntry(productId: productId, delta: 10, reason: StockReason.initial, at: DateTime(2026, 11, 22, 15, 30)),
      ];
}

class _Locations extends FakeLocationRepository {
  final List<String> added = [];
  final List<StorageLocation> _made = [];

  @override
  Future<StorageLocation> add(String name, LocationType type) async {
    added.add(name);
    final made = StorageLocation(id: 50 + added.length, name: name, type: type, code: 'N');
    _made.add(made);
    return made;
  }

  @override
  Future<List<StorageLocation>> all() async => [..._made, ..._fixed];

  static const _fixed = [
        StorageLocation(id: 5, name: 'তাক ১', code: 'A'),
        StorageLocation(id: 6, name: 'গুদাম', type: LocationType.storeroom, code: 'B'),
      ];
}

void main() {
  late FakeProductRepository products;
  late _LinkedStock stock;

  // 10 nails: 6 on shelf 1, none anywhere else, so 4 are "not yet placed".
  const nails = Product(
    id: 1,
    name: 'পেরেক',
    kind: ProductKind.loose,
    purchasePrice: 80,
    sellingPrice: 100,
    stock: 10,
    unit: 'কেজি',
    placements: [StockPlacement(locationId: 5, quantity: 6)],
  );

  setUp(() {
    products = FakeProductRepository([nails]);
    stock = _LinkedStock(products);
  });

  Future<void> openForm(WidgetTester tester, {Product? product, int? initialLocationId}) async {
    tester.view.physicalSize = const Size(900, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = ProductFormViewModel(products, FakeCategoryRepository(), _Locations(), stock);
    await tester.pumpWidget(MaterialApp(
      home: ProductFormPage(viewModel: vm, screens: _Screens(), product: product, initialLocationId: initialLocationId),
    ));
    await tester.pumpAndSettle();
  }

  Finder dialogButton(String label) => find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  group('making a location without leaving the form', () {
    testWidgets('a new product has a "new location" button beside the location list, and the new location is picked', (tester) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Locations();
      final vm = ProductFormViewModel(products, FakeCategoryRepository(), repo, stock);
      await tester.pumpWidget(MaterialApp(home: ProductFormPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('নতুন স্থান'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'বাম দেয়াল');
      await tester.tap(dialogButton('যোগ করুন'));
      await tester.pumpAndSettle();
      expect(repo.added, ['বাম দেয়াল']);
      expect(find.textContaining('বাম দেয়াল'), findsWidgets, reason: 'it is now the chosen location');
    });
  });

  group('existing product', () {
    testWidgets('shows where the stock is kept and what is not placed yet', (tester) async {
      await openForm(tester, product: nails);
      expect(find.text('স্থান ও মজুদ বণ্টন'), findsOneWidget);
      expect(find.text('তাক ১'), findsWidgets);
      expect(find.text('৬ কেজি'), findsOneWidget);
      expect(find.text('স্থান ঠিক হয়নি: ৪ কেজি'), findsOneWidget);
      expect(find.text('স্থান যোগ করুন'), findsOneWidget, reason: 'the add button');
    });

    testWidgets('has no single-location dropdown (placements replace it)', (tester) async {
      await openForm(tester, product: nails);
      expect(find.text('স্থান নেই'), findsNothing);
    });

    testWidgets('RECOUNT: menu -> dialog -> confirm calls recount, updates the row and the total, no crash', (tester) async {
      await openForm(tester, product: nails);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('গণনা করে ঠিক করুন'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '9');
      await tester.tap(dialogButton('সংরক্ষণ'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stock.calls, ['recount 1 5 9.0']);
      expect(find.text('৯ কেজি'), findsOneWidget, reason: 'the row shows the counted quantity');
      expect(find.widgetWithText(TextFormField, '১৩'), findsOneWidget, reason: 'total 10 + 3 more found = 13');
    });

    testWidgets('MOVE: menu -> pick target + quantity -> confirm calls move and updates both rows', (tester) async {
      await openForm(tester, product: nails);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('অন্য স্থানে সরান'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '2');
      await tester.tap(dialogButton('সংরক্ষণ'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stock.calls, ['move 1 5 6 2.0'], reason: 'the only other location is the storeroom');
      expect(find.text('৪ কেজি'), findsWidgets);
      expect(find.text('২ কেজি'), findsOneWidget);
    });

    testWidgets('REMOVE: menu -> confirm sets the quantity at that location to zero', (tester) async {
      await openForm(tester, product: nails);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('এই স্থান থেকে সরান'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('এই স্থান থেকে সরান'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stock.calls, ['place 1 5 0.0']);
      expect(find.text('৬ কেজি'), findsNothing);
      expect(find.text('স্থান ঠিক হয়নি: ১০ কেজি'), findsOneWidget, reason: 'everything is unplaced again');
    });

    testWidgets('ADD: place part of the unplaced stock at a location', (tester) async {
      await openForm(tester, product: nails);
      await tester.tap(find.text('স্থান যোগ করুন'));
      await tester.pumpAndSettle();
      // The number is pre-filled with the 4 that are not placed yet.
      expect(find.widgetWithText(TextField, '৪'), findsOneWidget);
      await tester.tap(dialogButton('সংরক্ষণ'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stock.calls, ['place 1 5 4.0'], reason: 'defaults to the first location');
    });

    testWidgets('a broken stock rule shows a Bangla message and changes nothing', (tester) async {
      stock.failWith = const StockException(StockProblem.notEnoughAtSource);
      await openForm(tester, product: nails);
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('অন্য স্থানে সরান'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('সংরক্ষণ'));
      await tester.pumpAndSettle();

      expect(find.text('ওই স্থানে এত পরিমাণ নেই।'), findsOneWidget);
      expect(find.text('৬ কেজি'), findsOneWidget, reason: 'unchanged');
      expect(tester.takeException(), isNull);
    });

    testWidgets('HISTORY: the sheet lists changes, newest first, with reasons', (tester) async {
      await openForm(tester, product: nails);
      await tester.tap(find.byTooltip('ইতিহাস'));
      await tester.pumpAndSettle();
      expect(find.text('মজুদের ইতিহাস'), findsOneWidget);
      expect(find.textContaining('স্থান পরিবর্তন'), findsOneWidget);
      expect(find.text('নতুন পণ্য'), findsOneWidget);
      expect(find.text('+৪ কেজি'), findsOneWidget);
    });

    testWidgets('saving with a total below what is placed shows the rule message', (tester) async {
      // The real repository throws belowPlaced; here the fake products repo does the same.
      await openForm(tester, product: nails);
      await tester.enterText(find.widgetWithText(TextFormField, '১০'), '4');
      await tester.tap(find.text('সংরক্ষণ').last);
      await tester.pumpAndSettle();
      expect(find.text('মোট মজুদ বিভিন্ন স্থানে রাখা পরিমাণের চেয়ে কম হতে পারে না। আগে স্থান থেকে কমান।'), findsOneWidget);
    });
  });

  group('new product', () {
    testWidgets('keeps the quick single-location dropdown and shows no placement editor', (tester) async {
      await openForm(tester);
      expect(find.text('স্থান নেই'), findsOneWidget);
      expect(find.text('স্থান ও মজুদ বণ্টন'), findsNothing);
    });

    testWidgets('a chosen location receives the whole stock as one placement', (tester) async {
      await openForm(tester, initialLocationId: 6);
      await tester.enterText(find.widgetWithText(TextFormField, 'পণ্যের নাম'), 'তার');
      await tester.enterText(find.widgetWithText(TextFormField, 'কেনা দাম'), '50');
      await tester.enterText(find.widgetWithText(TextFormField, 'বিক্রি দাম'), '70');
      await tester.enterText(find.widgetWithText(TextFormField, 'মজুদ (পিস)'), '8');
      await tester.tap(find.text('সংরক্ষণ').last);
      await tester.pumpAndSettle();

      final saved = products.items.firstWhere((p) => p.name == 'তার');
      expect(saved.stock, 8);
      expect(saved.placements.single.locationId, 6);
      expect(saved.placements.single.quantity, 8);
    });

    testWidgets('no stock means nothing to place, even with a location chosen', (tester) async {
      await openForm(tester, initialLocationId: 6);
      await tester.enterText(find.widgetWithText(TextFormField, 'পণ্যের নাম'), 'তার');
      await tester.enterText(find.widgetWithText(TextFormField, 'কেনা দাম'), '50');
      await tester.enterText(find.widgetWithText(TextFormField, 'বিক্রি দাম'), '70');
      await tester.enterText(find.widgetWithText(TextFormField, 'মজুদ (পিস)'), '0');
      await tester.tap(find.text('সংরক্ষণ').last);
      await tester.pumpAndSettle();
      expect(products.items.firstWhere((p) => p.name == 'তার').placements, isEmpty);
    });
  });
}
