import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/core/language.dart';
import 'package:hardware_shop/data/starter_categories.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/cart_page.dart';
import 'package:hardware_shop/presentation/home_shell.dart';
import 'package:hardware_shop/presentation/product_list_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/sell_page.dart';
import 'package:hardware_shop/presentation/shell_scope.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:hardware_shop/presentation/widgets/sell_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

class _Screens implements ScreenFactory {
  final SellViewModel cartVm;
  _Screens(this.cartVm);

  @override
  Widget cart(SellViewModel cart) => CartPage(viewModel: cart, screens: this);
  @override
  Widget checkout(SellViewModel cart) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              cart.clearCart(); // as if the sale was made
            },
            child: const Text('CHECKOUT-PAGE'),
          ),
        ),
      );
  @override
  Widget sell() => SellPage(viewModel: cartVm, screens: this);
  @override
  Widget dashboard() => _page('DASHBOARD');
  @override
  Widget productList({StorageLocation? location}) => _page('INVENTORY');

  /// A bare screen with a top bar like the real ones (menu button and cart icon).
  Widget _page(String name) => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(leading: menuButton(context), title: Text(name), actions: cartActions(context)),
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => const Scaffold(body: Text('OTHER'));
}

void main() {
  tearDown(() {
    Language.englishDigits = false; // the test config's default
    Language.current = AppLanguage.bangla;
  });

  const nails = Product(
    id: 1,
    name: 'পেরেক',
    kind: ProductKind.loose,
    purchasePrice: 80,
    sellingPrice: 100,
    stock: 10,
    unit: 'কেজি',
  );
  const pipe = Product(id: 2, name: 'পাইপ', purchasePrice: 40, sellingPrice: 60, stock: 5, unit: 'পিস');

  late FakeProductRepository products;
  late SellViewModel cart;

  setUp(() async {
    products = FakeProductRepository([nails, pipe]);
    cart = SellViewModel(
      products,
      FakeSalesRepository(products, FakeClock(DateTime(2026, 11, 22, 15, 30))),
      FakeLocationRepository(),
      FakeCustomerRepository(),
    );
    await cart.load();
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('English digits everywhere', () {
    test('numbers, money, dates and counts show 0-9 by default, in Bangla text too', () {
      Language.englishDigits = true;
      expect(formatNumber(1250), '1250');
      expect(formatMoney(40), '৳40');
      expect(formatNumber(0.5), '0.50');
      expect(Bn.customerTimes(3), contains('3'));
      expect(Bn.customerTimes(3), isNot(contains('৩')));
      expect(formatDateTime(DateTime(2026, 11, 22, 15, 5)), isNot(matches(RegExp(r'[০-৯]'))));
      Language.current = AppLanguage.english;
      expect(formatMoney(40), '৳40');
    });

    test('typing in either kind of digit is still understood', () {
      Language.englishDigits = true;
      expect(parseNumber('১২৫'), 125);
      expect(parseNumber('125'), 125);
    });

    test('a fresh shop starts with one category, General', () {
      expect(starterCategories, ['General']);
    });
  });

  group('the cart icon at the top', () {
    Future<void> openShell(WidgetTester tester) async {
      bigScreen(tester);
      final session = Session()..signIn(const AppUser(id: 1, name: 'মালিক', role: UserRole.owner));
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _Screens(cart), currentUser: session, onSignOut: () {}, cart: cart),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no cart icon while the cart is empty', (tester) async {
      await openShell(tester);
      expect(find.byTooltip(Bn.cartIconTooltip), findsNothing);
    });

    testWidgets('with items in the cart, the icon shows how many, on whichever screen', (tester) async {
      await openShell(tester);
      cart.addToCart(nails, quantity: 2);
      cart.addToCart(pipe);
      await tester.pumpAndSettle();
      expect(find.byTooltip(Bn.cartIconTooltip), findsOneWidget);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsOneWidget);
    });

    testWidgets('the cart is not lost when another screen is opened', (tester) async {
      await openShell(tester);
      cart.addToCart(nails);
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.navInventory));
      await tester.pumpAndSettle();
      expect(cart.cartCount, 1);
      expect(find.byTooltip(Bn.cartIconTooltip), findsOneWidget, reason: 'still there on the inventory screen');
    });

    testWidgets('tapping it opens the cart', (tester) async {
      await openShell(tester);
      cart.addToCart(nails);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(Bn.cartIconTooltip));
      await tester.pumpAndSettle();
      expect(find.text(Bn.cartTitle), findsOneWidget);
      expect(find.text('পেরেক'), findsOneWidget);
    });

    testWidgets('outside the shell there is no icon', (tester) async {
      cart.addToCart(nails);
      await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(actions: [Builder(builder: (c) => Row(children: cartActions(c)))]))));
      expect(find.byTooltip(Bn.cartIconTooltip), findsNothing);
    });
  });

  group('the cart page', () {
    Future<void> open(WidgetTester tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage(viewModel: cart, screens: _Screens(cart)))),
            child: const Text('open-cart'),
          ),
        ),
      )));
      await tester.tap(find.text('open-cart'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every item with its price and total', (tester) async {
      cart.addToCart(nails, quantity: 2);
      cart.addToCart(pipe);
      await open(tester);
      expect(find.text('পেরেক'), findsOneWidget);
      expect(find.text('পাইপ'), findsOneWidget);
      expect(find.text('৳২৬০'), findsWidgets, reason: '200 + 60');
    });

    testWidgets('amounts go up and down (loose goods by half), and an item can be taken out', (tester) async {
      cart.addToCart(nails, quantity: 2);
      await open(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(cart.cart.single.quantity, 2.5);
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();
      expect(cart.cart.single.quantity, 2);
      await tester.tap(find.byTooltip(Bn.removeFromCart));
      await tester.pumpAndSettle();
      expect(cart.cartCount, 0);
      expect(find.text(Bn.cartEmpty), findsOneWidget);
    });

    testWidgets('cannot go above the stock', (tester) async {
      cart.addToCart(pipe, quantity: 5);
      await open(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(cart.cart.single.quantity, 5);
      expect(find.text('মজুদে এত পরিমাণ নেই।'), findsOneWidget);
    });

    testWidgets('CANCEL asks first, then empties the cart and closes the page', (tester) async {
      cart.addToCart(nails);
      await open(tester);
      await tester.tap(find.text(Bn.cartCancel));
      await tester.pumpAndSettle();
      expect(cart.cartCount, 1, reason: 'it asked first');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(Bn.cartCancel)));
      await tester.pumpAndSettle();
      expect(cart.cartCount, 0);
      expect(find.byType(CartPage), findsNothing);
    });

    testWidgets('keeping the cart when the question is answered "no"', (tester) async {
      cart.addToCart(nails);
      await open(tester);
      await tester.tap(find.text(Bn.cartCancel));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(Bn.cancel)));
      await tester.pumpAndSettle();
      expect(cart.cartCount, 1);
      expect(find.byType(CartPage), findsOneWidget);
    });

    testWidgets('SELL goes on to checkout; once the sale is made the page closes', (tester) async {
      cart.addToCart(nails);
      await open(tester);
      await tester.tap(find.text(Bn.cartSell));
      await tester.pumpAndSettle();
      expect(find.text('CHECKOUT-PAGE'), findsOneWidget);
      await tester.tap(find.text('CHECKOUT-PAGE')); // the sale is made: cart emptied
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('CHECKOUT-PAGE'))).pop(); // back from the receipt
      await tester.pumpAndSettle();
      expect(find.byType(CartPage), findsNothing);
    });
  });

  group('the selling sheet', () {
    testWidgets('shows both the selling price and the buying price', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSellSheet(context, product: nails, locationName: (_) => '', inCart: 0),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('${Bn.sellingPrice}: ৳১০০'), findsOneWidget);
      expect(find.text('${Bn.purchasePrice}: ৳৮০'), findsOneWidget);
    });
  });

  group('coming back from a menu page', () {
    ProductListViewModel listVm() =>
        ProductListViewModel(products, FakeCategoryRepository(), FakeLocationRepository(), FakeStockRepository());

    test('a quiet reload never shows the loading bar, and still refreshes', () async {
      final vm = listVm();
      await vm.load();
      var sawLoading = false;
      vm.addListener(() => sawLoading |= vm.loading);
      await vm.load(quiet: true);
      expect(sawLoading, isFalse);
      expect(vm.products, hasLength(2));
      await vm.load();
      expect(sawLoading, isTrue, reason: 'a normal reload still shows it');
    });

    testWidgets('the inventory refreshes quietly when the shell says data changed: no progress bar appears', (tester) async {
      bigScreen(tester);
      final signal = ValueNotifier<int>(0);
      final vm = listVm();
      await tester.pumpWidget(MaterialApp(
        home: ShellScope(
          openDrawer: () {},
          dataChanged: signal,
          child: ProductListPage(viewModel: vm, screens: _Screens(cart)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);

      var barSeen = false;
      vm.addListener(() => barSeen |= vm.loading);
      signal.value++;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
      expect(barSeen, isFalse);
      expect(find.text('পেরেক'), findsOneWidget, reason: 'the list stayed on screen');
    });
  });
}
