import '../domain/dashboard.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/stock.dart';
import 'app_database.dart';

/// One bill with what it came to. (A bill with no lines counts as zero.)
class _BillRow {
  final int id;
  final DateTime at;
  final double paid;
  final int? customerId;
  final String name;
  final String whatsapp;
  final String mobile;
  final double total;
  final double cost;

  _BillRow(Map<String, Object?> r)
      : id = r['id'] as int,
        at = DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
        paid = (r['paid'] as num).toDouble(),
        customerId = r['customer_id'] as int?,
        name = r['customer_name'] as String? ?? '',
        whatsapp = r['customer_whatsapp'] as String? ?? '',
        mobile = r['customer_mobile'] as String? ?? '',
        total = (r['total'] as num).toDouble(),
        cost = (r['cost'] as num).toDouble();

  double get due {
    final rest = total - paid;
    return rest < stockEpsilon ? 0 : rest;
  }
}

/// Reads figures for the dashboard. Everything here is a SELECT.
class SqliteDashboardRepository implements DashboardRepository {
  final DatabaseProvider _database;
  SqliteDashboardRepository(this._database);

  Future<List<_BillRow>> _bills({DateTime? from, DateTime? to}) async {
    final db = await _database.db;
    final filtered = from != null && to != null;
    final rows = await db.rawQuery('''
      SELECT b.id AS id, b.at AS at, b.paid AS paid, b.customer_id AS customer_id,
             b.customer_name AS customer_name, b.customer_whatsapp AS customer_whatsapp,
             b.customer_mobile AS customer_mobile,
             COALESCE(SUM(s.quantity * s.unit_price), 0) AS total,
             COALESCE(SUM(s.quantity * s.unit_cost), 0) AS cost
      FROM bills b LEFT JOIN sales s ON s.bill_id = b.id
      ${filtered ? 'WHERE b.at >= ? AND b.at < ?' : ''}
      GROUP BY b.id
      ORDER BY b.at DESC, b.id DESC''', filtered ? [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch] : []);
    return rows.map(_BillRow.new).toList();
  }

  @override
  Future<DaySummary> summary(DateTime from, DateTime to) async {
    final bills = await _bills(from: from, to: to);
    var revenue = 0.0, cost = 0.0, due = 0.0;
    for (final b in bills) {
      revenue += b.total;
      cost += b.cost;
      due += b.due;
    }
    final db = await _database.db;
    final collected = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM payments WHERE at >= ? AND at < ?',
      [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch],
    );
    return DaySummary(
      saleCount: bills.length,
      revenue: revenue,
      cost: cost,
      due: due,
      collected: (collected.first['total'] as num).toDouble(),
    );
  }

  @override
  Future<List<DailyTotal>> dailyTotals(DateTime from, int days) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(start.year, start.month, start.day + days);
    final bills = await _bills(from: start, to: end);

    final revenue = <DateTime, double>{};
    final profit = <DateTime, double>{};
    final count = <DateTime, int>{};
    for (final b in bills) {
      final day = DateTime(b.at.year, b.at.month, b.at.day);
      revenue[day] = (revenue[day] ?? 0) + b.total;
      profit[day] = (profit[day] ?? 0) + (b.total - b.cost);
      count[day] = (count[day] ?? 0) + 1;
    }
    return [
      for (var i = 0; i < days; i++)
        () {
          final day = DateTime(start.year, start.month, start.day + i);
          return DailyTotal(day: day, revenue: revenue[day] ?? 0, profit: profit[day] ?? 0, bills: count[day] ?? 0);
        }(),
    ];
  }

  @override
  Future<List<ProductSales>> topProducts(DateTime from, DateTime to, {int limit = 5}) async {
    final db = await _database.db;
    final rows = await db.rawQuery('''
      SELECT product_name, unit,
             SUM(quantity) AS quantity,
             SUM(quantity * unit_price) AS revenue,
             SUM(quantity * (unit_price - unit_cost)) AS profit
      FROM sales
      WHERE at >= ? AND at < ?
      GROUP BY product_name, unit
      ORDER BY revenue DESC, product_name
      LIMIT ?''', [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch, limit]);
    return [
      for (final r in rows)
        ProductSales(
          name: r['product_name'] as String,
          unit: r['unit'] as String,
          quantity: (r['quantity'] as num).toDouble(),
          revenue: (r['revenue'] as num).toDouble(),
          profit: (r['profit'] as num).toDouble(),
        ),
    ];
  }

  @override
  Future<Receivables> receivables({int limit = 5}) async {
    final owing = (await _bills()).where((b) => b.due > 0);

    // One entry per customer: by customer record if there is one, otherwise by
    // the best identifier on the bill.
    final byCustomer = <String, Debtor>{};
    for (final b in owing) {
      final key = b.customerId != null
          ? 'c${b.customerId}'
          : b.whatsapp.isNotEmpty
              ? 'w${b.whatsapp}'
              : b.mobile.isNotEmpty
                  ? 'm${b.mobile}'
                  : b.name.isNotEmpty
                      ? 'n${b.name}'
                      : 'b${b.id}';
      final known = byCustomer[key];
      byCustomer[key] = Debtor(
        name: known != null && known.name.isNotEmpty ? known.name : b.name,
        whatsapp: known != null && known.whatsapp.isNotEmpty ? known.whatsapp : b.whatsapp,
        mobile: known != null && known.mobile.isNotEmpty ? known.mobile : b.mobile,
        due: (known?.due ?? 0) + b.due,
      );
    }
    final debtors = byCustomer.values.toList()..sort((a, b) => b.due.compareTo(a.due));
    return Receivables(
      totalDue: debtors.fold(0.0, (sum, d) => sum + d.due),
      customerCount: debtors.length,
      top: debtors.take(limit).toList(),
    );
  }

  @override
  Future<InventoryHealth> inventoryHealth({int listLimit = 5}) async {
    final db = await _database.db;
    final totals = (await db.rawQuery('''
      SELECT COUNT(*) AS products,
             COALESCE(SUM(stock * purchase_price), 0) AS at_cost,
             COALESCE(SUM(stock * selling_price), 0) AS at_price,
             COALESCE(SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END), 0) AS out_of_stock,
             COALESCE(SUM(CASE WHEN selling_price <= 0 THEN 1 ELSE 0 END), 0) AS missing_price
      FROM products''')).first;
    final unplaced = (await db.rawQuery('''
      SELECT COUNT(*) AS n FROM products p
      WHERE p.stock > 0
        AND p.stock > COALESCE((SELECT SUM(quantity) FROM stock_placements sp WHERE sp.product_id = p.id), 0) + 0.000000001
      ''')).first;
    final outNames = await db.query(
      'products',
      columns: ['name'],
      where: 'stock <= 0',
      orderBy: 'name',
      limit: listLimit,
    );
    return InventoryHealth(
      productCount: (totals['products'] as num).toInt(),
      stockValueAtCost: (totals['at_cost'] as num).toDouble(),
      stockValueAtPrice: (totals['at_price'] as num).toDouble(),
      outOfStockCount: (totals['out_of_stock'] as num).toInt(),
      outOfStock: [for (final r in outNames) r['name'] as String],
      missingPriceCount: (totals['missing_price'] as num).toInt(),
      unplacedCount: (unplaced['n'] as num).toInt(),
    );
  }
}
