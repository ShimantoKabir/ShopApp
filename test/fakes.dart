import 'package:hardware_shop/domain/customers.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/payments.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/stock.dart';

/// In-memory fakes shared by tests. They implement the same abstractions the
/// app depends on, which is what dependency injection makes possible.
class FakeProductRepository implements ProductRepository {
  final List<Product> items;
  int _nextId = 1000;
  FakeProductRepository([List<Product>? items]) : items = items ?? [];

  @override
  Future<List<Product>> search({
    String query = '',
    int? categoryId,
    int? locationId,
    ProductKind? kind,
  }) async =>
      items
          .where((p) =>
              p.name.contains(query) &&
              (categoryId == null || p.categoryId == categoryId) &&
              (locationId == null || p.quantityAt(locationId) > 0) &&
              (kind == null || p.kind == kind))
          .toList();

  @override
  Future<Product?> byId(int id) async => items.where((p) => p.id == id).firstOrNull;

  @override
  Future<bool> existsSimilar({
    required String name,
    String brand = '',
    String size = '',
    int? excludeId,
  }) async =>
      items.any((p) =>
          p.id != excludeId &&
          p.name.toLowerCase() == name.trim().toLowerCase() &&
          p.brand.toLowerCase() == brand.trim().toLowerCase() &&
          p.size.toLowerCase() == size.trim().toLowerCase());

  @override
  Future<Product> save(Product product) async {
    if (product.id != null) {
      // Same rule as the real repository: total can't go below what is placed.
      final existing = items.where((p) => p.id == product.id).firstOrNull;
      if (existing != null && product.stock + stockEpsilon < existing.placedQuantity) {
        throw const StockException(StockProblem.belowPlaced);
      }
      product = product.copyWith(placements: existing?.placements);
    }
    final saved = product.id == null ? product.copyWith(id: _nextId++) : product;
    items.removeWhere((p) => p.id == saved.id);
    items.add(saved);
    return saved;
  }

  @override
  Future<void> delete(int id) async => items.removeWhere((p) => p.id == id);

  @override
  Future<void> adjustStock(int id, double newTotal) async {
    final i = items.indexWhere((p) => p.id == id);
    if (newTotal + stockEpsilon < items[i].placedQuantity) throw const StockException(StockProblem.belowPlaced);
    items[i] = items[i].copyWith(stock: newTotal);
  }
}

/// Records what the view models ask of it. The real rules are tested against
/// real SQL in sqlite_repositories_test.dart.
class FakeStockRepository implements StockRepository {
  final List<String> calls = [];
  StockException? failWith;

  void _record(String call) {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<StockPlacement>> placements(int productId) async => const [];

  @override
  Future<void> place(int productId, int locationId, double quantity) async =>
      _record('place $productId $locationId $quantity');

  @override
  Future<void> recount(int productId, int locationId, double quantity) async =>
      _record('recount $productId $locationId $quantity');

  @override
  Future<void> move(int productId, int fromLocationId, int toLocationId, double quantity) async =>
      _record('move $productId $fromLocationId $toLocationId $quantity');

  @override
  Future<void> restock(int productId, double quantity, {int? locationId, double? purchasePrice}) async =>
      _record('restock $productId $quantity $locationId $purchasePrice');

  @override
  Future<List<StockLogEntry>> history(int productId, {int limit = 30}) async => [
        StockLogEntry(productId: productId, delta: 5, reason: StockReason.initial, at: DateTime(2026, 11, 22, 15, 35)),
      ];
}

class FakeClock implements Clock {
  DateTime current;
  FakeClock(this.current);
  @override
  DateTime now() => current;
}

/// Sells against the in-memory product store, so screens see stock go down.
/// (The real rules are tested against SQL in sales_repository_test.dart.)
class FakeSalesRepository implements SalesRepository {
  final FakeProductRepository products;
  final FakeClock clock;
  final List<Bill> bills = [];
  final List<String> calls = [];

  /// Thrown by the next checkout, to test how screens show a refused sale.
  Object? failWith;
  int _billId = 1;
  int _saleId = 1;

  FakeSalesRepository(this.products, this.clock);

  /// What the daily account shows as collected.
  double collected = 0;

  @override
  Future<double> collectedOn(DateTime day) async => collected;

  @override
  Future<List<Bill>> billsOfCustomer(int customerId) async =>
      bills.where((b) => b.customerId == customerId).toList().reversed.toList();

  @override
  Future<Bill> checkout(List<SaleLine> lines, {CustomerInfo? customer, double? paid}) async {
    calls.add('checkout ${lines.map((l) => '${l.productId}x${l.quantity}@${l.unitPrice}').join(',')} '
        'paid=$paid name=${customer?.name} mobile=${customer?.mobile} nid=${customer?.nid} '
        'address=${customer?.address} whatsapp=${customer?.whatsapp}');
    if (failWith != null) throw failWith!;
    final sold = <Sale>[];
    for (final l in lines) {
      final i = products.items.indexWhere((p) => p.id == l.productId);
      final p = products.items[i];
      if (l.quantity > p.stock) throw const StockException(StockProblem.insufficientStock);
      products.items[i] = p.copyWith(stock: p.stock - l.quantity);
      sold.add(Sale(
        id: _saleId++,
        billId: _billId,
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        unitCost: p.purchasePrice,
        at: clock.current,
      ));
    }
    final total = sold.fold(0.0, (sum, s) => sum + s.total);
    final bill = Bill(
      id: _billId++,
      customerName: customer?.name.trim() ?? '',
      customerMobile: customer?.mobile ?? '',
      customerAddress: customer?.address ?? '',
      customerWhatsApp: customer?.whatsapp ?? '',
      paid: paid ?? total,
      at: clock.current,
      lines: sold,
    );
    bills.add(bill);
    return bill;
  }

  @override
  Future<void> voidBill(int billId) async {
    calls.add('void $billId');
    final bill = bills.where((b) => b.id == billId).firstOrNull;
    if (bill == null) return;
    bills.remove(bill);
    for (final l in bill.lines) {
      final i = products.items.indexWhere((p) => p.id == l.productId);
      if (i != -1) products.items[i] = products.items[i].copyWith(stock: products.items[i].stock + l.quantity);
    }
  }

  @override
  Future<List<Bill>> billsOn(DateTime day) async => bills
      .where((b) => b.at.year == day.year && b.at.month == day.month && b.at.day == day.day)
      .toList()
      .reversed
      .toList();

  @override
  Future<Bill?> billById(int id) async => bills.where((b) => b.id == id).firstOrNull;
}

class FakeCustomerRepository implements CustomerRepository {
  final Map<String, CustomerInfo> known;
  FakeCustomerRepository([Map<String, CustomerInfo>? known]) : known = known ?? {};

  @override
  Future<CustomerInfo?> findByPhone(String number) async => known[number];

  /// Customers shown by the list and detail screens.
  final List<CustomerSummary> summaries = [];

  @override
  Future<List<CustomerSummary>> all() async => List.of(summaries);

  @override
  Future<CustomerSummary?> byId(int id) async => summaries.where((c) => c.id == id).firstOrNull;

  final List<Payment> payments = [];
  final List<String> paymentCalls = [];

  /// Thrown by the next collectPayment, to test how screens show a refusal.
  Object? failPaymentWith;

  /// Takes the amount off the customer's due, like the real thing (but not
  /// bill by bill).
  @override
  Future<Payment> collectPayment(int customerId, double amount) async {
    paymentCalls.add('collect $customerId $amount');
    if (failPaymentWith != null) throw failPaymentWith!;
    final i = summaries.indexWhere((c) => c.id == customerId);
    if (i == -1) throw const PaymentException(PaymentProblem.unknownCustomer);
    final c = summaries[i];
    if (amount <= 0) throw const PaymentException(PaymentProblem.invalidAmount);
    if (amount > c.due) throw const PaymentException(PaymentProblem.exceedsDue);
    summaries[i] = CustomerSummary(
      id: c.id,
      name: c.name,
      mobile: c.mobile,
      whatsapp: c.whatsapp,
      address: c.address,
      nid: c.nid,
      billCount: c.billCount,
      productCount: c.productCount,
      totalSpent: c.totalSpent,
      totalPaid: c.totalPaid + amount,
      due: c.due - amount,
      lastPurchase: c.lastPurchase,
    );
    final payment = Payment(id: payments.length + 1, customerId: customerId, amount: amount, at: DateTime(2026, 11, 22, 14, 5));
    payments.add(payment);
    return payment;
  }

  @override
  Future<List<Payment>> paymentsOf(int customerId) async =>
      payments.where((p) => p.customerId == customerId).toList().reversed.toList();
}

/// Records receipts instead of opening WhatsApp.
class FakeReceiptSender implements ReceiptSender {
  final List<({String mobile, String message})> whatsApp = [];
  final List<String> shared = [];

  /// What sendWhatsApp reports: false = "WhatsApp could not be opened".
  bool whatsAppResult = true;

  @override
  Future<bool> sendWhatsApp(String mobile, String message) async {
    whatsApp.add((mobile: mobile, message: message));
    return whatsAppResult;
  }

  @override
  Future<void> share(String message) async => shared.add(message);
}

class FakeCategoryRepository implements CategoryRepository {
  final List<Category> items;
  int _nextId = 100;
  FakeCategoryRepository([List<Category>? items]) : items = items ?? [const Category(id: 1, name: 'পাইপ')];

  @override
  Future<List<Category>> all() async => List.of(items);

  @override
  Future<Category> add(String name) async {
    final existing = items.where((c) => c.name == name.trim()).firstOrNull;
    if (existing != null) return existing;
    final c = Category(id: _nextId++, name: name.trim());
    items.add(c);
    return c;
  }

  /// Renames made, as (id, name).
  final List<(int, String)> edits = [];
  @override
  Future<Category> update(int id, String name) async {
    if (name.trim().isEmpty) throw const CategoryException(CategoryProblem.emptyName);
    if (!items.any((c) => c.id == id)) throw const CategoryException(CategoryProblem.unknownCategory);
    if (items.any((c) => c.id != id && c.name.toLowerCase() == name.trim().toLowerCase())) {
      throw const CategoryException(CategoryProblem.nameTaken);
    }
    edits.add((id, name.trim()));
    final updated = Category(id: id, name: name.trim());
    items[items.indexWhere((c) => c.id == id)] = updated;
    return updated;
  }

  @override
  Future<void> delete(int id) async => items.removeWhere((c) => c.id == id);
}

class FakeLocationRepository implements LocationRepository {
  /// Products stocked per location id, like the real repository reports.
  final Map<int, int> counts;
  final List<int> deleted = [];
  FakeLocationRepository({this.counts = const {}});

  @override
  Future<List<StorageLocation>> all() async => const [StorageLocation(id: 5, name: 'তাক ১', code: 'X')];
  @override
  Future<StorageLocation> add(String name, LocationType type) async =>
      StorageLocation(id: 6, name: name, type: type, code: 'Y');
  @override
  Future<StorageLocation?> findByCode(String code) async => null;
  /// Renames made, as (id, name, type).
  final List<(int, String, LocationType)> edits = [];
  @override
  Future<StorageLocation> update(int id, {required String name, required LocationType type}) async {
    if (name.trim().isEmpty) throw const LocationException(LocationProblem.emptyName);
    edits.add((id, name.trim(), type));
    return StorageLocation(id: id, name: name.trim(), type: type, code: 'X');
  }

  @override
  Future<int> renameType(LocationType type, String newName) async => 0;
  @override
  Future<int> deleteType(LocationType type) async => 0;
  @override
  Future<Map<int, int>> stockedProductCounts() async => counts;
  @override
  Future<void> delete(int id) async {
    final stocked = counts[id] ?? 0;
    if (stocked > 0) throw LocationNotEmptyException(stocked);
    deleted.add(id);
  }
}

/// Records the calls and shares a screen asked for.
class FakeContactLauncher implements ContactLauncher {
  final List<String> calls = [];
  final List<String> shared = [];

  /// What every action reports: false = "could not be opened".
  bool result = true;

  @override
  Future<bool> call(String mobile) async {
    calls.add(mobile);
    return result;
  }

  @override
  Future<bool> share(String message) async {
    shared.add(message);
    return result;
  }
}
