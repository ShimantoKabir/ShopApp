import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/entities.dart';
import '../domain/import/csv_source.dart';
import '../domain/import/product_importer.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import '../domain/stock.dart';
import '../domain/sync.dart';

class ProductListViewModel extends ChangeNotifier {
  final ProductRepository _products;
  final CategoryRepository _categories;
  final LocationRepository _locations;
  final StockRepository _stock;

  ProductListViewModel(this._products, this._categories, this._locations, this._stock);

  List<Product> products = [];
  List<Category> categories = [];
  List<StorageLocation> locations = [];
  String query = '';
  int? categoryFilter;
  int? locationFilter;
  bool loading = true;

  bool get hasFilter => query.isNotEmpty || categoryFilter != null;

  double get totalStockValue => products.fold(0, (s, p) => s + p.stockValueAtCost);

  String categoryName(int? id) =>
      categories.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '';

  String locationName(int? id) => locations.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? '';

  /// [quiet]: refresh what is shown without the loading bar (the list stays
  /// on screen meanwhile), for coming back to a screen.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      notifyListeners();
    }
    final results = await Future.wait([
      _products.search(
        query: query,
        categoryId: categoryFilter,
        locationId: locationFilter,
      ),
      _categories.all(),
      _locations.all(),
    ]);
    products = results[0] as List<Product>;
    categories = results[1] as List<Category>;
    locations = results[2] as List<StorageLocation>;
    loading = false;
    notifyListeners();
  }

  Future<void> setQuery(String value) {
    query = value;
    return load();
  }

  Future<void> setCategoryFilter(int? id) {
    categoryFilter = id;
    return load();
  }

  Future<void> setLocationFilter(int? id) {
    locationFilter = id;
    return load();
  }

  /// Sets the product's TOTAL stock. Throws [StockException] if it would be
  /// less than the quantity already placed at locations.
  Future<void> updateStock(Product p, double stock) async {
    await _products.adjustStock(p.id!, stock);
    await load();
  }

  /// New goods arrived. See [StockRepository.restock].
  Future<void> restock(Product p, double quantity, {int? locationId, double? purchasePrice}) async {
    await _stock.restock(p.id!, quantity, locationId: locationId, purchasePrice: purchasePrice);
    await load();
  }

  /// A physical count at one location: sets the quantity there and adjusts the total.
  Future<void> recount(Product p, int locationId, double quantity) async {
    await _stock.recount(p.id!, locationId, quantity);
    await load();
  }

  Future<void> delete(Product p) async {
    await _products.delete(p.id!);
    await load();
  }
}

class ProductFormViewModel extends ChangeNotifier {
  final ProductRepository _products;
  final CategoryRepository _categories;
  final LocationRepository _locations;
  final StockRepository _stock;

  ProductFormViewModel(this._products, this._categories, this._locations, this._stock);

  List<Category> categories = [];
  List<StorageLocation> locations = [];

  Future<void> load() async {
    categories = await _categories.all();
    locations = await _locations.all();
    notifyListeners();
  }

  Future<Category> addCategory(String name) async {
    final c = await _categories.add(name);
    await load();
    return c;
  }

  Future<StorageLocation> addLocation(String name, LocationType type) async {
    final s = await _locations.add(name, type);
    await load();
    return s;
  }

  Future<StorageLocation?> locationByCode(String code) => _locations.findByCode(code);

  Future<Product> save(Product p) => _products.save(p);

  /// Latest saved state of a product, including where its stock is kept.
  Future<Product?> reload(int id) => _products.byId(id);

  // Where stock is kept. Each call is atomic and recorded in the history.
  Future<void> place(int productId, int locationId, double quantity) => _stock.place(productId, locationId, quantity);
  Future<void> recount(int productId, int locationId, double quantity) =>
      _stock.recount(productId, locationId, quantity);
  Future<void> move(int productId, int from, int to, double quantity) => _stock.move(productId, from, to, quantity);
  Future<List<StockLogEntry>> history(int productId) => _stock.history(productId);

  Future<bool> isDuplicate(Product p) => _products.existsSimilar(
        name: p.name,
        brand: p.brand,
        size: p.size,
        excludeId: p.id,
      );
}

class CategoriesViewModel extends ChangeNotifier {
  final CategoryRepository _repo;
  CategoriesViewModel(this._repo);

  List<Category> items = [];

  Future<void> load() async {
    items = await _repo.all();
    notifyListeners();
  }

  Future<void> add(String name) async {
    await _repo.add(name);
    await load();
  }

  Future<void> update(Category c, String name) async {
    await _repo.update(c.id!, name);
    await load();
  }

  Future<void> delete(Category c) async {
    await _repo.delete(c.id!);
    await load();
  }
}

/// The location types the shop made up, and how many locations use each.
class LocationTypesViewModel extends ChangeNotifier {
  final LocationRepository _repo;
  LocationTypesViewModel(this._repo);

  List<({LocationType type, int count})> items = [];

  Future<void> load() async {
    final counts = <LocationType, int>{};
    for (final l in await _repo.all()) {
      if (!l.type.isBuiltIn) counts[l.type] = (counts[l.type] ?? 0) + 1;
    }
    items = [for (final t in LocationType.offered([for (final e in counts.keys) StorageLocation(name: '', type: e, code: '')]).where((t) => !t.isBuiltIn)) (type: t, count: counts[t]!)];
    notifyListeners();
  }

  Future<void> rename(LocationType type, String newName) async {
    await _repo.renameType(type, newName);
    await load();
  }

  Future<void> delete(LocationType type) async {
    await _repo.deleteType(type);
    await load();
  }
}

class LocationsViewModel extends ChangeNotifier {
  final LocationRepository _repo;
  LocationsViewModel(this._repo);

  List<StorageLocation> items = [];

  /// How many products hold stock at each location (id -> count).
  Map<int, int> counts = {};

  int stockedProducts(StorageLocation s) => counts[s.id] ?? 0;

  Future<void> load() async {
    items = await _repo.all();
    counts = await _repo.stockedProductCounts();
    notifyListeners();
  }

  Future<void> add(String name, LocationType type) async {
    await _repo.add(name, type);
    await load();
  }

  /// Renames a location (and/or changes its type). Allowed even when it holds
  /// stock. Throws [LocationException] or (when shared) [SyncException].
  Future<void> update(StorageLocation s, String name, LocationType type) async {
    await _repo.update(s.id!, name: name, type: type);
    await load();
  }

  /// Returns 0 if deleted, or the number of products still stocked there if
  /// the location was refused (it must be emptied first).
  Future<int> delete(StorageLocation s) async {
    try {
      await _repo.delete(s.id!);
      await load();
      return 0;
    } on LocationNotEmptyException catch (e) {
      await load();
      return e.productCount;
    }
  }
}

enum ImportStatus { idle, running, done, cancelled }

class ImportViewModel extends ChangeNotifier {
  final CsvSource _source;
  final ProductImporter _importer;
  ImportViewModel(this._source, this._importer);

  ImportStatus status = ImportStatus.idle;
  ImportResult? result;

  /// Off by default: file prices/stock are often unverified estimates.
  bool withPricesAndStock = false;

  void setWithPricesAndStock(bool value) {
    withPricesAndStock = value;
    notifyListeners();
  }

  Future<void> pickAndImport() async {
    status = ImportStatus.running;
    result = null;
    notifyListeners();
    try {
      final text = await _source.pick();
      if (text == null) {
        status = ImportStatus.cancelled;
      } else {
        result = await _importer.import(text, withPricesAndStock: withPricesAndStock);
        status = ImportStatus.done;
      }
    } catch (_) {
      result = const ImportResult(fatalError: 'ফাইলটি পড়া যায়নি');
      status = ImportStatus.done;
    }
    notifyListeners();
  }
}

/// A product in the cart, with the quantity, price and (optionally) the
/// location the customer's units will come from.
class CartLine {
  Product product;
  double quantity;
  double unitPrice;
  final int? fromLocationId;

  CartLine({required this.product, required this.quantity, required this.unitPrice, this.fromLocationId});

  double get total => quantity * unitPrice;

  SaleLine toSaleLine() =>
      SaleLine(productId: product.id!, quantity: quantity, unitPrice: unitPrice, fromLocationId: fromLocationId);
}

/// The sell screen: find products, build a cart, and check out as one bill.
class SellViewModel extends ChangeNotifier {
  final ProductRepository _products;
  final SalesRepository _sales;
  final LocationRepository _locations;
  final CustomerRepository _customers;
  final SyncService? _sync;

  /// [sync], when the shop is shared, lets the selling screens catch up with
  /// what other phones did at the moments that matter (see [refreshFromShop]).
  SellViewModel(this._products, this._sales, this._locations, this._customers, {this._sync});

  List<Product> products = [];
  List<StorageLocation> locations = [];
  String query = '';
  bool loading = true;

  final List<CartLine> cart = [];

  int get cartCount => cart.length;
  double get cartTotal => cart.fold(0.0, (sum, l) => sum + l.total);

  String locationName(int? id) => locations.where((l) => l.id == id).map((l) => l.name).firstOrNull ?? '';

  /// How much of [p] is already in the cart.
  double inCart(Product p) => cart.where((l) => l.product.id == p.id).fold(0.0, (sum, l) => sum + l.quantity);

  /// What can still be added to the cart.
  double availableFor(Product p) => p.stock - inCart(p);

  /// [quiet]: refresh without the loading bar.
  Future<void> load({bool quiet = false}) async {
    if (!quiet) {
      loading = true;
      notifyListeners();
    }
    final results = await Future.wait([_products.search(query: query), _locations.all()]);
    products = results[0] as List<Product>;
    locations = results[1] as List<StorageLocation>;
    loading = false;
    notifyListeners();
  }

  Future<void> setQuery(String value) {
    query = value;
    return load();
  }

  /// Adds to the cart (merging with an identical line). Throws [StockException]
  /// if the cart would hold more than is in stock.
  void addToCart(Product p, {double quantity = 1, double? unitPrice, int? fromLocationId}) {
    if (quantity > availableFor(p) + stockEpsilon) throw const StockException(StockProblem.insufficientStock);
    final price = unitPrice ?? p.sellingPrice;
    final same = cart.where((l) => l.product.id == p.id && l.unitPrice == price && l.fromLocationId == fromLocationId);
    if (same.isNotEmpty) {
      same.first.quantity += quantity;
    } else {
      cart.add(CartLine(product: p, quantity: quantity, unitPrice: price, fromLocationId: fromLocationId));
    }
    notifyListeners();
  }

  /// Sets a line's quantity (zero or less removes it). Throws [StockException]
  /// if it would exceed the stock.
  void setQuantity(CartLine line, double quantity) {
    if (quantity <= stockEpsilon) return removeLine(line);
    final others = inCart(line.product) - line.quantity;
    if (quantity > line.product.stock - others + stockEpsilon) {
      throw const StockException(StockProblem.insufficientStock);
    }
    line.quantity = quantity;
    notifyListeners();
  }

  void removeLine(CartLine line) {
    cart.remove(line);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  /// Sells everything in the cart as one bill and empties the cart. Throws
  /// [StockException] or [SaleException]; on failure the cart is kept.
  Future<Bill> checkout({CustomerInfo? customer, double? paid}) async {
    final Bill bill;
    try {
      bill = await _sales.checkout([for (final l in cart) l.toSaleLine()], customer: customer, paid: paid);
    } on SyncException catch (e) {
      // The sale reached the shop but has not come back yet. It is NOT lost, so
      // the cart is emptied: selling it again would sell it twice.
      if (e.problem == SyncProblem.delayed) {
        cart.clear();
        notifyListeners();
      }
      rethrow;
    }
    cart.clear();
    await load();
    return bill;
  }

  /// How long a sale moment waits for the shop before going on with what this
  /// phone already knows (a weak signal must not freeze selling).
  static const catchUpTimeout = Duration(seconds: 5);

  /// Called when someone is about to sell (the selling screen opens, a product
  /// is picked, the cart or checkout opens): catches up with what other phones
  /// did, shows the fresh stock, and fixes the cart to match. Returns what no
  /// longer fits (an item another phone sold meanwhile): each was cut down to
  /// what is left, or taken out of the cart when nothing is left.
  ///
  /// When the shop is not shared, or there is no signal, it simply uses what
  /// this phone has. Never throws for lack of connection.
  Future<List<({String name, double left})>> refreshFromShop() async {
    final sync = _sync;
    if (sync != null && sync.enabled) {
      try {
        await sync.syncNow().timeout(catchUpTimeout);
      } on TimeoutException {
        // Carry on with what we have; the sync finishes by itself.
      }
    }
    await load(quiet: true);
    return _fitCartToStock();
  }

  Future<List<({String name, double left})>> _fitCartToStock() async {
    final shortages = <({String name, double left})>[];
    final remaining = <int, double>{};
    final fresh = <int, Product?>{};
    for (final line in List.of(cart)) {
      final id = line.product.id!;
      final product = fresh[id] ??= await _products.byId(id);
      if (product == null) {
        // Deleted on another phone.
        shortages.add((name: line.product.name, left: 0));
        cart.remove(line);
        continue;
      }
      line.product = product;
      final left = remaining[id] ?? product.stock;
      final limit = line.fromLocationId == null ? left : (product.quantityAt(line.fromLocationId!) < left ? product.quantityAt(line.fromLocationId!) : left);
      if (line.quantity > limit + stockEpsilon) {
        shortages.add((name: product.name, left: limit < 0 ? 0 : limit));
        if (limit <= stockEpsilon) {
          cart.remove(line);
          continue;
        }
        line.quantity = limit;
      }
      remaining[id] = left - line.quantity;
    }
    if (shortages.isNotEmpty) notifyListeners();
    return shortages;
  }

  /// A customer seen before, by WhatsApp or mobile number (to fill in the form).
  Future<CustomerInfo?> findCustomer(String number) => _customers.findByPhone(number);
}

/// The daily account: bills of one day, with totals, browsable day by day.
class SalesSummaryViewModel extends ChangeNotifier {
  final SalesRepository _sales;
  final Clock _clock;

  SalesSummaryViewModel(this._sales, this._clock) : day = _clock.now();

  DateTime day;
  List<Bill> bills = [];
  DaySummary summary = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  bool loading = true;

  DateTime get _today => DateTime(_clock.now().year, _clock.now().month, _clock.now().day);
  DateTime get _dayOnly => DateTime(day.year, day.month, day.day);

  bool get isToday => _dayOnly == _today;
  String get label => dayLabel(day, _clock.now());

  Future<void> load() async {
    loading = true;
    notifyListeners();
    bills = await _sales.billsOn(day);
    summary = DaySummary.of(bills).withCollected(await _sales.collectedOn(day));
    loading = false;
    notifyListeners();
  }

  Future<void> previousDay() {
    day = DateTime(day.year, day.month, day.day - 1);
    return load();
  }

  /// Never goes past today.
  Future<void> nextDay() {
    if (isToday) return Future.value();
    day = DateTime(day.year, day.month, day.day + 1);
    return load();
  }

  Future<void> voidBill(Bill bill) async {
    await _sales.voidBill(bill.id!);
    await load();
  }
}
