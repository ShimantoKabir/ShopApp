import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/presentation/receipt/receipt_page.dart';
import 'package:hardware_shop/presentation/receipt/receipt_viewmodel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

/// Adding a customer to a sale that was made without one.

class _Clock implements Clock {
  DateTime current;
  _Clock(this.current);
  @override
  DateTime now() => current;
}

Matcher throwsSale(SaleProblem problem) =>
    throwsA(isA<SaleException>().having((e) => e.problem, 'problem', problem));

const _rahim = CustomerInfo(
  name: 'রহিম',
  mobile: '01712345678',
  nid: '1234567890',
  address: 'কাজিপুর',
  whatsapp: '01712345678',
);

void main() {
  group('the repository', () {
    const file = 'attach_customer_test.db';

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late AppDatabase appDb;
    late SqliteProductRepository products;
    late SqliteSalesRepository sales;
    late SqliteCustomerRepository customers;
    late Product nails;

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), file));
      final clock = _Clock(DateTime(2026, 11, 22, 10));
      appDb = AppDatabase(fileName: file);
      products = SqliteProductRepository(appDb, clock);
      sales = SqliteSalesRepository(appDb, clock);
      customers = SqliteCustomerRepository(appDb, clock);
      nails = await products.save(const Product(
        name: 'পেরেক',
        kind: ProductKind.loose,
        purchasePrice: 80,
        sellingPrice: 100,
        stock: 20,
        unit: 'কেজি',
      ));
    });

    tearDown(() async => (await appDb.db).close());

    Future<Bill> sellTo(CustomerInfo? customer, {double? paid, double qty = 2}) =>
        sales.checkout([SaleLine(productId: nails.id!, quantity: qty, unitPrice: 100)], customer: customer, paid: paid);

    test('a sale with no customer gets one, and the customer counts the sale', () async {
      final bill = await sellTo(null);
      expect(bill.hasCustomer, isFalse);
      expect(bill.customerId, isNull);

      final updated = await sales.attachCustomer(bill.id!, _rahim);
      expect((updated.customerName, updated.customerMobile, updated.customerWhatsApp), ('রহিম', '01712345678', '01712345678'));
      expect(updated.customerId, isNotNull);
      expect(updated.lines.single.quantity, 2, reason: 'the sale itself is untouched');
      expect(updated.total, bill.total);

      final fromDb = (await sales.billById(bill.id!))!;
      expect((fromDb.customerName, fromDb.customerAddress), ('রহিম', 'কাজিপুর'));
      final customer = (await customers.byId(updated.customerId!))!;
      expect((customer.billCount, customer.totalSpent), (1, 200));
      expect((await sales.billsOfCustomer(customer.id)).map((b) => b.id), [bill.id]);
    });

    test('only a number is needed; the number is cleaned up like at checkout', () async {
      final bill = await sellTo(null);
      final updated = await sales.attachCustomer(bill.id!, const CustomerInfo(whatsapp: '+880 1712-345678'));
      expect(updated.customerWhatsApp, '01712345678');
      expect(updated.customerName, '');
    });

    test('a number that already belongs to a customer joins that customer', () async {
      await sellTo(_rahim);
      final later = await sellTo(null);
      final updated = await sales.attachCustomer(later.id!, const CustomerInfo(whatsapp: '01712345678'));
      expect((await customers.all()).length, 1);
      final customer = (await customers.byId(updated.customerId!))!;
      expect((customer.name, customer.billCount), ('রহিম', 2), reason: 'the record keeps what it knew');
    });

    test('a sale with a due keeps its due, and the customer now owes it', () async {
      final bill = await sellTo(_rahim, paid: 50); // 200 total, 150 due
      final other = await sales.attachCustomer(bill.id!, const CustomerInfo(
        name: 'করিম',
        mobile: '01911111111',
        nid: '9876543210',
        address: 'বাজার',
        whatsapp: '01911111111',
      ));
      expect(other.due, 150);
      expect((await customers.byId(other.customerId!))!.due, 150);
    });

    test('a sale with a due needs every detail', () async {
      final bill = await sellTo(_rahim, paid: 50);
      await expectLater(
        sales.attachCustomer(bill.id!, const CustomerInfo(whatsapp: '01911111111')),
        throwsSale(SaleProblem.customerRequiredForDue),
      );
      expect((await sales.billById(bill.id!))!.customerName, 'রহিম', reason: 'nothing changed');
    });

    test('no number, a bad number, a bad NID and an unknown sale are refused; nothing is saved', () async {
      final bill = await sellTo(null);
      await expectLater(sales.attachCustomer(bill.id!, const CustomerInfo(name: 'রহিম')), throwsSale(SaleProblem.contactRequired));
      await expectLater(sales.attachCustomer(bill.id!, const CustomerInfo(whatsapp: '12345')), throwsSale(SaleProblem.invalidCustomer));
      await expectLater(
        sales.attachCustomer(bill.id!, const CustomerInfo(whatsapp: '01712345678', nid: '12')),
        throwsSale(SaleProblem.invalidCustomer),
      );
      await expectLater(sales.attachCustomer(999, _rahim), throwsSale(SaleProblem.unknownBill));
      expect((await sales.billById(bill.id!))!.hasCustomer, isFalse);
      expect(await customers.all(), isEmpty);
    });
  });

  group('the receipt page', () {
    final at = DateTime(2026, 11, 22, 15, 35);
    late FakeSalesRepository sales;
    late FakeCustomerRepository customers;
    late FakeReceiptSender sender;
    late Bill bill;

    setUp(() {
      sales = FakeSalesRepository(FakeProductRepository(), FakeClock(at));
      customers = FakeCustomerRepository({'01712345678': _rahim});
      sender = FakeReceiptSender();
      bill = Bill(
        id: 7,
        paid: 200,
        at: at,
        lines: [Sale(productName: 'পেরেক', unit: 'কেজি', quantity: 2, unitPrice: 100, unitCost: 80, at: at)],
      );
      sales.bills.add(bill);
    });

    Future<void> openReceipt(WidgetTester tester, {Bill? shown, bool canChange = false, ContactPicker? picker}) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final b = shown ?? bill;
      await tester.pumpWidget(MaterialApp(
        home: ReceiptPage(
          bill: b,
          sender: sender,
          viewModel: ReceiptViewModel(sales, customers, b),
          canChangeCustomer: canChange,
          contactPicker: picker,
        ),
      ));
      await tester.pumpAndSettle();
    }

    // The form's fields, top to bottom: number, name, address, NID.
    Finder field(String label) => find.byType(TextFormField).at(switch (label) {
          'মোবাইল / WhatsApp নম্বর' => 0,
          'গ্রাহকের নাম' => 1,
          _ => throw ArgumentError(label),
        });

    testWidgets('a sale without a customer offers "Add customer"; the receipt then shows who it is for', (tester) async {
      await openReceipt(tester);
      expect(find.text('গ্রাহক যোগ করুন'), findsOneWidget);
      expect(find.textContaining('গ্রাহক:'), findsNothing);

      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      await tester.enterText(field('মোবাইল / WhatsApp নম্বর'), '01911111111');
      await tester.enterText(field('গ্রাহকের নাম'), 'করিম');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(sales.calls.last, 'attach 7 name=করিম mobile=01911111111 whatsapp=01911111111');
      expect(find.text('গ্রাহক: করিম'), findsOneWidget);
      expect(find.text('গ্রাহক যোগ হয়েছে'), findsOneWidget);
      expect(find.text('গ্রাহক যোগ করুন'), findsNothing, reason: 'the sale has a customer now; changing is for the owner');

      // The receipt that is sent now goes to the number just given.
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();
      expect(sender.whatsApp.single.mobile, '01911111111');
    });

    testWidgets('an empty or wrong number is refused in the form, and nothing is sent', (tester) async {
      await openReceipt(tester);
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      final save = find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ'));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the number is required');
      await tester.enterText(field('মোবাইল / WhatsApp নম্বর'), '123');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(sales.calls.where((c) => c.startsWith('attach')), isEmpty);
    });

    testWidgets('typing a known number fills in what we already know', (tester) async {
      await openReceipt(tester);
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      await tester.enterText(field('মোবাইল / WhatsApp নম্বর'), '01712345678');
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field('গ্রাহকের নাম')).controller!.text, 'রহিম');
      expect(find.text('পুরনো গ্রাহক: তথ্য বসানো হয়েছে'), findsOneWidget);
    });

    testWidgets('the customer can be chosen from the phone contacts instead of typed', (tester) async {
      final picker = FakeContactPicker(const PickedContact(name: 'জামাল', number: '+8801911111111'));
      await openReceipt(tester, picker: picker);
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ফোনের কন্টাক্ট থেকে নিন'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field('মোবাইল / WhatsApp নম্বর')).controller!.text, '01911111111');
      expect(tester.widget<TextFormField>(field('গ্রাহকের নাম')).controller!.text, 'জামাল');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      expect(sales.calls.last, 'attach 7 name=জামাল mobile=01911111111 whatsapp=01911111111');
    });

    testWidgets('the add-customer button is as big as the WhatsApp and share buttons', (tester) async {
      await openReceipt(tester);
      final add = tester.getSize(find.widgetWithText(OutlinedButton, 'গ্রাহক যোগ করুন'));
      final share = tester.getSize(find.widgetWithText(OutlinedButton, 'শেয়ার'));
      final whatsApp = tester.getSize(find.widgetWithText(FilledButton, 'WhatsApp'));
      expect(add, share);
      expect(add, whatsApp);
      expect(add.height, 52);
    });

    testWidgets('the form is wide on a phone, and the first label has room above the box', (tester) async {
      await openReceipt(tester);
      tester.view.physicalSize = const Size(400, 900);
      await tester.pump();
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      final surface = find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;
      expect(tester.getSize(surface).width, 400 - 32, reason: 'only 16 of margin on each side');
      final scroll = tester.getTopLeft(find.byType(SingleChildScrollView).last).dy;
      final field = tester.getTopLeft(find.byType(TextFormField).first).dy;
      expect(field - scroll, greaterThanOrEqualTo(8), reason: 'the floating label rises above the field');
    });

    testWidgets('no contact chooser, no button', (tester) async {
      await openReceipt(tester);
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('ফোনের কন্টাক্ট থেকে নিন'), findsNothing);
    });

    testWidgets('a refusal from the shop is shown, not thrown', (tester) async {
      await openReceipt(tester);
      sales.failWith = const SaleException(SaleProblem.unknownBill);
      await tester.tap(find.text('গ্রাহক যোগ করুন'));
      await tester.pumpAndSettle();
      await tester.enterText(field('মোবাইল / WhatsApp নম্বর'), '01911111111');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('সংরক্ষণ')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('এই বিক্রি আর পাওয়া যাচ্ছে না।'), findsOneWidget);
    });

    testWidgets('a sale that has a customer: only the owner can change it', (tester) async {
      final withCustomer = Bill(
        id: 7,
        customerName: 'রহিম',
        customerMobile: '01712345678',
        customerWhatsApp: '01712345678',
        paid: 200,
        at: at,
        lines: bill.lines,
      );
      await openReceipt(tester, shown: withCustomer);
      expect(find.text('গ্রাহক যোগ করুন'), findsNothing);
      expect(find.text('গ্রাহক বদলান'), findsNothing);
    });

    testWidgets('the owner sees "Change customer" and the form starts with what is there', (tester) async {
      final withCustomer = Bill(
        id: 7,
        customerName: 'রহিম',
        customerMobile: '01712345678',
        customerWhatsApp: '01712345678',
        paid: 200,
        at: at,
        lines: bill.lines,
      );
      sales.bills
        ..clear()
        ..add(withCustomer);
      await openReceipt(tester, shown: withCustomer, canChange: true);
      await tester.tap(find.text('গ্রাহক বদলান'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field('গ্রাহকের নাম')).controller!.text, 'রহিম');
    });

    testWidgets('without a view model (an old caller) the page is as before', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ReceiptPage(bill: bill, sender: sender)));
      await tester.pumpAndSettle();
      expect(find.text('গ্রাহক যোগ করুন'), findsNothing);
      expect(find.text('WhatsApp'), findsOneWidget);
    });
  });
}
