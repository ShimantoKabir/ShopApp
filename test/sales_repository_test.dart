import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real-SQL tests for restock, selling (bills), customers, due, voiding and
/// the daily query.

class SettableClock implements Clock {
  DateTime current;
  SettableClock(this.current);
  @override
  DateTime now() => current;
}

class CountingCodes implements LocationCodeGenerator {
  int _n = 0;
  @override
  String generate() => 'CODE-${_n++}';
}

Matcher throwsStock(StockProblem problem) =>
    throwsA(isA<StockException>().having((e) => e.problem, 'problem', problem));

Matcher throwsSale(SaleProblem problem) =>
    throwsA(isA<SaleException>().having((e) => e.problem, 'problem', problem));

const dbFile = 'sales_test.db';
Future<String> dbPath() async => p.join(await getDatabasesPath(), dbFile);

/// A complete customer: everything filled in, mobile and WhatsApp the same number.
const rahim = CustomerInfo(
  name: 'রহিম',
  mobile: '01712345678',
  nid: '1234567890',
  address: 'কাজিপুর, সিরাজগঞ্জ',
  whatsapp: '01712345678',
);

/// The least a sale needs: where they live and where to send the receipt.
const walkIn = CustomerInfo(address: 'বাজার রোড', whatsapp: '01911111111');

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDb;
  late SettableClock clock;
  late SqliteProductRepository products;
  late SqliteStockRepository stock;
  late SqliteSalesRepository sales;
  late SqliteCustomerRepository customers;
  late SqliteLocationRepository locations;
  late StorageLocation shelfA;
  late StorageLocation shelfB;

  void openRepositories() {
    appDb = AppDatabase(fileName: dbFile);
    products = SqliteProductRepository(appDb, clock);
    stock = SqliteStockRepository(appDb, clock);
    sales = SqliteSalesRepository(appDb, clock);
    customers = SqliteCustomerRepository(appDb, clock);
    locations = SqliteLocationRepository(appDb, CountingCodes());
  }

  setUp(() async {
    await deleteDatabase(await dbPath());
    clock = SettableClock(DateTime(2026, 11, 22, 10, 0));
    openRepositories();
    shelfA = await locations.add('তাক ক', LocationType.shelf);
    shelfB = await locations.add('তাক খ', LocationType.shelf);
  });

  tearDown(() async => (await appDb.db).close());

  Future<Product> nails({double total = 20, double cost = 80, double price = 100, List<StockPlacement> placed = const []}) =>
      products.save(Product(
        name: 'পেরেক',
        kind: ProductKind.loose,
        purchasePrice: cost,
        sellingPrice: price,
        stock: total,
        unit: 'কেজি',
        placements: placed,
      ));

  Future<Product> wire({double total = 10}) => products.save(Product(
        name: 'জিআই তার',
        kind: ProductKind.loose,
        purchasePrice: 125,
        sellingPrice: 150,
        stock: total,
        unit: 'কেজি',
      ));

  Future<Product> reload(Product x) async => (await products.byId(x.id!))!;

  /// Checkout with the minimum contact details unless a customer is given.
  Future<Bill> checkout(List<SaleLine> lines, {CustomerInfo? customer, double? paid}) =>
      sales.checkout(lines, customer: customer ?? walkIn, paid: paid);

  /// A one-line cash sale (the common case); returns that line.
  Future<Sale> sell(Product p, double qty, double price, {int? from}) async {
    final bill = await checkout([SaleLine(productId: p.id!, quantity: qty, unitPrice: price, fromLocationId: from)]);
    return bill.lines.single;
  }

  group('restock', () {
    test('adds to the total; without a location it stays "not placed"', () async {
      final n = await nails(total: 10);
      await stock.restock(n.id!, 5);
      final r = await reload(n);
      expect(r.stock, 15);
      expect(r.placements, isEmpty);
      expect(r.unplacedQuantity, 15);
    });

    test('with a location, the new goods are placed there on top of what is already there', () async {
      final n = await nails(total: 10, placed: [StockPlacement(locationId: shelfA.id!, quantity: 6)]);
      await stock.restock(n.id!, 5, locationId: shelfA.id);
      await stock.restock(n.id!, 2, locationId: shelfB.id);
      final r = await reload(n);
      expect(r.stock, 17);
      expect(r.quantityAt(shelfA.id), 11);
      expect(r.quantityAt(shelfB.id), 2);
      expect(r.unplacedQuantity, 4);
    });

    test('a new buying price replaces the old one; omitting it leaves it alone', () async {
      final n = await nails(cost: 80);
      await stock.restock(n.id!, 1, purchasePrice: 95);
      expect((await reload(n)).purchasePrice, 95);
      await stock.restock(n.id!, 1);
      expect((await reload(n)).purchasePrice, 95);
    });

    test('is recorded in the history with its location', () async {
      final n = await nails(total: 10);
      await stock.restock(n.id!, 5, locationId: shelfA.id);
      final entry = (await stock.history(n.id!)).first;
      expect([entry.reason, entry.delta, entry.locationId], [StockReason.restock, 5, shelfA.id]);
    });

    test('rejects zero/negative quantities and negative prices, changing nothing', () async {
      final n = await nails(total: 10);
      await expectLater(stock.restock(n.id!, 0), throwsStock(StockProblem.invalidQuantity));
      await expectLater(stock.restock(n.id!, -3), throwsStock(StockProblem.invalidQuantity));
      await expectLater(stock.restock(n.id!, 2, purchasePrice: -1), throwsStock(StockProblem.invalidQuantity));
      final r = await reload(n);
      expect([r.stock, r.purchasePrice], [10, 80]);
    });
  });

  group('selling (one line)', () {
    test('reduces stock and records the sale with price and cost at that moment', () async {
      final n = await nails(total: 20, cost: 80, price: 100);
      final sale = await sell(n, 3, 110);
      expect((await reload(n)).stock, 17);
      expect(sale.productName, 'পেরেক');
      expect(sale.unit, 'কেজি');
      expect([sale.quantity, sale.unitPrice, sale.unitCost], [3, 110, 80]);
      expect([sale.total, sale.cost, sale.profit], [330, 240, 90]);
      expect(sale.at, clock.current);
      expect(sale.id, isNotNull);
      expect(sale.billId, isNotNull);
    });

    test('later price changes never alter a recorded sale', () async {
      final n = await nails(cost: 80, price: 100);
      await sell(n, 1, 100);
      await products.save((await reload(n)).copyWith(purchasePrice: 200, sellingPrice: 300));
      final recorded = (await sales.billsOn(clock.current)).single.lines.single;
      expect([recorded.unitPrice, recorded.unitCost], [100, 80]);
    });

    test('fractional quantities work (half a kilo)', () async {
      final n = await nails(total: 2);
      await sell(n, 0.5, 100);
      expect((await reload(n)).stock, 1.5);
    });

    test('selling everything leaves exactly zero', () async {
      final n = await nails(total: 4);
      await sell(n, 4, 100);
      expect((await reload(n)).stock, 0);
    });

    test('cannot sell more than is in stock; nothing is recorded or changed', () async {
      final n = await nails(total: 5);
      await expectLater(sell(n, 6, 100), throwsStock(StockProblem.insufficientStock));
      expect((await reload(n)).stock, 5);
      expect(await sales.billsOn(clock.current), isEmpty);
      expect((await stock.history(n.id!)).every((e) => e.reason != StockReason.sale), isTrue);
    });

    test('rejects zero/negative quantity and negative price', () async {
      final n = await nails();
      await expectLater(sell(n, 0, 100), throwsStock(StockProblem.invalidQuantity));
      await expectLater(sell(n, -1, 100), throwsStock(StockProblem.invalidQuantity));
      await expectLater(sell(n, 1, -5), throwsStock(StockProblem.invalidQuantity));
    });

    test('takes stock that is not placed anywhere first', () async {
      final n = await nails(total: 20, placed: [
        StockPlacement(locationId: shelfA.id!, quantity: 10),
        StockPlacement(locationId: shelfB.id!, quantity: 5),
      ]); // 5 unplaced
      final sale = await sell(n, 3, 100);
      final r = await reload(n);
      expect(r.stock, 17);
      expect(r.quantityAt(shelfA.id), 10, reason: 'shelves untouched');
      expect(r.quantityAt(shelfB.id), 5);
      expect(sale.locationId, isNull);
    });

    test('once the unplaced stock is used up, takes from the biggest location first', () async {
      final n = await nails(total: 20, placed: [
        StockPlacement(locationId: shelfA.id!, quantity: 10),
        StockPlacement(locationId: shelfB.id!, quantity: 5),
      ]);
      await sell(n, 8, 100); // 5 unplaced + 3 from shelf A
      final r = await reload(n);
      expect(r.stock, 12);
      expect(r.unplacedQuantity, 0);
      expect(r.quantityAt(shelfA.id), 7);
      expect(r.quantityAt(shelfB.id), 5);
    });

    test('a sale that came from exactly one location remembers it', () async {
      final n = await nails(total: 10, placed: [StockPlacement(locationId: shelfA.id!, quantity: 10)]);
      final sale = await sell(n, 4, 100);
      expect(sale.locationId, shelfA.id);
      expect((await reload(n)).quantityAt(shelfA.id), 6);
    });

    test('can sell from a chosen location; it must hold enough', () async {
      final n = await nails(total: 20, placed: [
        StockPlacement(locationId: shelfA.id!, quantity: 4),
        StockPlacement(locationId: shelfB.id!, quantity: 6),
      ]);
      await sell(n, 5, 100, from: shelfB.id);
      var r = await reload(n);
      expect(r.quantityAt(shelfB.id), 1);
      expect(r.quantityAt(shelfA.id), 4);
      expect(r.stock, 15);

      await expectLater(sell(n, 2, 100, from: shelfB.id), throwsStock(StockProblem.notEnoughAtSource));
      r = await reload(n);
      expect(r.stock, 15, reason: 'failed sale changes nothing');
    });

    test('placed stock never exceeds the total, whatever the mix of sales', () async {
      final n = await nails(total: 9, placed: [
        StockPlacement(locationId: shelfA.id!, quantity: 4),
        StockPlacement(locationId: shelfB.id!, quantity: 3),
      ]); // 2 unplaced
      for (var i = 0; i < 9; i++) {
        await sell(n, 1, 100);
        final r = await reload(n);
        expect(r.placedQuantity, lessThanOrEqualTo(r.stock + stockEpsilon), reason: 'after sale ${i + 1}');
        expect(r.stock, 8 - i);
      }
      expect((await reload(n)).placements, isEmpty);
    });

    test('is written to the history as a negative entry', () async {
      final n = await nails(total: 10);
      await sell(n, 3, 100);
      final e = (await stock.history(n.id!)).first;
      expect([e.reason, e.delta], [StockReason.sale, -3]);
    });

    test('deleting a product keeps its sales history', () async {
      final n = await nails();
      await sell(n, 2, 100);
      await products.delete(n.id!);
      final kept = (await sales.billsOn(clock.current)).single.lines.single;
      expect(kept.productId, isNull);
      expect(kept.productName, 'পেরেক');
      expect(kept.total, 200);
    });
  });

  group('bills with several items', () {
    test('one bill holds every line; stock drops for each product; total adds up', () async {
      final n = await nails(total: 20);
      final w = await wire(total: 10);
      final bill = await checkout([
        SaleLine(productId: n.id!, quantity: 2, unitPrice: 100),
        SaleLine(productId: w.id!, quantity: 1.5, unitPrice: 150),
      ]);
      expect(bill.lines, hasLength(2));
      expect(bill.total, 200 + 225);
      expect(bill.paid, bill.total, reason: 'paid in full by default');
      expect(bill.due, 0);
      expect(bill.lines.every((l) => l.billId == bill.id), isTrue);
      expect((await reload(n)).stock, 18);
      expect((await reload(w)).stock, 8.5);
      expect(await sales.billsOn(clock.current), hasLength(1), reason: 'one bill, not two');
    });

    test('it is all-or-nothing: if one line cannot be sold, none are', () async {
      final n = await nails(total: 20);
      final w = await wire(total: 1);
      await expectLater(
        checkout([
          SaleLine(productId: n.id!, quantity: 2, unitPrice: 100),
          SaleLine(productId: w.id!, quantity: 5, unitPrice: 150), // only 1 in stock
        ]),
        throwsStock(StockProblem.insufficientStock),
      );
      expect((await reload(n)).stock, 20, reason: 'the first line was rolled back');
      expect((await reload(w)).stock, 1);
      expect(await sales.billsOn(clock.current), isEmpty);
      expect((await stock.history(n.id!)).every((e) => e.reason != StockReason.sale), isTrue);
    });

    test('the same product twice on one bill is checked against what is left, not the original stock', () async {
      final n = await nails(total: 5);
      await expectLater(
        checkout([
          SaleLine(productId: n.id!, quantity: 3, unitPrice: 100),
          SaleLine(productId: n.id!, quantity: 3, unitPrice: 100),
        ]),
        throwsStock(StockProblem.insufficientStock),
      );
      expect((await reload(n)).stock, 5);
    });

    test('an empty bill is refused', () async {
      await expectLater(checkout(const []), throwsSale(SaleProblem.emptyBill));
    });

    test('billById returns the bill with its lines, or null', () async {
      final n = await nails();
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 2, unitPrice: 100)]);
      final read = (await sales.billById(bill.id!))!;
      expect(read.lines.single.productName, 'পেরেক');
      expect(read.total, 200);
      expect(await sales.billById(99999), isNull);
    });
  });

  group('contact details (every sale)', () {
    late Product n;
    setUp(() async => n = await nails(total: 20));
    SaleLine line() => SaleLine(productId: n.id!, quantity: 2, unitPrice: 100);

    test('customer details are optional on a paid sale: with none at all it is a plain retail sale and nobody is saved', () async {
      for (final nothing in const [null, CustomerInfo(), CustomerInfo(whatsapp: '  ')]) {
        final bill = await sales.checkout([line()], customer: nothing);
        expect((bill.customerId, bill.customerWhatsApp, bill.due), (null, '', 0));
      }
      expect(await customers.all(), isEmpty, reason: 'no number, so no one to remember');
    });

    test('a WhatsApp number alone is enough for a paid sale (no address, no name)', () async {
      final bill = await sales.checkout([line()], customer: const CustomerInfo(whatsapp: '01911111111'));
      expect(bill.customerWhatsApp, '01911111111');
      expect(bill.customerAddress, '');
      expect(bill.due, 0);
    });

    test('a known address is not wiped by a later sale that leaves it out', () async {
      await sales.checkout([line()], customer: const CustomerInfo(whatsapp: '01911111111', address: 'বাজার রোড'));
      await sales.checkout([line()], customer: const CustomerInfo(whatsapp: '01911111111'));
      final known = await customers.findByPhone('01911111111');
      expect(known!.address, 'বাজার রোড');
    });

    test('a due sale also needs the address: each missing piece is refused', () async {
      const complete = CustomerInfo(
        name: 'রহিম',
        mobile: '01712345678',
        nid: '1234567890',
        address: 'কাজিপুর',
        whatsapp: '01712345678',
      );
      for (final incomplete in const [
        CustomerInfo(mobile: '01712345678', nid: '1234567890', address: 'কাজিপুর', whatsapp: '01712345678'), // no name
        CustomerInfo(name: 'রহিম', nid: '1234567890', address: 'কাজিপুর'), // no number to reach them on
        CustomerInfo(name: 'রহিম', mobile: '01712345678', address: 'কাজিপুর', whatsapp: '01712345678'), // no NID
        CustomerInfo(name: 'রহিম', mobile: '01712345678', nid: '1234567890', whatsapp: '01712345678'), // no address
      ]) {
        await expectLater(
          sales.checkout([line()], customer: incomplete, paid: 0),
          throwsSale(SaleProblem.customerRequiredForDue),
        );
      }
      final ok = await sales.checkout([line()], customer: complete, paid: 0);
      expect(ok.due, 200);
    });

    test('the WhatsApp number must be a real mobile number', () async {
      for (final bad in ['12345', '01212345678', '0171234567', '017123456789']) {
        await expectLater(
          sales.checkout([line()], customer: CustomerInfo(address: 'বাজার রোড', whatsapp: bad)),
          throwsSale(SaleProblem.invalidCustomer),
          reason: bad,
        );
      }
    });

    test('text with no digits at all counts as no number', () async {
      final bill = await sales.checkout([line()], customer: const CustomerInfo(address: 'বাজার রোড', whatsapp: 'abc'));
      expect((bill.customerWhatsApp, bill.customerId), ('', null));
    });

    test('one number is enough for a due sale, given as the mobile or as the WhatsApp number', () async {
      for (final number in const [
        CustomerInfo(name: 'রহিম', mobile: '01712345678', nid: '1234567890', address: 'কাজিপুর'),
        CustomerInfo(name: 'করিম', nid: '1234567890', address: 'কাজিপুর', whatsapp: '01812345678'),
        CustomerInfo(name: 'সালমা', mobile: '01912345678', nid: '1234567890', address: 'কাজিপুর', whatsapp: '01912345678'),
      ]) {
        final bill = await sales.checkout([line()], customer: number, paid: 0);
        expect(bill.due, 200, reason: number.name);
        expect(bill.customerId, isNotNull);
      }
    });

    test('with just an address and a WhatsApp number the sale goes through (name, mobile, NID are optional)', () async {
      final bill = await sales.checkout([line()], customer: walkIn);
      expect(bill.customerAddress, 'বাজার রোড');
      expect(bill.customerWhatsApp, '01911111111');
      expect(bill.customerName, '');
      expect(bill.customerMobile, '');
      expect(bill.due, 0);
    });

    test('they are stored on the bill (as a copy) and on the customer record', () async {
      final bill = await sales.checkout([line()], customer: rahim);
      final read = (await sales.billById(bill.id!))!;
      expect(read.customerAddress, 'কাজিপুর, সিরাজগঞ্জ');
      expect(read.customerWhatsApp, '01712345678');
      final found = (await customers.findByPhone('01712345678'))!;
      expect(found.address, 'কাজিপুর, সিরাজগঞ্জ');
      expect(found.whatsapp, '01712345678');
    });

    test('a WhatsApp number may differ from the mobile number', () async {
      final bill = await sales.checkout(
        [line()],
        customer: const CustomerInfo(address: 'বাজার', whatsapp: '01911111111', mobile: '01812345678'),
      );
      expect(bill.customerMobile, '01812345678');
      expect(bill.customerWhatsApp, '01911111111');
    });

    test('numbers typed in Bangla digits or with +880 are stored in the standard form', () async {
      final bill = await sales.checkout(
        [line()],
        customer: const CustomerInfo(address: 'বাজার', whatsapp: '+৮৮০ ১৯১১-১১১১১১'),
      );
      expect(bill.customerWhatsApp, '01911111111');
    });

    test('a mobile or NID that is given must be valid, even on a cash sale', () async {
      await expectLater(
        sales.checkout([line()], customer: const CustomerInfo(address: 'x', whatsapp: '01911111111', mobile: '999')),
        throwsSale(SaleProblem.invalidCustomer),
      );
      await expectLater(
        sales.checkout([line()], customer: const CustomerInfo(address: 'x', whatsapp: '01911111111', nid: '12')),
        throwsSale(SaleProblem.invalidCustomer),
      );
    });
  });

  group('payment and due', () {
    late Product n;
    setUp(() async => n = await nails(total: 20));
    SaleLine line() => SaleLine(productId: n.id!, quantity: 2, unitPrice: 100); // total 200

    test('paid in full by default', () async {
      final bill = await checkout([line()]);
      expect(bill.paid, 200);
      expect(bill.due, 0);
    });

    test('part-paid (due) with a complete customer works; the due is the unpaid part', () async {
      final bill = await checkout([line()], customer: rahim, paid: 50);
      expect(bill.paid, 50);
      expect(bill.due, 150);
      expect(bill.customerName, 'রহিম');
      expect(bill.customerMobile, '01712345678');
      expect(bill.customerId, isNotNull);
    });

    test('nothing paid at all is a valid due sale', () async {
      final bill = await checkout([line()], customer: rahim, paid: 0);
      expect(bill.due, 200);
    });

    test('a due sale ALSO needs name, mobile and NID: each missing piece is refused, nothing is saved', () async {
      for (final incomplete in const [
        walkIn, // address + WhatsApp only: fine for cash, not for due
        CustomerInfo(mobile: '01712345678', nid: '1234567890', address: 'x', whatsapp: '01911111111'), // no name
        CustomerInfo(name: 'রহিম', nid: '1234567890', address: 'x'), // no number at all
        CustomerInfo(name: 'রহিম', mobile: '01712345678', address: 'x', whatsapp: '01911111111'), // no NID
        CustomerInfo(name: '   ', mobile: '01712345678', nid: '1234567890', address: 'x', whatsapp: '01911111111'), // blank name
      ]) {
        await expectLater(
          sales.checkout([line()], customer: incomplete, paid: 50),
          throwsSale(SaleProblem.customerRequiredForDue),
        );
      }
      expect((await reload(n)).stock, 20);
      expect(await sales.billsOn(clock.current), isEmpty);
    });

    test('a due sale with an INVALID mobile or NID is refused (as invalid details)', () async {
      await expectLater(
        sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম', mobile: '12345', nid: '1234567890', address: 'x', whatsapp: '01911111111'), paid: 50),
        throwsSale(SaleProblem.invalidCustomer),
      );
      await expectLater(
        sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম', mobile: '01712345678', nid: '123', address: 'x', whatsapp: '01911111111'), paid: 50),
        throwsSale(SaleProblem.invalidCustomer),
      );
      expect((await reload(n)).stock, 20);
    });

    test('paid more than the total, or a negative amount, is refused', () async {
      await expectLater(checkout([line()], paid: 201), throwsSale(SaleProblem.invalidPayment));
      await expectLater(checkout([line()], paid: -1), throwsSale(SaleProblem.invalidPayment));
    });

    test('a cash sale may also give a name', () async {
      final bill = await checkout([line()], customer: const CustomerInfo(name: 'করিম', address: 'বাজার', whatsapp: '01911111111'));
      expect(bill.customerName, 'করিম');
      expect(bill.due, 0);
    });
  });

  group('customers', () {
    late Product n;
    setUp(() async => n = await nails(total: 100));
    SaleLine line() => SaleLine(productId: n.id!, quantity: 1, unitPrice: 100);

    test('a customer is found again by WhatsApp number or by mobile, written any way', () async {
      await sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম', address: 'কাজিপুর', whatsapp: '01911111111', mobile: '01812345678', nid: '1234567890'));
      for (final input in ['01911111111', '০১৯১১১১১১১১', '+8801911111111', '01812345678', '8801812345678']) {
        final found = await customers.findByPhone(input);
        expect(found, isNotNull, reason: input);
        expect(found!.name, 'রহিম', reason: input);
        expect(found.address, 'কাজিপুর');
        expect(found.nid, '1234567890');
      }
    });

    test('the same WhatsApp number is one customer; newer details replace older ones, nothing is blanked', () async {
      final first = await sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম', address: 'পুরনো ঠিকানা', whatsapp: '01911111111'));
      final second = await sales.checkout(
        [line()],
        customer: const CustomerInfo(address: 'নতুন ঠিকানা', whatsapp: '8801911111111', nid: '1234567890'), // no name this time
      );
      expect(second.customerId, first.customerId);
      final found = (await customers.findByPhone('01911111111'))!;
      expect(found.name, 'রহিম', reason: 'the earlier name is kept');
      expect(found.address, 'নতুন ঠিকানা', reason: 'the address is brought up to date');
      expect(found.nid, '1234567890', reason: 'the NID given later is added');
    });

    test('a different WhatsApp number is a different customer', () async {
      final a = await sales.checkout([line()], customer: const CustomerInfo(address: 'ক', whatsapp: '01911111111'));
      final b = await sales.checkout([line()], customer: const CustomerInfo(address: 'খ', whatsapp: '01922222222'));
      expect(a.customerId, isNot(b.customerId));
    });

    test('findByPhone returns null for an unknown or empty number', () async {
      expect(await customers.findByPhone('01999999999'), isNull);
      expect(await customers.findByPhone(''), isNull);
    });

    test('the bill keeps its own copy of the details (a receipt never changes)', () async {
      final first = await sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম', address: 'পুরনো', whatsapp: '01911111111'));
      await sales.checkout([line()], customer: const CustomerInfo(name: 'রহিম উদ্দিন', address: 'নতুন', whatsapp: '01911111111'));
      final read = (await sales.billById(first.id!))!;
      expect(read.customerName, 'রহিম');
      expect(read.customerAddress, 'পুরনো');
    });
  });

  group('voiding a bill', () {
    test('returns the units to stock and to the location they came from', () async {
      final n = await nails(total: 10, placed: [StockPlacement(locationId: shelfA.id!, quantity: 10)]);
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 4, unitPrice: 100)]);
      await sales.voidBill(bill.id!);
      final r = await reload(n);
      expect(r.stock, 10);
      expect(r.quantityAt(shelfA.id), 10);
      expect(await sales.billsOn(clock.current), isEmpty);
      expect((await stock.history(n.id!)).first.reason, StockReason.saleVoid);
    });

    test('a bill with several items gives every item back', () async {
      final n = await nails(total: 20);
      final w = await wire(total: 10);
      final bill = await checkout([
        SaleLine(productId: n.id!, quantity: 2, unitPrice: 100),
        SaleLine(productId: w.id!, quantity: 3, unitPrice: 150),
      ]);
      await sales.voidBill(bill.id!);
      expect((await reload(n)).stock, 20);
      expect((await reload(w)).stock, 10);
      expect(await sales.billById(bill.id!), isNull);
    });

    test('a sale taken from several places returns to "not placed"', () async {
      final n = await nails(total: 20, placed: [StockPlacement(locationId: shelfA.id!, quantity: 10)]); // 10 unplaced
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 12, unitPrice: 100)]); // 10 unplaced + 2 from A
      await sales.voidBill(bill.id!);
      final r = await reload(n);
      expect(r.stock, 20);
      expect(r.quantityAt(shelfA.id), 8, reason: 'shelf A is not topped up again');
      expect(r.unplacedQuantity, 12);
    });

    test('voiding the same bill twice is harmless', () async {
      final n = await nails(total: 10);
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 4, unitPrice: 100)]);
      await sales.voidBill(bill.id!);
      await sales.voidBill(bill.id!);
      expect((await reload(n)).stock, 10, reason: 'not returned twice');
    });

    test('works even if the location was deleted after the sale', () async {
      final n = await nails(total: 5, placed: [StockPlacement(locationId: shelfA.id!, quantity: 5)]);
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 5, unitPrice: 100)]); // shelf A now empty
      await locations.delete(shelfA.id!);
      await sales.voidBill(bill.id!);
      final r = await reload(n);
      expect(r.stock, 5);
      expect(r.placements, isEmpty);
    });

    test('voiding a due bill keeps the customer record', () async {
      final n = await nails(total: 10);
      final bill = await checkout([SaleLine(productId: n.id!, quantity: 2, unitPrice: 100)], customer: rahim, paid: 0);
      await sales.voidBill(bill.id!);
      expect(await customers.findByPhone('01712345678'), isNotNull);
    });
  });

  group('bills of a day', () {
    test('returns only that calendar day, newest first, including its edges', () async {
      final n = await nails(total: 50);
      Future<void> sellAt(DateTime t, double q) async {
        clock.current = t;
        await sell(n, q, 100);
      }

      await sellAt(DateTime(2026, 11, 21, 23, 59, 59), 1); // yesterday
      await sellAt(DateTime(2026, 11, 22, 0, 0, 0), 2); // today, first moment
      await sellAt(DateTime(2026, 11, 22, 18, 30), 3); // today, evening
      await sellAt(DateTime(2026, 11, 23, 0, 0, 0), 4); // tomorrow

      final today = await sales.billsOn(DateTime(2026, 11, 22, 12));
      expect(today.map((b) => b.lines.single.quantity), [3, 2]);
      expect((await sales.billsOn(DateTime(2026, 11, 21))).map((b) => b.lines.single.quantity), [1]);
      expect((await sales.billsOn(DateTime(2026, 11, 23))).map((b) => b.lines.single.quantity), [4]);
      expect(await sales.billsOn(DateTime(2026, 11, 25)), isEmpty);
    });

    test('DaySummary adds up revenue, cost, profit and what is still due', () async {
      final n = await nails(total: 50, cost: 80);
      await checkout([SaleLine(productId: n.id!, quantity: 2, unitPrice: 100)]); // 200 / cost 160, paid
      await checkout([SaleLine(productId: n.id!, quantity: 1, unitPrice: 90)], customer: rahim, paid: 30); // 90 / cost 80, due 60
      final summary = DaySummary.of(await sales.billsOn(clock.current));
      expect(summary.saleCount, 2, reason: 'counts bills');
      expect(summary.revenue, 290);
      expect(summary.cost, 240);
      expect(summary.profit, 50);
      expect(summary.due, 60);
    });

    test('an empty day summarizes to zeros', () {
      final s = DaySummary.of(const []);
      expect([s.saleCount, s.revenue, s.cost, s.profit, s.due], [0, 0, 0, 0, 0]);
    });
  });

  group('migration', () {
    Future<void> createOld({required int version, required bool withSale}) async {
      await (await appDb.db).close();
      await deleteDatabase(await dbPath());
      final old = await databaseFactory.openDatabase(
        await dbPath(),
        options: OpenDatabaseOptions(
          version: version,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
            await d.execute('''CREATE TABLE locations(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'shelf', code TEXT NOT NULL UNIQUE)''');
            await d.execute('''CREATE TABLE products(
              id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'standard',
              category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
              brand TEXT NOT NULL DEFAULT '', size TEXT NOT NULL DEFAULT '', model TEXT NOT NULL DEFAULT '',
              finish TEXT NOT NULL DEFAULT '', purchase_price REAL NOT NULL, selling_price REAL NOT NULL,
              stock REAL NOT NULL, unit TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE stock_placements(
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
              quantity REAL NOT NULL, PRIMARY KEY(product_id, location_id))''');
            await d.execute('''CREATE TABLE stock_log(id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
              delta REAL NOT NULL, reason TEXT NOT NULL, at INTEGER NOT NULL)''');
            await d.insert('products', {
              'name': 'পুরনো', 'purchase_price': 10.0, 'selling_price': 15.0, 'stock': 7.0, 'unit': 'পিস', 'updated_at': 1,
            });
            if (version >= 5) {
              // v5 shape: one row per sale, no bill.
              await d.execute('''CREATE TABLE sales(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
                product_name TEXT NOT NULL, unit TEXT NOT NULL,
                location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
                quantity REAL NOT NULL, unit_price REAL NOT NULL, unit_cost REAL NOT NULL, at INTEGER NOT NULL)''');
              if (withSale) {
                await d.insert('sales', {
                  'product_id': 1, 'product_name': 'পুরনো', 'unit': 'পিস', 'quantity': 2.0,
                  'unit_price': 15.0, 'unit_cost': 10.0, 'at': DateTime(2026, 11, 22, 9).millisecondsSinceEpoch,
                });
              }
            }
          },
        ),
      );
      await old.close();
      openRepositories();
    }

    test('v5 -> v6: every existing sale gets its own fully-paid bill, shown in the day list', () async {
      await createOld(version: 5, withSale: true);
      final bills = await sales.billsOn(DateTime(2026, 11, 22));
      expect(bills, hasLength(1));
      final bill = bills.single;
      expect(bill.lines.single.productName, 'পুরনো');
      expect(bill.total, 30);
      expect(bill.paid, 30);
      expect(bill.due, 0);
      expect(bill.hasCustomer, isFalse);
      expect(bill.lines.single.billId, bill.id);
    });

    test('v5 -> v6: voiding a migrated sale still returns its stock', () async {
      await createOld(version: 5, withSale: true);
      final bill = (await sales.billsOn(DateTime(2026, 11, 22))).single;
      await sales.voidBill(bill.id!);
      expect((await products.search()).single.stock, 9, reason: '7 + the 2 that were sold');
    });

    test('v5 -> v6: new bills (with a customer and due) work on the migrated database', () async {
      await createOld(version: 5, withSale: false);
      final product = (await products.search()).single;
      final bill = await checkout(
        [SaleLine(productId: product.id!, quantity: 2, unitPrice: 15)],
        customer: rahim,
        paid: 10,
      );
      expect(bill.due, 20);
      expect((await customers.findByPhone('01712345678'))!.name, 'রহিম');
    });

    test('v6 -> v7: old bills and customers keep working without an address or WhatsApp number; new sales need them', () async {
      await (await appDb.db).close();
      await deleteDatabase(await dbPath());
      final old = await databaseFactory.openDatabase(
        await dbPath(),
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
            await d.execute('''CREATE TABLE locations(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'shelf', code TEXT NOT NULL UNIQUE)''');
            await d.execute('''CREATE TABLE products(
              id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'standard',
              category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
              brand TEXT NOT NULL DEFAULT '', size TEXT NOT NULL DEFAULT '', model TEXT NOT NULL DEFAULT '',
              finish TEXT NOT NULL DEFAULT '', purchase_price REAL NOT NULL, selling_price REAL NOT NULL,
              stock REAL NOT NULL, unit TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE stock_placements(
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
              quantity REAL NOT NULL, PRIMARY KEY(product_id, location_id))''');
            await d.execute('''CREATE TABLE stock_log(id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
              location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
              delta REAL NOT NULL, reason TEXT NOT NULL, at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL DEFAULT '', mobile TEXT NOT NULL DEFAULT '', nid TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE bills(id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
              customer_name TEXT NOT NULL DEFAULT '', customer_mobile TEXT NOT NULL DEFAULT '',
              paid REAL NOT NULL, at INTEGER NOT NULL)''');
            await d.execute('''CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT,
              bill_id INTEGER REFERENCES bills(id) ON DELETE CASCADE,
              product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
              product_name TEXT NOT NULL, unit TEXT NOT NULL,
              location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
              quantity REAL NOT NULL, unit_price REAL NOT NULL, unit_cost REAL NOT NULL, at INTEGER NOT NULL)''');
            await d.insert('products', {
              'name': 'পুরনো', 'purchase_price': 10.0, 'selling_price': 15.0, 'stock': 7.0, 'unit': 'পিস', 'updated_at': 1,
            });
            await d.insert('customers', {'name': 'পুরনো গ্রাহক', 'mobile': '01712345678', 'nid': '1234567890', 'created_at': 1});
            await d.insert('bills', {
              'customer_id': 1, 'customer_name': 'পুরনো গ্রাহক', 'customer_mobile': '01712345678',
              'paid': 10.0, 'at': DateTime(2026, 11, 22, 9).millisecondsSinceEpoch,
            });
            await d.insert('sales', {
              'bill_id': 1, 'product_id': 1, 'product_name': 'পুরনো', 'unit': 'পিস', 'quantity': 2.0,
              'unit_price': 15.0, 'unit_cost': 10.0, 'at': DateTime(2026, 11, 22, 9).millisecondsSinceEpoch,
            });
          },
        ),
      );
      await old.close();
      openRepositories();

      final oldBill = (await sales.billsOn(DateTime(2026, 11, 22))).single;
      expect(oldBill.customerName, 'পুরনো গ্রাহক');
      expect(oldBill.customerAddress, '', reason: 'older bills have none');
      expect(oldBill.customerWhatsApp, '');
      expect(oldBill.due, 20, reason: '30 total - 10 paid');

      final product = (await products.search()).single;
      final walkIn = await sales.checkout([SaleLine(productId: product.id!, quantity: 1, unitPrice: 15)]);
      expect((walkIn.customerId, walkIn.due), (null, 0), reason: 'details are optional on a paid sale now');

      // The old customer (known by mobile only) is recognised, and gains the new details.
      final next = await sales.checkout(
        [SaleLine(productId: product.id!, quantity: 1, unitPrice: 15)],
        customer: const CustomerInfo(address: 'নতুন ঠিকানা', whatsapp: '01812345678', mobile: '01712345678'),
      );
      expect(next.customerId, 1, reason: 'matched the existing record by mobile');
      final found = (await customers.findByPhone('01812345678'))!;
      expect(found.name, 'পুরনো গ্রাহক');
      expect(found.nid, '1234567890');
      expect(found.address, 'নতুন ঠিকানা');
    });

    test('v4 -> v6 (no sales table yet): billing works', () async {
      await createOld(version: 4, withSale: false);
      final product = (await products.search()).single;
      final bill = await checkout([SaleLine(productId: product.id!, quantity: 1, unitPrice: 15)]);
      expect(bill.total, 15);
      expect((await sales.billsOn(clock.current)), hasLength(1));
    });
  });
}
