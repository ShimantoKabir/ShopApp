import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/data/platform_receipt_sender.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/presentation/checkout_page.dart';
import 'package:hardware_shop/presentation/receipt_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

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
  Widget receipt(Bill bill) => Scaffold(body: Center(child: Text('RECEIPT-${bill.id}')));
}

// The labels on the checkout form ("*" is added when the field is required).
const phoneLabel = 'মোবাইল / WhatsApp নম্বর';
const addressLabel = 'ঠিকানা';
const nameLabel = 'গ্রাহকের নাম';
const nidLabel = 'জাতীয় পরিচয়পত্র (NID) নম্বর';
const badMobile = 'সঠিক ১১ সংখ্যার মোবাইল নম্বর দিন (যেমন ০১৭১২৩৪৫৬৭৮)';
const badNid = 'NID নম্বর ১০, ১৩ বা ১৭ সংখ্যার হতে হবে';
const dueRequired = 'বাকির জন্য এটি আবশ্যক';

void main() {
  late FakeProductRepository products;
  late FakeSalesRepository sales;
  late FakeCustomerRepository customers;
  late SellViewModel vm;

  setUp(() async {
    products = FakeProductRepository([
      const Product(
        id: 1,
        name: 'পেরেক',
        kind: ProductKind.loose,
        purchasePrice: 80,
        sellingPrice: 100,
        stock: 10,
        unit: 'কেজি',
      ),
    ]);
    sales = FakeSalesRepository(products, FakeClock(DateTime(2026, 11, 22, 15, 30)));
    customers = FakeCustomerRepository({
      '01712345678': const CustomerInfo(
        name: 'রহিম',
        mobile: '01812345678',
        nid: '1234567890',
        address: 'কাজিপুর, সিরাজগঞ্জ',
        whatsapp: '01712345678',
      ),
      '01812345678': const CustomerInfo(
        name: 'রহিম',
        mobile: '01812345678',
        nid: '1234567890',
        address: 'কাজিপুর, সিরাজগঞ্জ',
        whatsapp: '01712345678',
      ),
    });
    vm = SellViewModel(products, sales, FakeLocationRepository(), customers);
    await vm.load();
    vm.addToCart(vm.products.first, quantity: 2); // total 200
  });

  /// Opens the checkout page on top of a host page, as the sell screen does.
  Future<void> openCheckout(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutPage(viewModel: vm, screens: _Screens()))),
            child: const Text('open-checkout'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open-checkout'));
    await tester.pumpAndSettle();
  }

  /// A text field by its label.
  Finder field(String label) => find.ancestor(of: find.text(label), matching: find.byType(TextFormField));
  String textOf(WidgetTester tester, String label) => tester.widget<TextFormField>(field(label)).controller!.text;

  /// The one number (WhatsApp, and also what calls and SMS use), and an address
  /// if given. On a due sale the labels have a star.
  Future<void> fillContact(
    WidgetTester tester, {
    String number = '01911111111',
    String? address,
    bool due = false,
  }) async {
    await tester.enterText(field(due ? '$phoneLabel *' : phoneLabel), number);
    if (address != null) await tester.enterText(field(due ? '$addressLabel *' : addressLabel), address);
  }

  /// A due sale needs the address too.
  Future<void> fillDueContact(WidgetTester tester, {String number = '01911111111'}) =>
      fillContact(tester, number: number, address: 'বাজার রোড', due: true);

  Future<void> payOnly(WidgetTester tester, String amount) async {
    await tester.tap(find.byType(Switch)); // "paid in full" off
    await tester.pumpAndSettle();
    await tester.enterText(field('কত টাকা পেয়েছি'), amount);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('নিশ্চিত করুন'));
    await tester.tap(find.text('নিশ্চিত করুন'));
    await tester.pumpAndSettle();
  }

  group('Checkout page: paid in full', () {
    testWidgets('shows the cart and total and "paid in full", with the customer fields folded away', (tester) async {
      await openCheckout(tester);
      expect(find.text('পেরেক'), findsOneWidget);
      expect(find.text('২ কেজি'), findsOneWidget);
      expect(find.text('৳২০০'), findsWidgets);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text(phoneLabel), findsNothing);
      expect(find.text(addressLabel), findsNothing);
      expect(find.text(nameLabel), findsNothing);
      expect(find.text(nidLabel), findsNothing);
    });

    testWidgets('a paid sale goes straight through, with no customer', (tester) async {
      await openCheckout(tester);
      await confirm(tester);
      expect(tester.takeException(), isNull);
      expect(sales.calls.single, 'checkout 1x2.0@100.0 paid=null name=null mobile=null nid=null address=null whatsapp=null');
      expect(find.text('RECEIPT-1'), findsOneWidget);
      expect(vm.cart, isEmpty);
    });

    testWidgets('turning "paid in full" off opens the customer details; turning it on folds them again', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('$phoneLabel *'), findsOneWidget);
      expect(find.text('$nameLabel *'), findsOneWidget);
      expect(find.text('$addressLabel *'), findsOneWidget);
      expect(find.text('$nidLabel *'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(phoneLabel), findsNothing);
      expect(find.text('$phoneLabel *'), findsNothing);
      expect(find.text(nameLabel), findsNothing);
    });

    testWidgets('details typed and then hidden (switched back to paid in full) are not sent', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillDueContact(tester);
      await tester.tap(find.byType(Switch)); // paid in full again
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(sales.calls.single, 'checkout 1x2.0@100.0 paid=null name=null mobile=null nid=null address=null whatsapp=null');
    });
  });

  group('Checkout page: the customer section is small, never gone', () {
    const header = 'গ্রাহকের তথ্য';
    const hint = 'ঐচ্ছিক • সময় থাকলে গ্রাহকের তথ্য নিতে চাপুন';

    testWidgets('paid in full: the section is there but minimized, with an invitation to open it', (tester) async {
      await openCheckout(tester);
      expect(find.text(header), findsOneWidget);
      expect(find.text(hint), findsOneWidget);
      expect(find.text(phoneLabel), findsNothing, reason: 'fields are folded away');
    });

    testWidgets('tapping it opens the fields, all optional (no stars); tapping again folds it', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      expect(find.text(phoneLabel), findsOneWidget);
      expect(find.text(nameLabel), findsOneWidget);
      expect(find.text(addressLabel), findsOneWidget);
      expect(find.text(nidLabel), findsOneWidget);
      expect(find.text(hint), findsNothing);

      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      expect(find.text(phoneLabel), findsNothing);
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('details given in a quiet moment are sent with a paid sale', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      await fillContact(tester, address: 'বাজার রোড');
      await tester.enterText(field(nameLabel), 'করিম');
      await confirm(tester);
      expect(sales.calls.single, 'checkout 1x2.0@100.0 paid=null name=করিম mobile=01911111111 nid= address=বাজার রোড whatsapp=01911111111');
    });

    testWidgets('an optional number must still be valid', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      await fillContact(tester, number: '12345');
      await confirm(tester);
      expect(find.text(badMobile), findsOneWidget);
      expect(sales.calls, isEmpty);
    });

    testWidgets('left folded, nothing is sent even if something was typed before folding it', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      await tester.enterText(field(nameLabel), 'করিম');
      await tester.tap(find.text(header)); // fold it again
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(sales.calls.single, 'checkout 1x2.0@100.0 paid=null name=null mobile=null nid=null address=null whatsapp=null');
    });

    testWidgets('with a due it opens by itself, is required, and cannot be folded away', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      expect(find.text('$phoneLabel *'), findsOneWidget);
      expect(find.text(hint), findsNothing);
      await tester.tap(find.text(header));
      await tester.pumpAndSettle();
      expect(find.text('$phoneLabel *'), findsOneWidget, reason: 'still open');
    });

    testWidgets('back to paid in full: it folds again (unless it was opened on purpose)', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(phoneLabel), findsNothing);
      expect(find.text(hint), findsOneWidget);
    });
  });

  group('Checkout page: due (credit) sales', () {
    testWidgets('turning off "paid in full" makes name, address, number and NID required, and shows what is due', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      expect(find.text('$nameLabel *'), findsOneWidget);
      expect(find.text('$addressLabel *'), findsOneWidget);
      expect(find.text('$phoneLabel *'), findsOneWidget);
      expect(find.text('$nidLabel *'), findsOneWidget);
      expect(find.text('বাকি: ৳১৫০'), findsOneWidget);
    });

    testWidgets('a due sale with nothing filled in is blocked, and every missing field says why', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await confirm(tester);
      expect(find.text(dueRequired), findsNWidgets(4), reason: 'name, address, number and NID');
      expect(sales.calls, isEmpty);
      expect(vm.cartCount, 1);
    });

    testWidgets('a number alone is not enough for a due sale', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillContact(tester, due: true);
      await confirm(tester);
      expect(find.text(dueRequired), findsNWidgets(3), reason: 'name, address and NID');
      expect(sales.calls, isEmpty);
    });

    testWidgets('one missing piece is still blocked', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillDueContact(tester);
      await tester.enterText(field('$nameLabel *'), 'করিম');
      // NID left empty
      await confirm(tester);
      expect(find.text(dueRequired), findsOneWidget);
      expect(sales.calls, isEmpty);
    });

    testWidgets('a wrong number or NID says what is wrong', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillDueContact(tester, number: '12345');
      await tester.enterText(field('$nameLabel *'), 'রহিম');
      await tester.enterText(field('$nidLabel *'), '123');
      await confirm(tester);
      expect(find.text(badMobile), findsOneWidget);
      expect(find.text(badNid), findsOneWidget);
      expect(sales.calls, isEmpty);
    });

    testWidgets('a complete due sale sells on credit and passes everything on', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillDueContact(tester, number: '০১৯১১১১১১১১১'.replaceAll('১১১১১১১১১', '১১১১১১১১'));
      await tester.enterText(field('$nameLabel *'), 'করিম');
      await tester.enterText(field('$nidLabel *'), '1234567890');
      await confirm(tester);

      expect(tester.takeException(), isNull);
      final call = sales.calls.single;
      expect(call, contains('paid=50.0'));
      expect(call, contains('name=করিম'));
      expect(call, contains('mobile=০১৯১১১১১১১১ '), reason: 'typed once, sent as the mobile...');
      expect(call, endsWith('whatsapp=০১৯১১১১১১১১'), reason: '...and as the WhatsApp number');
      expect(call, contains('nid=1234567890'));
      expect(call, contains('address=বাজার রোড'));
      expect(find.text('RECEIPT-1'), findsOneWidget);
    });

    testWidgets('leaving "how much was paid" empty means nothing was paid: it is not an error', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('সঠিক সংখ্যা লিখুন'), findsNothing);
      expect(find.text('বাকি: ৳২০০'), findsOneWidget);

      await fillDueContact(tester);
      await tester.enterText(field('$nameLabel *'), 'করিম');
      await tester.enterText(field('$nidLabel *'), '1234567890');
      await confirm(tester);
      expect(sales.calls.single, contains('paid=0.0'));
    });

    testWidgets('an unreadable amount is still an error', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      // Letters can't be typed here at all; this is typeable but not a number.
      await tester.enterText(field('কত টাকা পেয়েছি'), '1.2.3');
      await confirm(tester);
      expect(find.text('সঠিক সংখ্যা লিখুন'), findsOneWidget);
      expect(sales.calls, isEmpty);
    });

    testWidgets('cannot take more than the total', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '250');
      await confirm(tester);
      expect(find.text('মোট দামের বেশি নেওয়া যাবে না'), findsOneWidget);
      expect(sales.calls, isEmpty);
    });

    testWidgets('after a failed confirm, an error goes away as soon as that field is fixed', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await confirm(tester);
      expect(find.text(dueRequired), findsNWidgets(4));

      await tester.enterText(field('$nameLabel *'), 'করিম');
      await tester.pumpAndSettle();
      expect(find.text(dueRequired), findsNWidgets(3), reason: 'the name error cleared; the other three remain');

      await tester.enterText(field('$phoneLabel *'), '12');
      await tester.pumpAndSettle();
      expect(find.text(badMobile), findsOneWidget, reason: 'now it is wrong, not missing');
    });

    testWidgets('switching back to "paid in full" removes the fields and every "required" error', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await confirm(tester);
      expect(find.text(dueRequired), findsNWidgets(4));

      await tester.tap(find.byType(Switch)); // paid in full again
      await tester.pumpAndSettle();
      expect(find.text(dueRequired), findsNothing);
      expect(find.text(phoneLabel), findsNothing);
      expect(find.text(nameLabel), findsNothing);
    });
  });

  group('Checkout page: customers, refusals, cart', () {
    testWidgets('a repeat customer is recognised by their number: name, address and NID are filled in', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50'); // the customer details appear when something is due
      await tester.enterText(field('$phoneLabel *'), '01712345678');
      await tester.pumpAndSettle();
      expect(find.text('পুরনো গ্রাহক: তথ্য বসানো হয়েছে'), findsOneWidget);
      expect(textOf(tester, '$nameLabel *'), 'রহিম');
      expect(textOf(tester, '$addressLabel *'), 'কাজিপুর, সিরাজগঞ্জ');
      expect(textOf(tester, '$nidLabel *'), '1234567890');
    });

    testWidgets('...also by the number they once gave as their mobile', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50'); // the customer details appear when something is due
      await tester.enterText(field('$phoneLabel *'), '01812345678');
      await tester.pumpAndSettle();
      expect(textOf(tester, '$phoneLabel *'), '01812345678', reason: 'what was typed is kept');
      expect(textOf(tester, '$addressLabel *'), 'কাজিপুর, সিরাজগঞ্জ');
    });

    testWidgets('recognising a customer never overwrites what staff already typed', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50'); // the customer details appear when something is due
      await tester.enterText(field('$nameLabel *'), 'অন্য নাম');
      await tester.enterText(field('$addressLabel *'), 'নতুন ঠিকানা');
      await tester.enterText(field('$phoneLabel *'), '01712345678');
      await tester.pumpAndSettle();
      expect(textOf(tester, '$nameLabel *'), 'অন্য নাম');
      expect(textOf(tester, '$addressLabel *'), 'নতুন ঠিকানা');
    });

    testWidgets('an unknown number fills nothing in', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50'); // the customer details appear when something is due
      await tester.enterText(field('$phoneLabel *'), '01999999999');
      await tester.pumpAndSettle();
      expect(find.text('পুরনো গ্রাহক: তথ্য বসানো হয়েছে'), findsNothing);
      expect(textOf(tester, '$nameLabel *'), '');
    });

    testWidgets('if the repository refuses the customer details, the page stays', (tester) async {
      await openCheckout(tester);
      await payOnly(tester, '50');
      await fillDueContact(tester);
      await tester.enterText(field('$nameLabel *'), 'করিম');
      await tester.enterText(field('$nidLabel *'), '1234567890');
      sales.failWith = const SaleException(SaleProblem.invalidCustomer);
      await confirm(tester);
      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(vm.cartCount, 1);
    });

    testWidgets('if the stock ran out, the reason is shown and the page stays', (tester) async {
      await openCheckout(tester);
      sales.failWith = const StockException(StockProblem.insufficientStock);
      await confirm(tester);
      expect(find.text('মজুদে এত পরিমাণ নেই।'), findsOneWidget);
      expect(find.byType(CheckoutPage), findsOneWidget);
    });

    testWidgets('no connection: the reason is shown, the page stays and the cart is kept (nothing was sold)', (tester) async {
      await openCheckout(tester);
      sales.failWith = const SyncException(SyncProblem.offline);
      await confirm(tester);
      expect(find.text('ইন্টারনেট নেই। সংযোগ ফিরলে আবার চেষ্টা করুন।'), findsOneWidget);
      expect(find.byType(CheckoutPage), findsOneWidget);
      expect(vm.cartCount, 1);
    });

    testWidgets('recorded but not seen back yet: say so and leave, with an empty cart, so it cannot be sold twice', (tester) async {
      await openCheckout(tester);
      sales.failWith = const SyncException(SyncProblem.delayed);
      await confirm(tester);
      expect(find.text('সংরক্ষণ হয়েছে, কিন্তু এই ফোনে দেখা যেতে একটু সময় লাগবে। আবার করবেন না।'), findsOneWidget);
      expect(find.byType(CheckoutPage), findsNothing);
      expect(vm.cartCount, 0);
    });

    testWidgets('quantities can be changed here and the total follows', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('৳৩০০'), findsWidgets);
      expect(vm.cart.single.quantity, 3);
    });

    testWidgets('quantity cannot go above the stock', (tester) async {
      await openCheckout(tester);
      vm.setQuantity(vm.cart.single, 10);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('মজুদে এত পরিমাণ নেই।'), findsOneWidget);
      expect(vm.cart.single.quantity, 10);
    });

    testWidgets('removing the last item closes the page (nothing left to sell)', (tester) async {
      await openCheckout(tester);
      await tester.tap(find.byIcon(Icons.remove_circle_outline)); // 2 -> 1
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_circle_outline)); // 1 -> gone
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutPage), findsNothing);
    });
  });

  group('Receipt page', () {
    final at = DateTime(2026, 11, 22, 15, 35);
    Sale line(String name, double q, double price) =>
        Sale(productName: name, unit: 'কেজি', quantity: q, unitPrice: price, unitCost: 0, at: at);

    Bill bill({
      double paid = 300,
      String name = 'রহিম',
      String mobile = '01812345678',
      String whatsapp = '01712345678',
      String address = 'কাজিপুর, সিরাজগঞ্জ',
    }) =>
        Bill(
          id: 7,
          customerName: name,
          customerMobile: mobile,
          customerAddress: address,
          customerWhatsApp: whatsapp,
          paid: paid,
          at: at,
          lines: [line('পেরেক', 2, 100), line('তার', 1, 100)],
        );

    late FakeReceiptSender sender;
    setUp(() => sender = FakeReceiptSender());

    Future<void> openReceipt(WidgetTester tester, Bill b) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(bill: b, sender: sender))),
              child: const Text('open-receipt'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open-receipt'));
      await tester.pumpAndSettle();
    }

    Finder dialogButton(String label) => find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

    testWidgets('shows the shop, number, customer, address, every item, total and paid', (tester) async {
      await openReceipt(tester, bill());
      expect(find.text('দোকান খাতা'), findsOneWidget);
      expect(find.textContaining('রসিদ নং: ৭'), findsOneWidget);
      expect(find.text('গ্রাহক: রহিম'), findsOneWidget);
      expect(find.text('ঠিকানা: কাজিপুর, সিরাজগঞ্জ'), findsOneWidget);
      expect(find.text('পেরেক'), findsOneWidget);
      expect(find.text('তার'), findsOneWidget);
      expect(find.text('৳৩০০'), findsWidgets);
      expect(find.text('বাকি'), findsNothing, reason: 'fully paid');
    });

    testWidgets('a due bill shows what is still owed', (tester) async {
      await openReceipt(tester, bill(paid: 120)); // total 300, so 180 is due
      expect(find.text('বাকি'), findsOneWidget);
      expect(find.text('৳১৮০'), findsOneWidget);
      expect(find.text('৳১২০'), findsOneWidget, reason: 'what was paid');
    });

    testWidgets('WHATSAPP goes to the WHATSAPP number (not the mobile), with the whole receipt, in one tap', (tester) async {
      await openReceipt(tester, bill(paid: 100));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sender.whatsApp, hasLength(1));
      expect(sender.whatsApp.single.mobile, '01712345678', reason: 'the bill also has mobile 01812345678');
      final text = sender.whatsApp.single.message;
      expect(text, contains('রসিদ নং: ৭'));
      expect(text, contains('গ্রাহক: রহিম'));
      expect(text, contains('ঠিকানা: কাজিপুর, সিরাজগঞ্জ'));
      expect(text, contains('পেরেক'));
      expect(text, contains('মোট: ৳৩০০'));
      expect(text, contains('পরিশোধ: ৳১০০'));
      expect(text, contains('বাকি: ৳২০০'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'no question asked: the number is known');
    });

    testWidgets('a bill from before WhatsApp was required falls back to its mobile number', (tester) async {
      await openReceipt(tester, bill(whatsapp: ''));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(sender.whatsApp.single.mobile, '01812345678');
    });

    testWidgets('with no number at all on the bill, it asks for one, then sends to it', (tester) async {
      await openReceipt(tester, bill(name: '', mobile: '', whatsapp: ''));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(find.text('গ্রাহকের WhatsApp নম্বর'), findsOneWidget);

      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '01911111111');
      await tester.tap(dialogButton('পাঠান'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sender.whatsApp.single.mobile, '01911111111');
    });

    testWidgets('a wrong number typed in that question does not send, and says so', (tester) async {
      await openReceipt(tester, bill(name: '', mobile: '', whatsapp: ''));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '12345');
      await tester.tap(dialogButton('পাঠান'));
      await tester.pumpAndSettle();
      expect(sender.whatsApp, isEmpty);
      expect(find.text('সঠিক মোবাইল নম্বর দিন।'), findsOneWidget);
    });

    testWidgets('cancelling that question sends nothing', (tester) async {
      await openReceipt(tester, bill(name: '', mobile: '', whatsapp: ''));
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('বাতিল'));
      await tester.pumpAndSettle();
      expect(sender.whatsApp, isEmpty);
    });

    testWidgets('WhatsApp that cannot be opened points to the share button', (tester) async {
      sender.whatsAppResult = false;
      await openReceipt(tester, bill());
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(find.text('WhatsApp খোলা যায়নি। শেয়ার বাটন ব্যবহার করুন।'), findsOneWidget);
    });

    testWidgets('SHARE sends the same text through the share sheet', (tester) async {
      await openReceipt(tester, bill());
      await tester.tap(find.text('শেয়ার'));
      await tester.pumpAndSettle();
      expect(sender.shared, hasLength(1));
      expect(sender.shared.single, contains('পেরেক'));
      expect(sender.shared.single, contains('মোট: ৳৩০০'));
    });

    testWidgets('the sent text never contains a phone number or NID', (tester) async {
      await openReceipt(tester, bill());
      await tester.tap(find.text('শেয়ার'));
      await tester.pumpAndSettle();
      expect(sender.shared.single, isNot(contains('01712345678')));
      expect(sender.shared.single, isNot(contains('01812345678')));
      expect(sender.shared.single, isNot(contains('NID')));
    });

    testWidgets('DONE closes the receipt', (tester) async {
      await openReceipt(tester, bill());
      await tester.tap(find.text('শেষ'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptPage), findsNothing);
    });
  });

  group('WhatsApp link', () {
    test('uses the international number and carries the whole receipt, encoded', () {
      const message = 'রসিদ নং: ৭\nমোট: ৳৩০০';
      final uri = whatsAppUri('01712345678', message)!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/8801712345678');
      expect(uri.queryParameters['text'], message, reason: 'Bangla text and the line break survive the round trip');
    });

    test('any usual way of writing the mobile gives the same link', () {
      final expected = whatsAppUri('01712345678', 'x');
      for (final input in ['+8801712345678', '8801712345678', '017-1234-5678']) {
        expect(whatsAppUri(input, 'x'), expected, reason: input);
      }
    });

    test('an invalid mobile gives no link at all', () {
      expect(whatsAppUri('12345', 'x'), isNull);
      expect(whatsAppUri('', 'x'), isNull);
    });
  });
}
