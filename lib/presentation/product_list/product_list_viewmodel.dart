import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../../domain/stock.dart';

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
