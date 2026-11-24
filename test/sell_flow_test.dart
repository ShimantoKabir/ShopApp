import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/daily_sales_page.dart';
import 'package:hardware_shop/presentation/home_shell.dart';
import 'package:hardware_shop/presentation/product_list_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/sell_page.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:hardware_shop/presentation/widgets/restock_dialog.dart';
import 'package:hardware_shop/presentation/widgets/sale_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

class _Screens implements ScreenFactory {
  @override
  Widget home() => const SizedBox();
  @override
  Widget sell() => const Center(child: Text('SELL-TAB'));
  @override
  Widget shell({required VoidCallback onSignOut}) => const SizedBox();
  @override
  Widget users() => const Scaffold(body: Center(child: Text('USERS-PAGE')));
  @override
  Widget activity() => const SizedBox();
  @override
  Widget syncSettings() => const SizedBox();
  @override
  Widget joinShop() => const SizedBox();
  @override
  Widget profile() => const Scaffold(body: Center(child: Text('PROFILE-PAGE')));
  @override
  Widget settings() => const Scaffold(body: Center(child: Text('SETTINGS-PAGE')));
  @override
  Widget dashboard() => const Center(child: Text('DASHBOARD-TAB'));
  @override
  Widget customers() => const Center(child: Text('CUSTOMERS-TAB'));
  @override
  Widget customerDetail(int customerId) => const SizedBox();
  @override
  Widget dailySales() => const Center(child: Text('ACCOUNT-TAB'));
  @override
  Widget productList({StorageLocation? location}) => const Center(child: Text('INVENTORY-TAB'));
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
  Widget checkout(SellViewModel cart) => const Scaffold(body: Center(child: Text('CHECKOUT-PAGE')));
  @override
  Widget receipt(Bill bill) => Scaffold(body: Center(child: Text('RECEIPT-${bill.id}')));
}

/// A profile page that renames whoever is signed in as soon as it opens.
class _RenamingScreens extends _Screens {
  final Session session;
  _RenamingScreens(this.session);

  @override
  Widget profile() => Builder(builder: (context) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          session.signIn(AppUser(id: session.user!.id, name: 'নতুন নাম', role: session.user!.role));
          Navigator.pop(context);
        });
        return const Scaffold(body: SizedBox());
      });
}

void main() {
  late FakeProductRepository products;
  late FakeClock clock;
  late FakeSalesRepository sales;

  Product nails({double stock = 10}) => Product(
        id: 1,
        name: 'পেরেক',
        kind: ProductKind.loose,
        purchasePrice: 80,
        sellingPrice: 100,
        stock: stock,
        unit: 'কেজি',
        placements: const [StockPlacement(locationId: 5, quantity: 6)],
      );

  const empty = Product(id: 2, name: 'তার', purchasePrice: 50, sellingPrice: 70, stock: 0, unit: 'মিটার');

  setUp(() {
    products = FakeProductRepository([nails(), empty]);
    clock = FakeClock(DateTime(2026, 11, 22, 15, 30));
    sales = FakeSalesRepository(products, clock);
  });

  SellViewModel sellVm() => SellViewModel(products, sales, FakeLocationRepository(), FakeCustomerRepository());
  SalesSummaryViewModel summaryVm() => SalesSummaryViewModel(sales, clock);

  Matcher throwsProblem(StockProblem p) => throwsA(isA<StockException>().having((e) => e.problem, 'problem', p));

  group('SellViewModel (the cart)', () {
    Future<(SellViewModel, Product)> loaded() async {
      final vm = sellVm();
      await vm.load();
      return (vm, vm.products.firstWhere((p) => p.id == 1));
    }

    test('loads sellable products and location names', () async {
      final (vm, _) = await loaded();
      expect(vm.products.map((p) => p.name), containsAll(['পেরেক', 'তার']));
      expect(vm.locationName(5), 'তাক ১');
    });

    test('adding puts a line in the cart at the normal price; the same product merges', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n);
      vm.addToCart(n);
      expect(vm.cartCount, 1);
      expect(vm.cart.single.quantity, 2);
      expect(vm.cart.single.unitPrice, 100);
      expect(vm.cartTotal, 200);
    });

    test('a different price or a different source is a separate line', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n);
      vm.addToCart(n, unitPrice: 90);
      vm.addToCart(n, fromLocationId: 5);
      expect(vm.cartCount, 3);
      expect(vm.inCart(n), 3);
    });

    test('cannot add more than the stock, counting what is already in the cart', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n, quantity: 8);
      expect(vm.availableFor(n), 2);
      expect(() => vm.addToCart(n, quantity: 3), throwsProblem(StockProblem.insufficientStock));
      expect(vm.inCart(n), 8, reason: 'a refused add changes nothing');
      vm.addToCart(n, quantity: 2); // exactly what is left
      expect(vm.availableFor(n), 0);
    });

    test('setQuantity changes a line, removes it at zero, and respects the stock', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n, quantity: 2);
      final line = vm.cart.single;
      vm.setQuantity(line, 5);
      expect(line.quantity, 5);
      expect(() => vm.setQuantity(line, 11), throwsProblem(StockProblem.insufficientStock));
      expect(line.quantity, 5);
      vm.setQuantity(line, 0);
      expect(vm.cart, isEmpty);
    });

    test('removeLine and clearCart empty the cart', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n);
      vm.addToCart(n, unitPrice: 90);
      vm.removeLine(vm.cart.first);
      expect(vm.cartCount, 1);
      vm.clearCart();
      expect(vm.cart, isEmpty);
    });

    test('checkout sells the whole cart as ONE bill, empties the cart and refreshes stock', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n, quantity: 2);
      vm.addToCart(n, quantity: 1, unitPrice: 90);
      final bill = await vm.checkout();
      expect(bill.lines, hasLength(2));
      expect(sales.calls, hasLength(1), reason: 'one bill, not one per line');
      expect(vm.cart, isEmpty);
      expect(vm.products.firstWhere((p) => p.id == 1).stock, 7);
    });

    test('checkout passes the customer and payment through', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n);
      await vm.checkout(customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678', nid: '1234567890'), paid: 40);
      expect(sales.calls.single, contains('paid=40.0'));
      expect(sales.calls.single, contains('name=রহিম'));
      expect(sales.calls.single, contains('nid=1234567890'));
    });

    test('a refused checkout keeps the cart so nothing has to be re-entered', () async {
      final (vm, n) = await loaded();
      vm.addToCart(n, quantity: 2);
      sales.failWith = const SaleException(SaleProblem.customerRequiredForDue);
      await expectLater(vm.checkout(paid: 10), throwsA(isA<SaleException>()));
      expect(vm.cartCount, 1);
      expect(vm.cart.single.quantity, 2);
    });

    test('findCustomer looks a customer up by mobile', () async {
      final vm = SellViewModel(
        products,
        sales,
        FakeLocationRepository(),
        FakeCustomerRepository({'01712345678': const CustomerInfo(name: 'রহিম', mobile: '01712345678', nid: '1234567890')}),
      );
      expect((await vm.findCustomer('01712345678'))!.name, 'রহিম');
      expect(await vm.findCustomer('01999999999'), isNull);
    });
  });

  group('SalesSummaryViewModel', () {
    Future<void> sellNails(double q, double price, {CustomerInfo? customer, double? paid}) => sales
        .checkout([SaleLine(productId: 1, quantity: q, unitPrice: price)], customer: customer, paid: paid)
        .then((_) {});

    test("totals today's bills, including what is still due", () async {
      await sellNails(2, 100); // 200, cost 160
      await sellNails(1, 90, customer: const CustomerInfo(name: 'রহিম'), paid: 30); // 90, cost 80, due 60
      final vm = summaryVm();
      await vm.load();
      expect(vm.label, 'আজ');
      expect(vm.isToday, isTrue);
      expect(vm.summary.saleCount, 2);
      expect(vm.summary.revenue, 290);
      expect(vm.summary.profit, 50);
      expect(vm.summary.due, 60);
    });

    test('browses back a day and forward, but never past today', () async {
      clock.current = DateTime(2026, 11, 21, 12);
      await sellNails(1, 100); // yesterday
      clock.current = DateTime(2026, 11, 22, 15, 30);
      final vm = summaryVm();
      await vm.load();
      expect(vm.bills, isEmpty);

      await vm.previousDay();
      expect(vm.label, 'গতকাল');
      expect(vm.summary.saleCount, 1);

      await vm.nextDay();
      expect(vm.isToday, isTrue);
      await vm.nextDay(); // already today: stays put
      expect(vm.isToday, isTrue);
    });

    test('older days are labelled with their date', () async {
      final vm = summaryVm();
      await vm.previousDay();
      await vm.previousDay();
      expect(vm.label, '২০/১১/২০২৬');
    });

    test('voiding a bill updates the totals and returns the stock', () async {
      await sellNails(3, 100);
      final vm = summaryVm();
      await vm.load();
      await vm.voidBill(vm.bills.single);
      expect(vm.summary.saleCount, 0);
      expect(products.items.firstWhere((p) => p.id == 1).stock, 10);
    });
  });

  group('Sell screen', () {
    Future<SellViewModel> openSell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = sellVm();
      await tester.pumpWidget(MaterialApp(home: SellPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('lists products with their price and stock, and no cart bar yet', (tester) async {
      await openSell(tester);
      expect(find.text('পেরেক'), findsOneWidget);
      expect(find.textContaining('মজুদ আছে: ১০'), findsOneWidget);
      expect(find.textContaining('৳১০০ / কেজি'), findsOneWidget);
      expect(find.byType(CartBar), findsNothing);
    });

    testWidgets('tapping + adds one unit to the cart (it is not sold yet)', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      expect(find.text('১টি পণ্য • ৳১০০'), findsOneWidget);
      expect(find.textContaining('কার্টের পণ্য: ১'), findsOneWidget);
      expect(sales.calls, isEmpty, reason: 'nothing is sold until "complete"');
      expect(products.items.first.stock, 10);
    });

    testWidgets('tapping + twice merges into one line with the right total', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      expect(find.text('১টি পণ্য • ৳২০০'), findsOneWidget);
    });

    testWidgets('+ is disabled once the cart holds all the stock', (tester) async {
      products.items[0] = nails(stock: 1);
      await openSell(tester);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '+ ১ কেজি'));
      expect(add.onPressed, isNull);
    });

    testWidgets('a product with no stock cannot be added', (tester) async {
      await openSell(tester);
      final soldOut = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'শেষ'));
      expect(soldOut.onPressed, isNull);
    });

    testWidgets('the cart bar leads to checkout; nothing is sold from the sell screen itself', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      expect(find.text('গ্রাহক ও বাকি'), findsNothing, reason: 'there is no separate quick path any more');
      expect(find.widgetWithText(FilledButton, 'বিক্রি করুন'), findsOneWidget, reason: 'one button, and it leads to checkout');
      await tester.tap(find.text('বিক্রি করুন'));
      await tester.pumpAndSettle();
      expect(find.text('CHECKOUT-PAGE'), findsOneWidget);
      expect(sales.calls, isEmpty);
      expect(products.items.first.stock, 10);
    });

    testWidgets('the cart is kept when checkout is opened and closed again', (tester) async {
      final vm = await openSell(tester);
      await tester.tap(find.text('+ ১ কেজি'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('বিক্রি করুন'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('CHECKOUT-PAGE'))).pop();
      await tester.pumpAndSettle();
      expect(vm.cartCount, 1);
      expect(find.text('১টি পণ্য • ৳১০০'), findsOneWidget);
    });

    testWidgets('searching narrows the list', (tester) async {
      await openSell(tester);
      await tester.enterText(find.byType(TextField), 'পেরেক');
      await tester.pumpAndSettle();
      expect(find.text('তার'), findsNothing);
      expect(find.byType(SellTile), findsOneWidget, reason: 'only the nails remain');
    });

    testWidgets('CUSTOM quantity and price: card -> sheet -> add to cart', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      expect(find.text('কার্টে যোগ করুন'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add)); // loose goods go up by half: 1 -> 1.5
      await tester.tap(find.byIcon(Icons.add)); // -> 2
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '১০০'), '110');
      await tester.pump();
      expect(find.textContaining('মোট: ৳২২০'), findsOneWidget);
      expect(find.textContaining('লাভ: ৳৬০'), findsOneWidget, reason: '(110-80) x 2');

      await tester.tap(find.text('কার্টে যোগ করুন'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('১টি পণ্য • ৳২২০'), findsOneWidget);
      expect(sales.calls, isEmpty, reason: 'still just in the cart');
    });

    testWidgets('PART of a unit: loose goods have quick 1/4, 1/2 and 1 amounts, and the price follows', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '¼'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '½'));
      await tester.pump();
      expect(find.textContaining('মোট: ৳৫০'), findsOneWidget, reason: 'half a kilo at 100 a kilo');
      await tester.tap(find.text('কার্টে যোগ করুন'));
      await tester.pumpAndSettle();
      expect(find.text('১টি পণ্য • ৳৫০'), findsOneWidget);
    });

    testWidgets('quick amounts are never more than there is', (tester) async {
      final vm = await openSell(tester);
      vm.addToCart(vm.products.first, quantity: 9.8); // 0.2 left
      await tester.pumpAndSettle();
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, '¼'), findsNothing);
      expect(find.widgetWithText(ActionChip, '½'), findsNothing);
    });

    testWidgets('the sheet takes the cart into account: stock already in the cart is not offered again', (tester) async {
      final vm = await openSell(tester);
      vm.addToCart(vm.products.first, quantity: 8);
      await tester.pumpAndSettle();
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      expect(find.textContaining('মজুদ আছে: ২ কেজি'), findsOneWidget, reason: '10 - 8 in the cart');
      await tester.enterText(find.widgetWithText(TextField, '১'), '3');
      await tester.pump();
      expect(find.text('মজুদে এত পরিমাণ নেই।'), findsOneWidget);
      final add = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'কার্টে যোগ করুন'));
      expect(add.onPressed, isNull);
    });

    testWidgets('the sheet can take the units from one location; the cart remembers it', (tester) async {
      final vm = await openSell(tester);
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('তাক ১ · ৬'));
      await tester.pump();
      await tester.tap(find.text('কার্টে যোগ করুন'));
      await tester.pumpAndSettle();
      expect(vm.cart.single.fromLocationId, 5);
    });

    testWidgets('the sheet limits a location sale to what that location holds', (tester) async {
      await openSell(tester);
      await tester.tap(find.text('পেরেক'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('তাক ১ · ৬'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, '১'), '7'); // 10 in total, only 6 there
      await tester.pump();
      expect(find.text('মজুদে এত পরিমাণ নেই।'), findsOneWidget);
    });
  });

  group('Daily account screen', () {
    Future<void> openDay(WidgetTester tester, {FakeContactLauncher? contacts}) async {
      tester.view.physicalSize = const Size(900, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: DailySalesPage(viewModel: summaryVm(), screens: _Screens(), contacts: contacts, shopName: 'হাসান স্টোর'),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> sellNails(double q, double price, {CustomerInfo? customer, double? paid}) async {
      await sales.checkout([SaleLine(productId: 1, quantity: q, unitPrice: price)], customer: customer, paid: paid);
    }

    testWidgets('shows totals and bills, with the customer and what is due', (tester) async {
      await sellNails(2, 100);
      await sellNails(1, 150, customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678'), paid: 0);
      await openDay(tester);

      expect(find.text('আজ'), findsOneWidget);
      expect(find.text('৳৩৫০'), findsOneWidget, reason: 'total sales 200 + 150');
      expect(find.text('খুচরা বিক্রি'), findsOneWidget, reason: 'the anonymous bill');
      expect(find.text('রহিম'), findsOneWidget);
      expect(find.text('বাকি: ৳১৫০'), findsOneWidget, reason: 'on the bill');
      expect(find.text('মোট বাকি: ৳১৫০'), findsOneWidget, reason: 'in the summary');
    });

    testWidgets('a bill with a due has call and share inside its card; the reminder names the customer and the amount', (tester) async {
      final contacts = FakeContactLauncher();
      await sellNails(1, 150, customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678', whatsapp: '01812345678'), paid: 0);
      await openDay(tester, contacts: contacts);

      final card = find.ancestor(of: find.text('রহিম'), matching: find.byType(Card)).first;
      expect(find.descendant(of: card, matching: find.byTooltip('ফোন করুন')), findsOneWidget, reason: 'inside the card');
      await tester.tap(find.byTooltip('ফোন করুন'));
      await tester.tap(find.byTooltip('শেয়ার করুন (যেকোনো অ্যাপে)'));
      await tester.pump();
      expect(contacts.calls, ['01712345678']);
      expect(contacts.shared.single, 'রহিম, আসসালামু আলাইকুম। হাসান স্টোর-এ আপনার ৳১৫০ বাকি আছে। সুবিধামতো পরিশোধ করবেন। ধন্যবাদ।');
    });

    testWidgets('no buttons for a paid bill, and none when no launcher is given', (tester) async {
      final contacts = FakeContactLauncher();
      await sellNails(2, 100, customer: const CustomerInfo(whatsapp: '01812345678')); // paid in full
      await openDay(tester, contacts: contacts);
      expect(find.byTooltip('ফোন করুন'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await sellNails(1, 150, customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678'), paid: 0);
      await openDay(tester);
      expect(find.byTooltip('ফোন করুন'), findsNothing);
    });

    testWidgets('a number that cannot be opened says so', (tester) async {
      final contacts = FakeContactLauncher()..result = false;
      await sellNails(1, 150, customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678'), paid: 0);
      await openDay(tester, contacts: contacts);
      await tester.tap(find.byTooltip('ফোন করুন'));
      await tester.pumpAndSettle();
      expect(find.text('খোলা যায়নি। নম্বরটি ঠিক আছে কিনা দেখুন।'), findsOneWidget);
    });

    testWidgets('no "total due" line when nothing is owed', (tester) async {
      await sellNails(2, 100);
      await openDay(tester);
      expect(find.textContaining('মোট বাকি'), findsNothing);
    });

    testWidgets('tapping a bill opens its receipt', (tester) async {
      await sellNails(2, 100);
      await openDay(tester);
      await tester.tap(find.text('খুচরা বিক্রি'));
      await tester.pumpAndSettle();
      expect(find.text('RECEIPT-1'), findsOneWidget);
    });

    testWidgets('a bill can be cancelled by swiping; the stock comes back', (tester) async {
      await sellNails(2, 100);
      await openDay(tester);
      await tester.drag(find.text('খুচরা বিক্রি'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('বিক্রি বাতিল করলে মজুদ ফিরে আসবে। বাতিল করবেন?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('বিক্রি বাতিল')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sales.calls.last, startsWith('void'));
      expect(find.text('এই দিনে কোনো বিক্রি নেই'), findsOneWidget);
      expect(products.items.firstWhere((p) => p.id == 1).stock, 10, reason: 'stock came back');
    });

    testWidgets('an empty day says so; "next" is disabled today', (tester) async {
      await openDay(tester);
      expect(find.text('এই দিনে কোনো বিক্রি নেই'), findsOneWidget);
      final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNull);
    });

    testWidgets('going back a day enables "next" and changes the label', (tester) async {
      await openDay(tester);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('গতকাল'), findsOneWidget);
      final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNotNull);
    });
  });

  group('Restock', () {
    Future<void> openDialog(WidgetTester tester, void Function(Future<RestockInput?>) capture) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => capture(showRestockDialog(context, product: nails(), locations: const [
              StorageLocation(id: 5, name: 'তাক ১', code: 'A'),
            ])),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('returns the quantity; an unchanged price is not sent', (tester) async {
      late Future<RestockInput?> result;
      await openDialog(tester, (f) => result = f);
      await tester.enterText(find.widgetWithText(TextField, ''), '5');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      final input = await result;
      expect(tester.takeException(), isNull);
      expect(input!.quantity, 5);
      expect(input.purchasePrice, isNull, reason: 'price left at 80');
      expect(input.locationId, isNull);
    });

    testWidgets('a changed price and a chosen location are returned', (tester) async {
      late Future<RestockInput?> result;
      await openDialog(tester, (f) => result = f);
      await tester.enterText(find.widgetWithText(TextField, ''), '2.5');
      await tester.enterText(find.widgetWithText(TextField, '৮০'), '95');
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('তাক ১').last);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      final input = await result;
      expect(tester.takeException(), isNull);
      expect([input!.quantity, input.purchasePrice, input.locationId], [2.5, 95, 5]);
    });

    testWidgets('an empty or zero quantity keeps the dialog open', (tester) async {
      late Future<RestockInput?> result;
      await openDialog(tester, (f) => result = f);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, ''), '0');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      // ignore: unawaited_futures
      result.ignore();
    });

    testWidgets('inventory: the page is headed with the same word as its menu entry', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vm = ProductListViewModel(products, FakeCategoryRepository(), FakeLocationRepository(), FakeStockRepository());
      await tester.pumpWidget(MaterialApp(home: ProductListPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('মজুদ')), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('দোকান খাতা')), findsNothing);
    });

    testWidgets('inventory: tapping the stock opens restock, which calls the stock repository', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final stock = FakeStockRepository();
      final vm = ProductListViewModel(products, FakeCategoryRepository(), FakeLocationRepository(), stock);
      await tester.pumpWidget(MaterialApp(home: ProductListPage(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TappableValue).first);
      await tester.pumpAndSettle();
      expect(find.text('মজুদ আনুন'), findsOneWidget);
      expect(find.text('মজুদ ঠিক করুন'), findsOneWidget);

      await tester.tap(find.text('মজুদ আনুন'));
      await tester.pumpAndSettle();
      // The first field in the dialog is the quantity (the search box behind it is also empty).
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '4');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(stock.calls, ['restock 1 4.0 null null']);
      expect(find.text('মজুদ যোগ হয়েছে'), findsOneWidget);
    });
  });

  group('Home shell', () {
    const owner = AppUser(id: 1, name: 'মালিক', role: UserRole.owner);
    const staff = AppUser(id: 2, name: 'কর্মী১', role: UserRole.staff);

    Future<({Session session, List<int> signOuts})> open(WidgetTester tester, AppUser who) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(who);
      final signOuts = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _Screens(), currentUser: session, onSignOut: () => signOuts.add(1)),
      ));
      await tester.pumpAndSettle();
      return (session: session, signOuts: signOuts);
    }

    Future<void> openDrawer(WidgetTester tester) async {
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String label) async {
      await openDrawer(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationDrawer), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    testWidgets('an owner starts on the dashboard and reaches every screen from the drawer', (tester) async {
      await open(tester, owner);
      expect(find.text('DASHBOARD-TAB'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing, reason: 'no bottom bar any more');

      await choose(tester, 'মজুদ');
      expect(find.text('INVENTORY-TAB'), findsOneWidget);
      expect(find.byType(NavigationDrawer), findsNothing, reason: 'the drawer closes after choosing');

      await choose(tester, 'বিক্রি');
      expect(find.text('SELL-TAB'), findsOneWidget);
      expect(find.text('INVENTORY-TAB'), findsNothing);

      await choose(tester, 'গ্রাহক');
      expect(find.text('CUSTOMERS-TAB'), findsOneWidget);

      await choose(tester, 'হিসাব');
      expect(find.text('ACCOUNT-TAB'), findsOneWidget);

      await choose(tester, 'ড্যাশবোর্ড');
      expect(find.text('DASHBOARD-TAB'), findsOneWidget);
    });

    testWidgets('the drawer says who is signed in and as what', (tester) async {
      await open(tester, owner);
      await openDrawer(tester);
      expect(find.text('মালিক • মালিক'), findsOneWidget);
    });

    testWidgets('staff start on selling, and no menu entry is hidden from them', (tester) async {
      await open(tester, staff);
      expect(find.text('SELL-TAB'), findsOneWidget);
      await openDrawer(tester);
      final drawer = find.byType(NavigationDrawer);
      expect(find.descendant(of: drawer, matching: find.text('ড্যাশবোর্ড')), findsOneWidget);
      expect(find.descendant(of: drawer, matching: find.text('কর্মী')), findsOneWidget);
      expect(find.descendant(of: drawer, matching: find.text('মজুদ')), findsOneWidget);
      expect(find.descendant(of: drawer, matching: find.text('সেটিংস')), findsOneWidget);
      expect(find.descendant(of: drawer, matching: find.text('আমার প্রোফাইল')), findsOneWidget, reason: 'everyone has one');
    });

    testWidgets('anyone can open their own profile from the drawer', (tester) async {
      await open(tester, staff);
      await choose(tester, 'আমার প্রোফাইল');
      expect(find.text('PROFILE-PAGE'), findsOneWidget);
    });

    testWidgets('a name changed on the profile shows in the drawer straight after', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(staff);
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _RenamingScreens(session), currentUser: session, onSignOut: () {}),
      ));
      await tester.pumpAndSettle();
      await choose(tester, 'আমার প্রোফাইল'); // the fake page renames the user, then closes
      await openDrawer(tester);
      expect(find.text('নতুন নাম • কর্মী'), findsOneWidget);
    });

    testWidgets('the owner can open the staff list and settings', (tester) async {
      await open(tester, owner);
      await choose(tester, 'কর্মী');
      expect(find.text('USERS-PAGE'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await choose(tester, 'সেটিংস');
      expect(find.text('SETTINGS-PAGE'), findsOneWidget);
    });

    testWidgets('sign out asks the app to sign out', (tester) async {
      final r = await open(tester, owner);
      await choose(tester, 'বেরিয়ে যান');
      expect(r.signOuts, hasLength(1));
    });
  });
}
