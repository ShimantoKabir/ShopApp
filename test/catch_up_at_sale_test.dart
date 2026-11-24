import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/presentation/cart_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/sell_page.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// A shop connection that records being asked, and can change the stock the
/// way another phone's sale would, or hang like a bad signal.
class _Shop implements SyncService {
  int syncs = 0;
  Completer<void>? hang;
  void Function()? otherPhoneSells;

  @override
  bool enabled = true;

  @override
  Future<void> syncNow() async {
    syncs++;
    if (hang != null) return hang!.future;
    otherPhoneSells?.call();
  }

  @override
  SyncState get state => SyncState.idle;
  @override
  String? get detail => null;
  @override
  DateTime? get lastSynced => null;
  @override
  String get defaultUrl => '';
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<void> connect({required String url, required String key}) async {}
  @override
  Future<void> join() async {}
  @override
  Future<void> shareThisPhone() async {}
  @override
  Future<void> disconnect() async {}
}

class _Screens implements ScreenFactory {
  @override
  Widget checkout(SellViewModel cart) => const Scaffold(body: Text('CHECKOUT'));
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  Product nails(double stock) => Product(
        id: 1,
        name: 'পেরেক',
        kind: ProductKind.loose,
        purchasePrice: 80,
        sellingPrice: 100,
        stock: stock,
        unit: 'কেজি',
        placements: [StockPlacement(locationId: 5, quantity: stock)],
      );

  late FakeProductRepository products;
  late _Shop shop;
  late SellViewModel vm;

  void otherPhoneLeaves(double stock) {
    shop.otherPhoneSells = () => products.items[0] = nails(stock);
  }

  setUp(() async {
    products = FakeProductRepository([nails(10)]);
    shop = _Shop();
    vm = SellViewModel(
      products,
      FakeSalesRepository(products, FakeClock(DateTime(2026, 11, 22, 15, 30))),
      FakeLocationRepository(),
      FakeCustomerRepository(),
      sync: shop,
    );
    await vm.load();
  });

  group('catching up at a sale moment', () {
    test('asks the shop, shows the fresh stock, and says nothing when nothing changed', () async {
      vm.addToCart(vm.products.first, quantity: 2);
      expect(await vm.refreshFromShop(), isEmpty);
      expect(shop.syncs, 1);
      expect(vm.cart.single.quantity, 2);
    });

    test('another phone sold some: the cart is cut down to what is left, and it says which item', () async {
      vm.addToCart(vm.products.first, quantity: 6);
      otherPhoneLeaves(4);
      final shortages = await vm.refreshFromShop();
      expect(shortages, [(name: 'পেরেক', left: 4.0)]);
      expect(vm.cart.single.quantity, 4);
      expect(vm.products.first.stock, 4, reason: 'the list shows the fresh stock too');
    });

    test('another phone sold it all: the item leaves the cart', () async {
      vm.addToCart(vm.products.first, quantity: 3);
      otherPhoneLeaves(0);
      final shortages = await vm.refreshFromShop();
      expect(shortages.single.left, 0);
      expect(vm.cartCount, 0);
    });

    test('two lines of the same item share what is left', () async {
      final nail = vm.products.first;
      vm.addToCart(nail, quantity: 3, unitPrice: 100);
      vm.addToCart(nail, quantity: 3, unitPrice: 90);
      otherPhoneLeaves(4);
      await vm.refreshFromShop();
      expect(vm.cart.fold(0.0, (sum, l) => sum + l.quantity), 4);
    });

    test('an item deleted on another phone is taken out', () async {
      vm.addToCart(vm.products.first, quantity: 1);
      shop.otherPhoneSells = () => products.items.clear();
      final shortages = await vm.refreshFromShop();
      expect(shortages.single.left, 0);
      expect(vm.cartCount, 0);
    });

    test('a shop that is not shared is not asked, but the stock is still checked locally', () async {
      shop.enabled = false;
      vm.addToCart(vm.products.first, quantity: 2);
      expect(await vm.refreshFromShop(), isEmpty);
      expect(shop.syncs, 0);
    });

    test('a bad signal never freezes selling: after a few seconds it carries on with what it has', () async {
      shop.hang = Completer<void>(); // the shop never answers
      vm.addToCart(vm.products.first, quantity: 2);
      final stopwatch = Stopwatch()..start();
      final result = await vm.refreshFromShop();
      expect(result, isEmpty);
      expect(stopwatch.elapsed, lessThan(SellViewModel.catchUpTimeout + const Duration(seconds: 2)));
      expect(vm.cart.single.quantity, 2);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('the screens ask at the right moments', () {
    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('opening the selling screen catches up, and a short cart is reported', (tester) async {
      bigScreen(tester);
      vm.addToCart(vm.products.first, quantity: 6);
      otherPhoneLeaves(4);
      await tester.pumpWidget(MaterialApp(home: SellPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      expect(shop.syncs, 1);
      expect(find.text(Bn.stockChangedElsewhere('পেরেক', 4)), findsOneWidget);
    });

    testWidgets('picking a product catches up first, so the popup shows the fresh stock', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: SellPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      shop.syncs = 0;
      otherPhoneLeaves(3);
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      expect(shop.syncs, 1);
      expect(find.textContaining('মজুদ আছে: ৩ কেজি'), findsWidgets);
    });

    testWidgets('the quick "+ 1" asks too, and refuses what is no longer there', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: SellPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      shop.syncs = 0;
      otherPhoneLeaves(0);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      expect(shop.syncs, 1);
      expect(vm.cartCount, 0, reason: 'nothing left to add');
    });

    testWidgets('opening the cart catches up', (tester) async {
      bigScreen(tester);
      vm.addToCart(vm.products.first, quantity: 6);
      otherPhoneLeaves(2);
      await tester.pumpWidget(MaterialApp(home: CartPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      expect(shop.syncs, 1);
      expect(vm.cart.single.quantity, 2);
      expect(find.text(Bn.stockChangedElsewhere('পেরেক', 2)), findsOneWidget);
    });
  });

  group('no timer asking the server', () {
    test('the app no longer starts the every-20-seconds check', () {
      expect(File('lib/main.dart').readAsStringSync(), isNot(contains('startAutoSync')));
    });
  });
}
