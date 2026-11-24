/// A stretch of time on the dashboard, always ending today.
enum DashboardPeriod {
  today(1),
  week(7),
  month(30);

  /// How many days it covers, counting today.
  final int days;
  const DashboardPeriod(this.days);
}

/// Sales on one calendar day.
class DailyTotal {
  final DateTime day;
  final double revenue;
  final double profit;
  final int bills;
  const DailyTotal({required this.day, required this.revenue, required this.profit, required this.bills});
}

/// How well one product sold in a period.
class ProductSales {
  final String name;
  final String unit;
  final double quantity;
  final double revenue;
  final double profit;
  const ProductSales({
    required this.name,
    required this.unit,
    required this.quantity,
    required this.revenue,
    required this.profit,
  });
}

/// A customer who owes money.
class Debtor {
  final String name;
  final String whatsapp;
  final String mobile;
  final double due;
  const Debtor({required this.name, this.whatsapp = '', this.mobile = '', required this.due});
}

/// Everything customers still owe, across all days.
class Receivables {
  final double totalDue;

  /// How many different customers owe something.
  final int customerCount;

  /// The biggest debtors first (not necessarily all of them).
  final List<Debtor> top;
  const Receivables({required this.totalDue, required this.customerCount, required this.top});

  static const none = Receivables(totalDue: 0, customerCount: 0, top: []);
}

/// A snapshot of the stock room.
class InventoryHealth {
  final int productCount;

  /// What the stock cost.
  final double stockValueAtCost;

  /// What the stock would bring in at the current selling prices.
  final double stockValueAtPrice;

  final int outOfStockCount;

  /// Names of some products that are out of stock (alphabetical).
  final List<String> outOfStock;

  /// Products with no selling price yet.
  final int missingPriceCount;

  /// Products with stock that is not (fully) placed on any location.
  final int unplacedCount;

  const InventoryHealth({
    required this.productCount,
    required this.stockValueAtCost,
    required this.stockValueAtPrice,
    required this.outOfStockCount,
    required this.outOfStock,
    required this.missingPriceCount,
    required this.unplacedCount,
  });

  double get potentialProfit => stockValueAtPrice - stockValueAtCost;

  static const empty = InventoryHealth(
    productCount: 0,
    stockValueAtCost: 0,
    stockValueAtPrice: 0,
    outOfStockCount: 0,
    outOfStock: [],
    missingPriceCount: 0,
    unplacedCount: 0,
  );
}
