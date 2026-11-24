import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/entities.dart';
import '../../domain/repositories.dart';
import '../../domain/stock.dart';

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
