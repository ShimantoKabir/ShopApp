import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../../domain/sales.dart';
import '../../domain/stock.dart';
import '../../domain/sync.dart';

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
