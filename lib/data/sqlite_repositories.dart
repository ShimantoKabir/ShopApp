import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../domain/customer_rules.dart';
import '../domain/customers.dart';
import '../domain/entities.dart';
import '../domain/payments.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import '../domain/stock.dart';
import '../domain/users.dart';
import 'app_database.dart';

/// Safe enum decoding: unknown/missing values fall back instead of crashing.
T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

// ---------------------------------------------------------------------------
// Small SQL helpers shared by the product and stock repositories. They take a
// DatabaseExecutor so they work both inside and outside a transaction.
// ---------------------------------------------------------------------------

Future<double> _productStock(DatabaseExecutor db, int productId) async {
  final rows = await db.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [productId], limit: 1);
  if (rows.isEmpty) throw StateError('No product with id $productId');
  return (rows.first['stock'] as num).toDouble();
}

Future<double> _placedTotal(DatabaseExecutor db, int productId) async {
  final rows = await db.rawQuery(
    'SELECT COALESCE(SUM(quantity), 0) AS total FROM stock_placements WHERE product_id = ?',
    [productId],
  );
  return (rows.first['total'] as num).toDouble();
}

Future<double> _placedAt(DatabaseExecutor db, int productId, int locationId) async {
  final rows = await db.query(
    'stock_placements',
    columns: ['quantity'],
    where: 'product_id = ? AND location_id = ?',
    whereArgs: [productId, locationId],
    limit: 1,
  );
  return rows.isEmpty ? 0 : (rows.first['quantity'] as num).toDouble();
}

/// Writes the quantity at a location; a zero (or less) quantity removes the row.
Future<void> _setPlacement(DatabaseExecutor db, int productId, int locationId, double quantity) async {
  if (quantity <= stockEpsilon) {
    await db.delete('stock_placements',
        where: 'product_id = ? AND location_id = ?', whereArgs: [productId, locationId]);
  } else {
    await db.insert(
      'stock_placements',
      {'product_id': productId, 'location_id': locationId, 'quantity': quantity},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

Future<void> _writeLog(
  DatabaseExecutor db,
  Clock clock,
  CurrentUser actor, {
  required int productId,
  int? locationId,
  required double delta,
  required StockReason reason,
}) async {
  if (delta.abs() <= stockEpsilon) return;
  await db.insert('stock_log', {
    'product_id': productId,
    'location_id': locationId,
    'delta': delta,
    'reason': reason.name,
    'user_id': actor.user?.id,
    'user_name': actor.user?.name ?? '',
    'at': clock.now().millisecondsSinceEpoch,
  });
}

Future<void> _touchProduct(DatabaseExecutor db, Clock clock, int productId) => db.update(
      'products',
      {'updated_at': clock.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [productId],
    );

// ---------------------------------------------------------------------------

class SqliteProductRepository implements ProductRepository {
  final DatabaseProvider _database;
  final Clock _clock;
  final CurrentUser _actor;
  SqliteProductRepository(this._database, this._clock, {this._actor = const NoUser()});

  Product _fromRow(Map<String, Object?> r, List<StockPlacement> placements) => Product(
        id: r['id'] as int,
        name: r['name'] as String,
        kind: _enumByName(ProductKind.values, r['kind'] as String?, ProductKind.standard),
        categoryId: r['category_id'] as int?,
        brand: r['brand'] as String? ?? '',
        size: r['size'] as String? ?? '',
        model: r['model'] as String? ?? '',
        finish: r['finish'] as String? ?? '',
        purchasePrice: (r['purchase_price'] as num).toDouble(),
        sellingPrice: (r['selling_price'] as num).toDouble(),
        stock: (r['stock'] as num).toDouble(),
        unit: r['unit'] as String,
        placements: placements,
      );

  /// Note: no location column. Where stock is kept lives in stock_placements.
  Map<String, Object?> _toRow(Product p) => {
        'name': p.name,
        'kind': p.kind.name,
        'category_id': p.categoryId,
        'brand': p.brand,
        'size': p.size,
        'model': p.model,
        'finish': p.finish,
        'purchase_price': p.purchasePrice,
        'selling_price': p.sellingPrice,
        'stock': p.stock,
        'unit': p.unit,
        'updated_at': _clock.now().millisecondsSinceEpoch,
      };

  Future<Map<int, List<StockPlacement>>> _placementsFor(DatabaseExecutor db, List<int> productIds) async {
    if (productIds.isEmpty) return {};
    final marks = List.filled(productIds.length, '?').join(',');
    final rows = await db.query(
      'stock_placements',
      where: 'product_id IN ($marks) AND quantity > 0',
      whereArgs: productIds,
      orderBy: 'quantity DESC',
    );
    final byProduct = <int, List<StockPlacement>>{};
    for (final r in rows) {
      byProduct.putIfAbsent(r['product_id'] as int, () => []).add(
            StockPlacement(locationId: r['location_id'] as int, quantity: (r['quantity'] as num).toDouble()),
          );
    }
    return byProduct;
  }

  @override
  Future<List<Product>> search({
    String query = '',
    int? categoryId,
    int? locationId,
    ProductKind? kind,
  }) async {
    final db = await _database.db;
    final where = <String>[];
    final args = <Object?>[];
    if (query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR brand LIKE ? OR size LIKE ? OR model LIKE ? OR finish LIKE ?)');
      args.addAll(List.filled(5, '%${query.trim()}%'));
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (locationId != null) {
      where.add('id IN (SELECT product_id FROM stock_placements WHERE location_id = ? AND quantity > 0)');
      args.add(locationId);
    }
    final rows = await db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );
    final placements = await _placementsFor(db, [for (final r in rows) r['id'] as int]);
    return [for (final r in rows) _fromRow(r, placements[r['id'] as int] ?? const [])];
  }

  @override
  Future<Product?> byId(int id) async {
    final db = await _database.db;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final placements = await _placementsFor(db, [id]);
    return _fromRow(rows.first, placements[id] ?? const []);
  }

  @override
  Future<bool> existsSimilar({
    required String name,
    String brand = '',
    String size = '',
    int? excludeId,
  }) async {
    final db = await _database.db;
    final rows = await db.query(
      'products',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE AND brand = ? COLLATE NOCASE AND size = ? COLLATE NOCASE'
          '${excludeId == null ? '' : ' AND id != ?'}',
      whereArgs: [name.trim(), brand.trim(), size.trim(), ?excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<Product> save(Product product) async {
    final db = await _database.db;
    if (product.stock < 0) throw const StockException(StockProblem.invalidQuantity);

    if (product.id == null) {
      final placements = product.placements.where((p) => p.quantity > stockEpsilon).toList();
      if (placements.any((p) => p.quantity < 0) || product.placedQuantity > product.stock + stockEpsilon) {
        throw const StockException(StockProblem.exceedsStock);
      }
      return db.transaction((txn) async {
        final id = await txn.insert('products', _toRow(product));
        for (final p in placements) {
          await _setPlacement(txn, id, p.locationId, p.quantity);
        }
        await _writeLog(txn, _clock, _actor, productId: id, delta: product.stock, reason: StockReason.initial);
        return product.copyWith(id: id, placements: placements);
      });
    }

    return db.transaction((txn) async {
      final id = product.id!;
      final placed = await _placedTotal(txn, id);
      if (product.stock + stockEpsilon < placed) throw const StockException(StockProblem.belowPlaced);
      final oldStock = await _productStock(txn, id);
      await txn.update('products', _toRow(product), where: 'id = ?', whereArgs: [id]);
      await _writeLog(txn, _clock, _actor, productId: id, delta: product.stock - oldStock, reason: StockReason.edit);
      return product;
    });
  }

  @override
  Future<void> delete(int id) async {
    final db = await _database.db;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> adjustStock(int id, double newTotal) async {
    final db = await _database.db;
    if (newTotal < 0) throw const StockException(StockProblem.invalidQuantity);
    await db.transaction((txn) async {
      final placed = await _placedTotal(txn, id);
      if (newTotal + stockEpsilon < placed) throw const StockException(StockProblem.belowPlaced);
      final oldStock = await _productStock(txn, id);
      await txn.update(
        'products',
        {'stock': newTotal, 'updated_at': _clock.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _writeLog(txn, _clock, _actor, productId: id, delta: newTotal - oldStock, reason: StockReason.edit);
    });
  }
}

class SqliteStockRepository implements StockRepository {
  final DatabaseProvider _database;
  final Clock _clock;
  final CurrentUser _actor;
  SqliteStockRepository(this._database, this._clock, {this._actor = const NoUser()});

  @override
  Future<List<StockPlacement>> placements(int productId) async {
    final db = await _database.db;
    final rows = await db.query(
      'stock_placements',
      where: 'product_id = ? AND quantity > 0',
      whereArgs: [productId],
      orderBy: 'quantity DESC',
    );
    return [
      for (final r in rows)
        StockPlacement(locationId: r['location_id'] as int, quantity: (r['quantity'] as num).toDouble()),
    ];
  }

  @override
  Future<void> place(int productId, int locationId, double quantity) async {
    if (quantity < 0) throw const StockException(StockProblem.invalidQuantity);
    final db = await _database.db;
    await db.transaction((txn) async {
      final stock = await _productStock(txn, productId);
      final placed = await _placedTotal(txn, productId);
      final old = await _placedAt(txn, productId, locationId);
      if (placed - old + quantity > stock + stockEpsilon) throw const StockException(StockProblem.exceedsStock);
      await _setPlacement(txn, productId, locationId, quantity);
      await _writeLog(txn, _clock, _actor,
          productId: productId, locationId: locationId, delta: quantity - old, reason: StockReason.place);
      await _touchProduct(txn, _clock, productId);
    });
  }

  @override
  Future<void> recount(int productId, int locationId, double quantity) async {
    if (quantity < 0) throw const StockException(StockProblem.invalidQuantity);
    final db = await _database.db;
    await db.transaction((txn) async {
      final old = await _placedAt(txn, productId, locationId);
      final delta = quantity - old;
      final stock = await _productStock(txn, productId);
      // Unplaced stock is untouched, so the total moves by exactly the difference.
      await txn.update(
        'products',
        {'stock': stock + delta, 'updated_at': _clock.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await _setPlacement(txn, productId, locationId, quantity);
      await _writeLog(txn, _clock, _actor,
          productId: productId, locationId: locationId, delta: delta, reason: StockReason.count);
    });
  }

  @override
  Future<void> move(int productId, int fromLocationId, int toLocationId, double quantity) async {
    if (quantity <= stockEpsilon) throw const StockException(StockProblem.invalidQuantity);
    if (fromLocationId == toLocationId) throw const StockException(StockProblem.sameLocation);
    final db = await _database.db;
    await db.transaction((txn) async {
      final atFrom = await _placedAt(txn, productId, fromLocationId);
      if (atFrom + stockEpsilon < quantity) throw const StockException(StockProblem.notEnoughAtSource);
      final atTo = await _placedAt(txn, productId, toLocationId);
      await _setPlacement(txn, productId, fromLocationId, atFrom - quantity);
      await _setPlacement(txn, productId, toLocationId, atTo + quantity);
      await _writeLog(txn, _clock, _actor,
          productId: productId, locationId: fromLocationId, delta: -quantity, reason: StockReason.move);
      await _writeLog(txn, _clock, _actor,
          productId: productId, locationId: toLocationId, delta: quantity, reason: StockReason.move);
      await _touchProduct(txn, _clock, productId);
    });
  }

  @override
  Future<void> restock(int productId, double quantity, {int? locationId, double? purchasePrice}) async {
    if (quantity <= stockEpsilon || (purchasePrice != null && purchasePrice < 0)) {
      throw const StockException(StockProblem.invalidQuantity);
    }
    final db = await _database.db;
    await db.transaction((txn) async {
      final stock = await _productStock(txn, productId);
      await txn.update(
        'products',
        {
          'stock': stock + quantity,
          'purchase_price': ?purchasePrice,
          'updated_at': _clock.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [productId],
      );
      if (locationId != null) {
        final at = await _placedAt(txn, productId, locationId);
        await _setPlacement(txn, productId, locationId, at + quantity);
      }
      await _writeLog(txn, _clock, _actor,
          productId: productId, locationId: locationId, delta: quantity, reason: StockReason.restock);
    });
  }

  @override
  Future<List<StockLogEntry>> history(int productId, {int limit = 30}) async {
    final db = await _database.db;
    final rows = await db.query(
      'stock_log',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        StockLogEntry(
          id: r['id'] as int,
          productId: r['product_id'] as int,
          locationId: r['location_id'] as int?,
          delta: (r['delta'] as num).toDouble(),
          reason: _enumByName(StockReason.values, r['reason'] as String?, StockReason.edit),
          at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
          userName: r['user_name'] as String? ?? '',
        ),
    ];
  }
}

class SqliteCategoryRepository implements CategoryRepository {
  final DatabaseProvider _database;
  SqliteCategoryRepository(this._database);

  @override
  Future<List<Category>> all() async {
    final db = await _database.db;
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Category(id: r['id'] as int, name: r['name'] as String)).toList();
  }

  @override
  Future<Category> add(String name) async {
    final db = await _database.db;
    final clean = name.trim();
    // Look up first: relying on insert(ignore)'s return value is unreliable
    // when the row already exists.
    final existing = await db.query(
      'categories',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [clean],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return Category(id: existing.first['id'] as int, name: existing.first['name'] as String);
    }
    final id = await db.insert('categories', {'name': clean});
    return Category(id: id, name: clean);
  }

  @override
  Future<Category> update(int id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const CategoryException(CategoryProblem.emptyName);
    final db = await _database.db;
    final current = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (current.isEmpty) throw const CategoryException(CategoryProblem.unknownCategory);
    final clash = await db.query('categories', where: 'name = ? COLLATE NOCASE AND id <> ?', whereArgs: [clean, id], limit: 1);
    if (clash.isNotEmpty) throw const CategoryException(CategoryProblem.nameTaken);
    await db.update('categories', {'name': clean}, where: 'id = ?', whereArgs: [id]);
    return Category(id: id, name: clean);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _database.db;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}

class SqliteLocationRepository implements LocationRepository {
  final DatabaseProvider _database;
  final LocationCodeGenerator _codes;
  SqliteLocationRepository(this._database, this._codes);

  StorageLocation _fromRow(Map<String, Object?> r) => StorageLocation(
        id: r['id'] as int,
        name: r['name'] as String,
        type: LocationType.parse(r['type'] as String?),
        code: r['code'] as String,
      );

  @override
  Future<List<StorageLocation>> all() async {
    final db = await _database.db;
    final rows = await db.query('locations', orderBy: 'name COLLATE NOCASE');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<StorageLocation> add(String name, LocationType type) async {
    final db = await _database.db;
    final code = _codes.generate();
    final id = await db.insert('locations', {'name': name.trim(), 'type': type.name, 'code': code});
    return StorageLocation(id: id, name: name.trim(), type: type, code: code);
  }

  @override
  Future<StorageLocation?> findByCode(String code) async {
    final db = await _database.db;
    final rows = await db.query('locations', where: 'code = ?', whereArgs: [code], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<Map<int, int>> stockedProductCounts() async {
    final db = await _database.db;
    final rows = await db.rawQuery('''
      SELECT location_id, COUNT(DISTINCT product_id) AS products
      FROM stock_placements WHERE quantity > 0 GROUP BY location_id''');
    return {for (final r in rows) r['location_id'] as int: r['products'] as int};
  }

  @override
  Future<StorageLocation> update(int id, {required String name, required LocationType type}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const LocationException(LocationProblem.emptyName);
    final db = await _database.db;
    final changed = await db.update('locations', {'name': clean, 'type': type.name}, where: 'id = ?', whereArgs: [id]);
    if (changed == 0) throw const LocationException(LocationProblem.unknownLocation);
    return _fromRow((await db.query('locations', where: 'id = ?', whereArgs: [id], limit: 1)).single);
  }

  @override
  Future<int> renameType(LocationType type, String newName) async {
    if (type.isBuiltIn) throw const LocationException(LocationProblem.builtInType);
    final clean = newName.trim();
    if (clean.isEmpty) throw const LocationException(LocationProblem.emptyName);
    final db = await _database.db;
    return db.update('locations', {'type': LocationType.custom(clean).name}, where: 'type = ?', whereArgs: [type.name]);
  }

  @override
  Future<int> deleteType(LocationType type) async {
    if (type.isBuiltIn) throw const LocationException(LocationProblem.builtInType);
    final db = await _database.db;
    return db.update('locations', {'type': LocationType.shelf.name}, where: 'type = ?', whereArgs: [type.name]);
  }

  @override
  Future<void> delete(int id) async {
    final db = await _database.db;
    // Checked here, at the lowest level, so no screen can bypass it.
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT COUNT(DISTINCT product_id) AS products FROM stock_placements WHERE location_id = ? AND quantity > 0',
        [id],
      );
      final stocked = rows.first['products'] as int;
      if (stocked > 0) throw LocationNotEmptyException(stocked);
      await txn.delete('locations', where: 'id = ?', whereArgs: [id]);
    });
  }
}

class SqliteSalesRepository implements SalesRepository {
  final DatabaseProvider _database;
  final Clock _clock;
  final CurrentUser _actor;
  SqliteSalesRepository(this._database, this._clock, {this._actor = const NoUser()});

  Sale _saleFromRow(Map<String, Object?> r) => Sale(
        id: r['id'] as int,
        billId: r['bill_id'] as int?,
        productId: r['product_id'] as int?,
        productName: r['product_name'] as String,
        unit: r['unit'] as String,
        locationId: r['location_id'] as int?,
        quantity: (r['quantity'] as num).toDouble(),
        unitPrice: (r['unit_price'] as num).toDouble(),
        unitCost: (r['unit_cost'] as num).toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
      );

  Bill _billFromRow(Map<String, Object?> r, List<Sale> lines) => Bill(
        id: r['id'] as int,
        customerId: r['customer_id'] as int?,
        customerName: r['customer_name'] as String? ?? '',
        customerMobile: r['customer_mobile'] as String? ?? '',
        customerAddress: r['customer_address'] as String? ?? '',
        customerWhatsApp: r['customer_whatsapp'] as String? ?? '',
        paid: (r['paid'] as num).toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
        lines: lines,
        soldBy: r['user_name'] as String? ?? '',
      );

  /// Loads the lines of several bills in one query.
  Future<Map<int, List<Sale>>> _linesFor(DatabaseExecutor db, List<int> billIds) async {
    if (billIds.isEmpty) return {};
    final marks = List.filled(billIds.length, '?').join(',');
    final rows = await db.query('sales', where: 'bill_id IN ($marks)', whereArgs: billIds, orderBy: 'id ASC');
    final byBill = <int, List<Sale>>{};
    for (final r in rows) {
      byBill.putIfAbsent(r['bill_id'] as int, () => []).add(_saleFromRow(r));
    }
    return byBill;
  }

  /// Trims and normalises what staff typed (Bangla/English digits, +880, dashes).
  CustomerInfo _clean(CustomerInfo? c) => c == null
      ? const CustomerInfo()
      : CustomerInfo(
          name: c.name.trim(),
          mobile: normalizeMobile(c.mobile),
          nid: normalizeNid(c.nid),
          address: c.address.trim(),
          whatsapp: normalizeMobile(c.whatsapp),
        );

  @override
  Future<Bill> checkout(List<SaleLine> lines, {CustomerInfo? customer, double? paid}) async {
    if (lines.isEmpty) throw const SaleException(SaleProblem.emptyBill);
    for (final l in lines) {
      if (l.quantity <= stockEpsilon || l.unitPrice < 0) throw const StockException(StockProblem.invalidQuantity);
    }
    final total = lines.fold(0.0, (sum, l) => sum + l.quantity * l.unitPrice);
    final paidAmount = paid ?? total;
    if (paidAmount < 0 || paidAmount > total + stockEpsilon) throw const SaleException(SaleProblem.invalidPayment);

    final info = _clean(customer);
    // Customer details are optional (a walk-in who pays in full gives nothing),
    // but whatever is given must be valid. Only a due makes them required:
    // then the name, address, a number to reach them on, and the NID.
    if (info.whatsapp.isNotEmpty && !isValidMobile(info.whatsapp)) throw const SaleException(SaleProblem.invalidCustomer);
    if (info.mobile.isNotEmpty && !isValidMobile(info.mobile)) throw const SaleException(SaleProblem.invalidCustomer);
    if (info.nid.isNotEmpty && !isValidNid(info.nid)) throw const SaleException(SaleProblem.invalidCustomer);
    final due = total - paidAmount;
    if (due > stockEpsilon &&
        (info.name.isEmpty ||
            info.address.isEmpty ||
            !(isValidMobile(info.mobile) || isValidMobile(info.whatsapp)) ||
            !isValidNid(info.nid))) {
      throw const SaleException(SaleProblem.customerRequiredForDue);
    }

    final db = await _database.db;
    return db.transaction((txn) async {
      final at = _clock.now();
      final customerId = await _saveCustomer(txn, info, at);
      final billId = await txn.insert('bills', {
        'customer_id': customerId,
        'customer_name': info.name,
        'customer_mobile': info.mobile,
        'customer_address': info.address,
        'customer_whatsapp': info.whatsapp,
        'user_id': _actor.user?.id,
        'user_name': _actor.user?.name ?? '',
        'paid': paidAmount,
        'at': at.millisecondsSinceEpoch,
      });
      final sold = <Sale>[];
      for (final line in lines) {
        sold.add(await _sellLine(txn, line, billId, at));
      }
      return Bill(
        id: billId,
        customerId: customerId,
        customerName: info.name,
        customerMobile: info.mobile,
        customerAddress: info.address,
        customerWhatsApp: info.whatsapp,
        paid: paidAmount,
        at: at,
        lines: sold,
        soldBy: _actor.user?.name ?? '',
      );
    });
  }

  @override
  Future<Bill> attachCustomer(int billId, CustomerInfo customer) async {
    final info = _clean(customer);
    if (info.whatsapp.isEmpty && info.mobile.isEmpty) throw const SaleException(SaleProblem.contactRequired);
    if (info.whatsapp.isNotEmpty && !isValidMobile(info.whatsapp)) throw const SaleException(SaleProblem.invalidCustomer);
    if (info.mobile.isNotEmpty && !isValidMobile(info.mobile)) throw const SaleException(SaleProblem.invalidCustomer);
    if (info.nid.isNotEmpty && !isValidNid(info.nid)) throw const SaleException(SaleProblem.invalidCustomer);

    final db = await _database.db;
    return db.transaction((txn) async {
      final rows = await txn.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
      if (rows.isEmpty) throw const SaleException(SaleProblem.unknownBill);
      final lines = (await _linesFor(txn, [billId]))[billId] ?? const <Sale>[];
      final before = _billFromRow(rows.first, lines);
      if (before.due > 0 &&
          (info.name.isEmpty ||
              info.address.isEmpty ||
              !(isValidMobile(info.mobile) || isValidMobile(info.whatsapp)) ||
              !isValidNid(info.nid))) {
        throw const SaleException(SaleProblem.customerRequiredForDue);
      }
      final customerId = await _saveCustomer(txn, info, _clock.now());
      await txn.update(
        'bills',
        {
          'customer_id': customerId,
          'customer_name': info.name,
          'customer_mobile': info.mobile,
          'customer_address': info.address,
          'customer_whatsapp': info.whatsapp,
        },
        where: 'id = ?',
        whereArgs: [billId],
      );
      final updated = await txn.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
      return _billFromRow(updated.first, lines);
    });
  }

  /// Remembers the customer. Matched by WhatsApp number (every sale has one),
  /// or by mobile number for customers saved before WhatsApp was required. A
  /// repeat customer keeps their record and gets anything newly given filled in.
  /// With no number at all (a walk-in who gave nothing) there is nobody to
  /// remember, so nothing is saved and the sale is just a retail sale.
  Future<int?> _saveCustomer(DatabaseExecutor txn, CustomerInfo info, DateTime at) async {
    if (info.whatsapp.isEmpty && info.mobile.isEmpty) return null;
    var existing = info.whatsapp.isEmpty
        ? <Map<String, Object?>>[]
        : await txn.query('customers', where: 'whatsapp = ?', whereArgs: [info.whatsapp], limit: 1);
    if (existing.isEmpty && info.mobile.isNotEmpty) {
      existing = await txn.query('customers', where: 'mobile = ?', whereArgs: [info.mobile], limit: 1);
    }
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await txn.update(
        'customers',
        {
          if (info.name.isNotEmpty) 'name': info.name,
          if (info.mobile.isNotEmpty) 'mobile': info.mobile,
          if (info.nid.isNotEmpty) 'nid': info.nid,
          if (info.address.isNotEmpty) 'address': info.address,
          if (info.whatsapp.isNotEmpty) 'whatsapp': info.whatsapp,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return txn.insert('customers', {
      'name': info.name,
      'mobile': info.mobile,
      'nid': info.nid,
      'address': info.address,
      'whatsapp': info.whatsapp,
      'created_at': at.millisecondsSinceEpoch,
    });
  }

  /// Sells one line inside the checkout transaction.
  Future<Sale> _sellLine(DatabaseExecutor txn, SaleLine line, int billId, DateTime at) async {
    final productId = line.productId;
    final quantity = line.quantity;
    final rows = await txn.query(
      'products',
      columns: ['name', 'unit', 'purchase_price', 'stock'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('No product with id $productId');
    final product = rows.first;
    final stock = (product['stock'] as num).toDouble();
    if (quantity > stock + stockEpsilon) throw const StockException(StockProblem.insufficientStock);

    final placementRows = await txn.query(
      'stock_placements',
      where: 'product_id = ? AND quantity > 0',
      whereArgs: [productId],
      orderBy: 'quantity DESC',
    );
    final placed = <int, double>{
      for (final r in placementRows) r['location_id'] as int: (r['quantity'] as num).toDouble(),
    };

    // Decide where the units come from.
    final take = <int, double>{}; // location id -> units taken from it
    var fromUnplaced = 0.0;
    final from = line.fromLocationId;
    if (from != null) {
      if ((placed[from] ?? 0) + stockEpsilon < quantity) throw const StockException(StockProblem.notEnoughAtSource);
      take[from] = quantity;
    } else {
      final placedTotal = placed.values.fold(0.0, (a, b) => a + b);
      final unplaced = math.max(0.0, stock - placedTotal);
      fromUnplaced = math.min(quantity, unplaced);
      var rest = quantity - fromUnplaced;
      for (final e in placed.entries) {
        if (rest <= stockEpsilon) break;
        final t = math.min(rest, e.value);
        take[e.key] = t;
        rest -= t;
      }
    }

    for (final e in take.entries) {
      await _setPlacement(txn, productId, e.key, placed[e.key]! - e.value);
    }
    final remaining = stock - quantity;
    await txn.update(
      'products',
      {
        'stock': remaining < stockEpsilon ? 0.0 : remaining,
        'updated_at': _clock.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    // The sale remembers a location only if it came from exactly one.
    final singleLocation = (fromUnplaced <= stockEpsilon && take.length == 1) ? take.keys.single : null;
    final unitCost = (product['purchase_price'] as num).toDouble();
    final id = await txn.insert('sales', {
      'bill_id': billId,
      'product_id': productId,
      'product_name': product['name'],
      'unit': product['unit'],
      'location_id': singleLocation,
      'quantity': quantity,
      'unit_price': line.unitPrice,
      'unit_cost': unitCost,
      'at': at.millisecondsSinceEpoch,
    });
    await _writeLog(txn, _clock, _actor,
        productId: productId, locationId: singleLocation, delta: -quantity, reason: StockReason.sale);
    return Sale(
      id: id,
      billId: billId,
      productId: productId,
      productName: product['name'] as String,
      unit: product['unit'] as String,
      locationId: singleLocation,
      quantity: quantity,
      unitPrice: line.unitPrice,
      unitCost: unitCost,
      at: at,
    );
  }

  @override
  Future<void> voidBill(int billId) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final bills = await txn.query('bills', columns: ['id'], where: 'id = ?', whereArgs: [billId], limit: 1);
      if (bills.isEmpty) return;
      final saleRows = await txn.query('sales', where: 'bill_id = ?', whereArgs: [billId]);
      for (final row in saleRows) {
        await _restoreSale(txn, _saleFromRow(row));
      }
      // Money collected later on this bill goes back with it.
      final allocations = await txn.query('payment_allocations', where: 'bill_id = ?', whereArgs: [billId]);
      for (final a in allocations) {
        await txn.rawUpdate(
          'UPDATE payments SET amount = amount - ? WHERE id = ?',
          [(a['amount'] as num).toDouble(), a['payment_id']],
        );
      }
      await txn.delete('payment_allocations', where: 'bill_id = ?', whereArgs: [billId]);
      await txn.delete('payments', where: 'amount <= ?', whereArgs: [stockEpsilon]);
      await txn.delete('sales', where: 'bill_id = ?', whereArgs: [billId]);
      await txn.delete('bills', where: 'id = ?', whereArgs: [billId]);
    });
  }

  /// Returns one line's units to stock, and to the location they came from if
  /// that place still exists.
  Future<void> _restoreSale(DatabaseExecutor txn, Sale sale) async {
    final productId = sale.productId;
    if (productId == null) return; // product deleted: nothing to give back to
    final stock = await _productStock(txn, productId);
    await txn.update(
      'products',
      {'stock': stock + sale.quantity, 'updated_at': _clock.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [productId],
    );
    int? restoredTo;
    final locationId = sale.locationId;
    if (locationId != null) {
      final exists = await txn.query('locations', columns: ['id'], where: 'id = ?', whereArgs: [locationId], limit: 1);
      if (exists.isNotEmpty) {
        final at = await _placedAt(txn, productId, locationId);
        await _setPlacement(txn, productId, locationId, at + sale.quantity);
        restoredTo = locationId;
      }
    }
    await _writeLog(txn, _clock, _actor,
        productId: productId, locationId: restoredTo, delta: sale.quantity, reason: StockReason.saleVoid);
  }

  @override
  Future<List<Bill>> billsOn(DateTime day) async {
    final db = await _database.db;
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await db.query(
      'bills',
      where: 'at >= ? AND at < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'at DESC, id DESC',
    );
    final lines = await _linesFor(db, [for (final r in rows) r['id'] as int]);
    return [for (final r in rows) _billFromRow(r, lines[r['id'] as int] ?? const [])];
  }

  @override
  Future<double> collectedOn(DateTime day) async {
    final db = await _database.db;
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE at >= ? AND at < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (rows.first['total'] as num).toDouble();
  }

  @override
  Future<List<PaymentReceipt>> paymentsOn(DateTime day) async {
    final db = await _database.db;
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await db.rawQuery(
      '''SELECT p.id AS id, p.customer_id AS customer_id, p.amount AS amount, p.at AS at, p.user_name AS user_name,
                c.name AS name, c.mobile AS mobile, c.whatsapp AS whatsapp
         FROM payments p LEFT JOIN customers c ON c.id = p.customer_id
         WHERE p.at >= ? AND p.at < ?
         ORDER BY p.at DESC, p.id DESC''',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    final receipts = <PaymentReceipt>[];
    for (final r in rows) {
      final customerId = r['customer_id'] as int;
      final at = r['at'] as int;
      final id = r['id'] as int;
      receipts.add(PaymentReceipt(
        payment: Payment(
          id: id,
          customerId: customerId,
          amount: (r['amount'] as num).toDouble(),
          at: DateTime.fromMillisecondsSinceEpoch(at),
          receivedBy: r['user_name'] as String? ?? '',
        ),
        customerName: r['name'] as String? ?? '',
        customerMobile: r['mobile'] as String? ?? '',
        customerWhatsApp: r['whatsapp'] as String? ?? '',
        dueAfter: await _dueAfter(db, customerId, at, id),
      ));
    }
    return receipts;
  }

  /// What a customer still owed right after one payment: what their bills up
  /// to then left unpaid when they were made, less every payment up to and
  /// including this one.
  Future<double> _dueAfter(DatabaseExecutor db, int customerId, int at, int paymentId) async {
    final owed = await db.rawQuery(
      '''SELECT COALESCE(SUM(t.total - (t.paid - t.allocated)), 0) AS v FROM (
           SELECT b.paid AS paid,
                  COALESCE((SELECT SUM(a.amount) FROM payment_allocations a WHERE a.bill_id = b.id), 0) AS allocated,
                  COALESCE((SELECT SUM(s.quantity * s.unit_price) FROM sales s WHERE s.bill_id = b.id), 0) AS total
           FROM bills b WHERE b.customer_id = ? AND b.at <= ?) t''',
      [customerId, at],
    );
    final paid = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS v FROM payments WHERE customer_id = ? AND (at < ? OR (at = ? AND id <= ?))',
      [customerId, at, at, paymentId],
    );
    final due = (owed.first['v'] as num).toDouble() - (paid.first['v'] as num).toDouble();
    return due < stockEpsilon ? 0 : due;
  }

  @override
  Future<List<Bill>> billsOfCustomer(int customerId) async {
    final db = await _database.db;
    final rows = await db.query('bills', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'at DESC, id DESC');
    final lines = await _linesFor(db, [for (final r in rows) r['id'] as int]);
    return [for (final r in rows) _billFromRow(r, lines[r['id'] as int] ?? const [])];
  }

  @override
  Future<Bill?> billById(int id) async {
    final db = await _database.db;
    final rows = await db.query('bills', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final lines = await _linesFor(db, [id]);
    return _billFromRow(rows.first, lines[id] ?? const []);
  }
}

class SqliteCustomerRepository implements CustomerRepository {
  final DatabaseProvider _database;
  final Clock _clock;
  final CurrentUser _actor;
  SqliteCustomerRepository(this._database, this._clock, {this._actor = const NoUser()});

  @override
  Future<CustomerInfo?> findByPhone(String number) async {
    final normalized = normalizeMobile(number);
    if (normalized.isEmpty) return null;
    final db = await _database.db;
    // Prefer a match on WhatsApp over one on mobile. (?1 is the one number, used three times.)
    final rows = await db.rawQuery(
      'SELECT * FROM customers WHERE whatsapp = ?1 OR mobile = ?1 '
      'ORDER BY CASE WHEN whatsapp = ?1 THEN 0 ELSE 1 END LIMIT 1',
      [normalized],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CustomerInfo(
      name: r['name'] as String? ?? '',
      mobile: r['mobile'] as String? ?? '',
      nid: r['nid'] as String? ?? '',
      address: r['address'] as String? ?? '',
      whatsapp: r['whatsapp'] as String? ?? '',
    );
  }

  /// Customers joined with their per-bill totals and distinct products bought.
  /// A bill is "due" for what is left after what was paid (never negative).
  static const _summarySql = '''
    SELECT c.id, c.name, c.mobile, c.whatsapp, c.address, c.nid,
           COALESCE(t.bills, 0) AS bills, COALESCE(t.total, 0) AS total,
           COALESCE(t.paid, 0) AS paid, COALESCE(t.due, 0) AS due, t.last_at AS last_at,
           COALESCE(p.products, 0) AS products
    FROM customers c
    LEFT JOIN (
      SELECT customer_id, COUNT(*) AS bills, SUM(total) AS total, SUM(paid) AS paid,
             SUM(CASE WHEN total - paid > 0.000000001 THEN total - paid ELSE 0 END) AS due,
             MAX(at) AS last_at
      FROM (
        SELECT b.id, b.customer_id, b.paid, b.at, COALESCE(SUM(s.quantity * s.unit_price), 0) AS total
        FROM bills b LEFT JOIN sales s ON s.bill_id = b.id
        WHERE b.customer_id IS NOT NULL
        GROUP BY b.id)
      GROUP BY customer_id) t ON t.customer_id = c.id
    LEFT JOIN (
      SELECT b.customer_id, COUNT(DISTINCT s.product_name) AS products
      FROM bills b JOIN sales s ON s.bill_id = b.id
      WHERE b.customer_id IS NOT NULL
      GROUP BY b.customer_id) p ON p.customer_id = c.id''';

  CustomerSummary _summaryFromRow(Map<String, Object?> r) => CustomerSummary(
        id: r['id'] as int,
        name: r['name'] as String? ?? '',
        mobile: r['mobile'] as String? ?? '',
        whatsapp: r['whatsapp'] as String? ?? '',
        address: r['address'] as String? ?? '',
        nid: r['nid'] as String? ?? '',
        billCount: (r['bills'] as num).toInt(),
        productCount: (r['products'] as num).toInt(),
        totalSpent: (r['total'] as num).toDouble(),
        totalPaid: (r['paid'] as num).toDouble(),
        due: (r['due'] as num).toDouble(),
        lastPurchase: r['last_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last_at'] as int),
      );

  @override
  Future<List<CustomerSummary>> all() async {
    final db = await _database.db;
    final rows = await db.rawQuery('$_summarySql ORDER BY t.last_at DESC, c.id DESC');
    return rows.map(_summaryFromRow).toList();
  }

  @override
  Future<Payment> collectPayment(int customerId, double amount) async {
    if (amount.isNaN || amount.isInfinite || amount <= stockEpsilon) {
      throw const PaymentException(PaymentProblem.invalidAmount);
    }
    final db = await _database.db;
    final at = _clock.now();
    return db.transaction((txn) async {
      final known = await txn.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (known.isEmpty) throw const PaymentException(PaymentProblem.unknownCustomer);

      // Their unpaid bills, oldest first.
      final rows = await txn.rawQuery('''
        SELECT b.id AS id, b.paid AS paid, COALESCE(SUM(s.quantity * s.unit_price), 0) AS total
        FROM bills b LEFT JOIN sales s ON s.bill_id = b.id
        WHERE b.customer_id = ?
        GROUP BY b.id
        ORDER BY b.at ASC, b.id ASC''', [customerId]);
      final owing = <({int id, double paid, double due})>[];
      for (final r in rows) {
        final paid = (r['paid'] as num).toDouble();
        final due = (r['total'] as num).toDouble() - paid;
        if (due > stockEpsilon) owing.add((id: r['id'] as int, paid: paid, due: due));
      }
      final totalDue = owing.fold(0.0, (sum, o) => sum + o.due);
      if (amount > totalDue + stockEpsilon) throw const PaymentException(PaymentProblem.exceedsDue);

      final paymentId = await txn.insert('payments', {
        'customer_id': customerId,
        'amount': amount,
        'user_id': _actor.user?.id,
        'user_name': _actor.user?.name ?? '',
        'at': at.millisecondsSinceEpoch,
      });
      var left = amount;
      for (final bill in owing) {
        if (left <= stockEpsilon) break;
        final part = math.min(left, bill.due);
        await txn.update('bills', {'paid': bill.paid + part}, where: 'id = ?', whereArgs: [bill.id]);
        await txn.insert('payment_allocations', {'payment_id': paymentId, 'bill_id': bill.id, 'amount': part});
        left -= part;
      }
      return Payment(id: paymentId, customerId: customerId, amount: amount, at: at, receivedBy: _actor.user?.name ?? '');
    });
  }

  @override
  Future<List<Payment>> paymentsOf(int customerId) async {
    final db = await _database.db;
    final rows = await db.query('payments', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'at DESC, id DESC');
    return [
      for (final r in rows)
        Payment(
          id: r['id'] as int,
          customerId: r['customer_id'] as int,
          amount: (r['amount'] as num).toDouble(),
          at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
          receivedBy: r['user_name'] as String? ?? '',
        ),
    ];
  }

  @override
  Future<CustomerSummary?> byId(int id) async {
    final db = await _database.db;
    final rows = await db.rawQuery('$_summarySql WHERE c.id = ?', [id]);
    return rows.isEmpty ? null : _summaryFromRow(rows.first);
  }
}
