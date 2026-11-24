import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_dashboard_repository.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/domain/customers.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/payments.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/presentation/customer_detail/customer_detail_page.dart';
import 'package:hardware_shop/presentation/customer_detail/customer_detail_viewmodel.dart';
import 'package:hardware_shop/presentation/receipt/payment_receipt_page.dart';
import 'package:hardware_shop/presentation/receipt/receipt_text.dart';
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

Matcher throwsPayment(PaymentProblem problem) =>
    throwsA(isA<PaymentException>().having((e) => e.problem, 'problem', problem));

class _Screens implements ScreenFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('collecting dues (SQL)', () {
    const dbFile = 'payments_test.db';
    late AppDatabase appDb;
    late _Clock clock;
    late SqliteProductRepository products;
    late SqliteSalesRepository sales;
    late SqliteCustomerRepository customers;
    late SqliteDashboardRepository dashboard;
    late Product nails;
    late int rahimId;

    Future<String> path() async => p.join(await getDatabasesPath(), dbFile);

    void open() {
      appDb = AppDatabase(fileName: dbFile);
      products = SqliteProductRepository(appDb, clock);
      sales = SqliteSalesRepository(appDb, clock);
      customers = SqliteCustomerRepository(appDb, clock);
      dashboard = SqliteDashboardRepository(appDb);
    }

    setUp(() async {
      await deleteDatabase(await path());
      clock = _Clock(DateTime(2026, 11, 22, 10));
      open();
      nails = await products.save(const Product(
          name: 'পেরেক', kind: ProductKind.loose, purchasePrice: 80, sellingPrice: 100, stock: 1000, unit: 'কেজি'));
    });

    tearDown(() async => (await appDb.db).close());

    Future<Bill> buy(CustomerInfo who, double qty, {double? paid, DateTime? at}) {
      clock.current = at ?? DateTime(2026, 11, 22, 10);
      return sales.checkout(
        [SaleLine(productId: nails.id!, quantity: qty, unitPrice: 100)],
        customer: who,
        paid: paid,
      );
    }

    /// Rahim owes 300 on an old bill and 500 on a newer one.
    Future<void> rahimOwes() async {
      await buy(rahim, 4, paid: 100, at: DateTime(2026, 11, 1)); // 400, 300 due
      await buy(rahim, 5, paid: 0, at: DateTime(2026, 11, 10)); // 500, 500 due
      rahimId = (await customers.all()).single.id;
      clock.current = DateTime(2026, 11, 22, 15);
    }

    test('the payments of a day are listed with who paid and what they still owed right after', () async {
      await rahimOwes(); // owes 800
      clock.current = DateTime(2026, 11, 22, 15);
      await customers.collectPayment(rahimId, 200); // 600 left
      clock.current = DateTime(2026, 11, 22, 16);
      await customers.collectPayment(rahimId, 600); // nothing left
      await buy(rahim, 2, paid: 0, at: DateTime(2026, 11, 23, 9)); // owes 200 again, the next day

      final day = await sales.paymentsOn(DateTime(2026, 11, 22));
      expect(day.map((r) => r.payment.amount), [600, 200], reason: 'newest first');
      expect(day.map((r) => r.dueAfter), [0, 600], reason: 'what was owed right after each one');
      expect((day.first.customerName, day.first.customerWhatsApp), ('রহিম', '01712345678'));
      expect(day.first.payment.at, DateTime(2026, 11, 22, 16));

      expect(await sales.paymentsOn(DateTime(2026, 11, 21)), isEmpty);
      expect(await sales.paymentsOn(DateTime(2026, 11, 23)), isEmpty, reason: 'a sale is not a payment');
    });

    test('a customer with a due made on the same day: the receipt counts only what was owed by then', () async {
      await buy(karim, 3, paid: 0, at: DateTime(2026, 11, 22, 9)); // owes 300
      final id = (await customers.all()).firstWhere((c) => c.name == 'করিম').id;
      clock.current = DateTime(2026, 11, 22, 11);
      await customers.collectPayment(id, 100);
      await buy(karim, 1, paid: 0, at: DateTime(2026, 11, 22, 13)); // owes 100 more later that day
      final receipts = await sales.paymentsOn(DateTime(2026, 11, 22));
      expect(receipts.single.dueAfter, 200, reason: 'the later bill is not part of it');
    });

    test('a part payment lowers the due and goes to the oldest bill first', () async {
      await rahimOwes();
      final payment = await customers.collectPayment(rahimId, 200);
      expect(payment.amount, 200);
      expect(payment.at, DateTime(2026, 11, 22, 15));

      final bills = (await sales.billsOfCustomer(rahimId)).reversed.toList(); // oldest first
      expect(bills[0].due, 100, reason: 'the old bill took all 200: 300 -> 100');
      expect(bills[1].due, 500, reason: 'the newer bill is untouched');
      final c = (await customers.byId(rahimId))!;
      expect(c.due, 600);
      expect(c.totalPaid, 100 + 200);
      expect(c.totalSpent, 900, reason: 'what he bought does not change');
    });

    test('a payment bigger than the oldest due spills over to the next bill', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 450);
      final bills = (await sales.billsOfCustomer(rahimId)).reversed.toList();
      expect(bills[0].due, 0);
      expect(bills[1].due, 350, reason: '300 cleared the old bill, 150 went to the new one');
      expect((await customers.byId(rahimId))!.due, 350);
    });

    test('paying everything clears the due; paying again is refused', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 800);
      final c = (await customers.byId(rahimId))!;
      expect(c.due, 0);
      expect(c.owes, isFalse);
      expect(await customers.collectPayment(rahimId, 1).then((_) => 'paid', onError: (_) => 'refused'), 'refused');
    });

    test('several payments add up, with a history, newest first', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 100);
      clock.current = DateTime(2026, 11, 23, 9);
      await customers.collectPayment(rahimId, 250);
      final history = await customers.paymentsOf(rahimId);
      expect(history.map((e) => e.amount), [250, 100]);
      expect((await customers.byId(rahimId))!.due, 450);
    });

    test('more than is owed, zero, negative or not a number: refused and nothing changes', () async {
      await rahimOwes();
      await expectLater(customers.collectPayment(rahimId, 801), throwsPayment(PaymentProblem.exceedsDue));
      await expectLater(customers.collectPayment(rahimId, 0), throwsPayment(PaymentProblem.invalidAmount));
      await expectLater(customers.collectPayment(rahimId, -5), throwsPayment(PaymentProblem.invalidAmount));
      await expectLater(customers.collectPayment(rahimId, double.nan), throwsPayment(PaymentProblem.invalidAmount));
      expect(await customers.paymentsOf(rahimId), isEmpty);
      expect((await customers.byId(rahimId))!.due, 800);
    });

    test('a customer that does not exist is refused', () async {
      await expectLater(customers.collectPayment(999, 10), throwsPayment(PaymentProblem.unknownCustomer));
    });

    test('a customer who owes nothing cannot pay', () async {
      await buy(karim, 1); // paid in full
      final id = (await customers.all()).single.id;
      await expectLater(customers.collectPayment(id, 10), throwsPayment(PaymentProblem.exceedsDue));
    });

    test("one customer's payment never touches another's bills", () async {
      await rahimOwes();
      await buy(karim, 2, paid: 0);
      final karimId = (await customers.all()).firstWhere((c) => c.name == 'করিম').id;
      await customers.collectPayment(karimId, 200);
      expect((await customers.byId(karimId))!.due, 0);
      expect((await customers.byId(rahimId))!.due, 800);
    });

    test('the daily account and the dashboard count it on the day it was collected', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 300); // 22 Nov
      clock.current = DateTime(2026, 11, 23, 11);
      await customers.collectPayment(rahimId, 100); // 23 Nov

      expect(await sales.collectedOn(DateTime(2026, 11, 22)), 300);
      expect(await sales.collectedOn(DateTime(2026, 11, 23)), 100);
      expect(await sales.collectedOn(DateTime(2026, 11, 24)), 0);

      final day = await dashboard.summary(DateTime(2026, 11, 22), DateTime(2026, 11, 23));
      expect(day.collected, 300);
      expect(day.revenue, 0, reason: 'collecting is not a new sale');
      final week = await dashboard.summary(DateTime(2026, 11, 16), DateTime(2026, 11, 24));
      expect(week.collected, 400);

      final r = await dashboard.receivables();
      expect(r.totalDue, 400, reason: 'the dashboard owed figure drops too');
    });

    test('cancelling a bill takes back the money that was collected on it', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 450); // 300 to the old bill, 150 to the new one
      final newBill = (await sales.billsOfCustomer(rahimId)).first;
      await sales.voidBill(newBill.id!);

      expect(await sales.collectedOn(DateTime(2026, 11, 22)), 300, reason: 'the 150 went back with the bill');
      final history = await customers.paymentsOf(rahimId);
      expect(history.single.amount, 300);
      expect((await customers.byId(rahimId))!.due, 0);
    });

    test('cancelling the bill that took a whole payment removes that payment', () async {
      await rahimOwes();
      await customers.collectPayment(rahimId, 100); // all to the old bill
      final oldBill = (await sales.billsOfCustomer(rahimId)).last;
      await sales.voidBill(oldBill.id!);
      expect(await customers.paymentsOf(rahimId), isEmpty);
      expect(await sales.collectedOn(DateTime(2026, 11, 22)), 0);
    });

    test('a database from before payments existed upgrades and then collects', () async {
      await rahimOwes();
      // Make it look like version 7: no payment tables.
      final db = await appDb.db;
      await db.execute('DROP TABLE payment_allocations');
      await db.execute('DROP TABLE payments');
      await db.execute('PRAGMA user_version = 7');
      await db.close();
      open();

      expect((await customers.byId(rahimId))!.due, 800, reason: 'old data is intact');
      await customers.collectPayment(rahimId, 300);
      expect((await customers.byId(rahimId))!.due, 500);
      expect(await customers.paymentsOf(rahimId), hasLength(1));
    });
  });

  group('receipt text', () {
    final payment = Payment(id: 1, customerId: 1, amount: 500, at: DateTime(2026, 11, 22, 14, 5));

    test('says what was received and what is still owed, without phone numbers or NID', () {
      const after = CustomerSummary(
        id: 1,
        name: 'রহিম',
        mobile: '01712345678',
        whatsapp: '01712345678',
        nid: '1234567890',
        due: 300,
      );
      final text = buildPaymentReceiptText(payment, after, shopName: 'আমার দোকান');
      expect(text, contains('আমার দোকান'));
      expect(text, contains('টাকা গ্রহণের রসিদ'));
      expect(text, contains('২২/১১/২০২৬ ১৪:০৫'));
      expect(text, contains('গ্রাহক: রহিম'));
      expect(text, contains('গ্রহণ: ৳৫০০'));
      expect(text, contains('এখনো বাকি: ৳৩০০'));
      expect(text, isNot(contains('01712345678')));
      expect(text, isNot(contains('1234567890')));
    });

    test('says so when nothing is left to pay', () {
      const after = CustomerSummary(id: 1, name: 'রহিম', due: 0);
      final text = buildPaymentReceiptText(payment, after, shopName: 'দোকান');
      expect(text, contains('সব বাকি পরিশোধ হয়েছে'));
      expect(text, isNot(contains('এখনো বাকি')));
    });
  });

  group('screen', () {
    late FakeCustomerRepository customers;
    late FakeSalesRepository sales;
    late FakeReceiptSender sender;

    setUp(() {
      customers = FakeCustomerRepository()
        ..summaries.add(const CustomerSummary(
          id: 1,
          name: 'রহিম',
          whatsapp: '01712345678',
          mobile: '01712345678',
          address: 'কাজিপুর',
          billCount: 2,
          totalSpent: 900,
          totalPaid: 100,
          due: 800,
        ));
      sales = FakeSalesRepository(FakeProductRepository(), FakeClock(DateTime(2026, 11, 22, 12)));
      sender = FakeReceiptSender();
    });

    Future<void> open(WidgetTester tester, {int id = 1}) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: CustomerDetailPage(
          viewModel: CustomerDetailViewModel(customers, sales),
          customerId: id,
          screens: _Screens(),
          sender: sender,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no button for a customer who owes nothing', (tester) async {
      customers.summaries[0] = const CustomerSummary(id: 1, name: 'রহিম', whatsapp: '01712345678', billCount: 1, totalSpent: 100, totalPaid: 100);
      await open(tester);
      expect(find.text(Bn.collectPayment), findsNothing);
      expect(find.text(Bn.noPayments), findsOneWidget);
    });

    testWidgets('the dialog offers the whole due; confirming takes it all', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      expect(find.text(Bn.collectTitle), findsOneWidget);
      expect(find.widgetWithText(TextField, '৮০০'), findsOneWidget, reason: 'the whole due is filled in');

      await tester.tap(find.text(Bn.collectConfirm));
      await tester.pumpAndSettle();
      expect(customers.paymentCalls, ['collect 1 800.0']);
      // The new receipt is shown at once.
      expect(find.byType(PaymentReceiptPage), findsOneWidget);
      expect(find.text('টাকা গ্রহণের রসিদ'), findsWidgets);
      expect(find.text('৳৮০০'), findsWidgets, reason: 'what was received');
      expect(find.text('সব বাকি পরিশোধ হয়েছে'), findsOneWidget);

      await tester.tap(find.text(Bn.receiptDone));
      await tester.pumpAndSettle();
      expect(find.text(Bn.collectPayment), findsNothing, reason: 'nothing left to collect');
      expect(find.text('বাকি'), findsWidgets);
      expect(find.text(Bn.noPayments), findsNothing);
    });

    testWidgets('a part payment: typed amount is taken, the rest stays due', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '৫০০');
      await tester.tap(find.text(Bn.collectConfirm));
      await tester.pumpAndSettle();

      expect(customers.paymentCalls, ['collect 1 500.0']);
      expect(find.byType(PaymentReceiptPage), findsOneWidget);
      expect(find.text('৳৫০০'), findsOneWidget, reason: 'what was received');
      expect(find.text('এখনো বাকি'), findsOneWidget);
      expect(find.text('৳৩০০'), findsOneWidget, reason: 'what is still due, on the receipt');
      await tester.tap(find.text(Bn.receiptDone));
      await tester.pumpAndSettle();
      expect(find.text('৳৩০০'), findsWidgets, reason: 'the new due is shown');
      expect(find.text(Bn.collectPayment), findsOneWidget, reason: 'still something to collect');
    });

    testWidgets('the receipt can be shared on any app too', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '500');
      await tester.tap(find.text(Bn.collectConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.text('শেয়ার'));
      await tester.pumpAndSettle();
      expect(sender.shared.single, contains('গ্রহণ: ৳৫০০'));
    });

    testWidgets('afterwards the receipt can go to the customer\'s WhatsApp', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '500');
      await tester.tap(find.text(Bn.collectConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WhatsApp'));
      await tester.pumpAndSettle();

      expect(sender.whatsApp, hasLength(1));
      expect(sender.whatsApp.single.mobile, '01712345678');
      expect(sender.whatsApp.single.message, contains('গ্রহণ: ৳৫০০'));
      expect(sender.whatsApp.single.message, contains('এখনো বাকি: ৳৩০০'));
    });

    testWidgets('a refused amount shows why and records nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '5000');
      await tester.tap(find.text(Bn.collectConfirm));
      await tester.pumpAndSettle();

      expect(find.text(Bn.payExceedsDue), findsOneWidget);
      expect(customers.payments, isEmpty);
      expect(find.text(Bn.collectPayment), findsOneWidget);
    });

    testWidgets('cancelling the dialog records nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text(Bn.collectPayment));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.cancel));
      await tester.pumpAndSettle();
      expect(customers.paymentCalls, isEmpty);
    });

    testWidgets('the payment history lists what was collected', (tester) async {
      customers.payments.add(Payment(id: 1, customerId: 1, amount: 250, at: DateTime(2026, 11, 20, 9, 30)));
      await open(tester);
      expect(find.text('৳২৫০'), findsOneWidget);
      expect(find.text('২০/১১/২০২৬ ০৯:৩০'), findsOneWidget);
    });
  });
}
