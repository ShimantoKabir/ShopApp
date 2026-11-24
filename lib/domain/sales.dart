import 'stock.dart';

/// One line of a bill: a product sold. The price and cost are copied at the
/// time of the sale, so later price changes (or deleting the product) never
/// alter history.
class Sale {
  final int? id;
  final int? billId;

  /// Null if the product was deleted after the sale.
  final int? productId;
  final String productName;
  final String unit;

  /// Set when the units came from exactly one location.
  final int? locationId;

  final double quantity;
  final double unitPrice;
  final double unitCost;
  final DateTime at;

  const Sale({
    this.id,
    this.billId,
    this.productId,
    required this.productName,
    required this.unit,
    this.locationId,
    required this.quantity,
    required this.unitPrice,
    required this.unitCost,
    required this.at,
  });

  double get total => quantity * unitPrice;
  double get cost => quantity * unitCost;
  double get profit => total - cost;
}

/// A product to sell, as given to checkout.
class SaleLine {
  final int productId;
  final double quantity;
  final double unitPrice;

  /// Null = let the app choose where the units come from.
  final int? fromLocationId;

  const SaleLine({required this.productId, required this.quantity, required this.unitPrice, this.fromLocationId});
}

/// Who bought.
///
/// Every sale needs an [address] and a [whatsapp] number (the receipt goes
/// there). [name], [mobile] and [nid] are optional, except that all three are
/// required when part of the bill is left unpaid (due).
class CustomerInfo {
  final String name;
  final String mobile;
  final String nid;
  final String address;

  /// The number the receipt is sent to. Can be the same as [mobile].
  final String whatsapp;

  const CustomerInfo({this.name = '', this.mobile = '', this.nid = '', this.address = '', this.whatsapp = ''});

  bool get isEmpty =>
      name.trim().isEmpty &&
      mobile.trim().isEmpty &&
      nid.trim().isEmpty &&
      address.trim().isEmpty &&
      whatsapp.trim().isEmpty;
}

/// One customer purchase: one or more lines, an optional customer, and what
/// was paid. If less than the total was paid, the rest is [due].
class Bill {
  final int? id;
  final int? customerId;

  /// Copied onto the bill so a receipt stays the same even if the customer's
  /// record changes. (The NID is deliberately not copied: it is not printed.)
  final String customerName;
  final String customerMobile;
  final String customerAddress;

  /// Where the receipt is sent. Empty only on bills made before this was required.
  final String customerWhatsApp;

  final double paid;
  final DateTime at;
  final List<Sale> lines;

  /// Who made the sale (the signed-in user's name). Empty on old bills.
  final String soldBy;

  const Bill({
    this.id,
    this.customerId,
    this.customerName = '',
    this.customerMobile = '',
    this.customerAddress = '',
    this.customerWhatsApp = '',
    required this.paid,
    required this.at,
    required this.lines,
    this.soldBy = '',
  });

  double get total => lines.fold(0.0, (sum, l) => sum + l.total);
  double get cost => lines.fold(0.0, (sum, l) => sum + l.cost);
  double get profit => total - cost;

  /// What the customer still owes (zero if fully paid).
  double get due {
    final rest = total - paid;
    return rest < stockEpsilon ? 0 : rest;
  }

  bool get hasCustomer =>
      customerName.isNotEmpty || customerMobile.isNotEmpty || customerWhatsApp.isNotEmpty;
}

/// Totals for a list of bills (normally one day).
class DaySummary {
  final int saleCount;
  final double revenue;
  final double cost;

  /// Sum of what customers still owe on these bills.
  final double due;

  /// Money received in the same period from customers paying off earlier dues.
  /// (Not part of [revenue]: that was counted on the day of the sale.)
  final double collected;

  const DaySummary({
    required this.saleCount,
    required this.revenue,
    required this.cost,
    this.due = 0,
    this.collected = 0,
  });

  double get profit => revenue - cost;

  DaySummary withCollected(double amount) =>
      DaySummary(saleCount: saleCount, revenue: revenue, cost: cost, due: due, collected: amount);

  factory DaySummary.of(Iterable<Bill> bills) {
    var count = 0;
    var revenue = 0.0;
    var cost = 0.0;
    var due = 0.0;
    for (final b in bills) {
      count++;
      revenue += b.total;
      cost += b.cost;
      due += b.due;
    }
    return DaySummary(saleCount: count, revenue: revenue, cost: cost, due: due);
  }
}

enum SaleProblem {
  /// A bill with no items.
  emptyBill,

  /// Every sale needs the customer's WhatsApp number (the receipt goes there).
  contactRequired,

  /// Paid amount is negative or more than the total.
  invalidPayment,

  /// Part of the bill is unpaid, so name, mobile, NID and address are required.
  customerRequiredForDue,

  /// A mobile number or NID was entered but is not valid.
  invalidCustomer,

  /// There is no such bill (for example it was cancelled on another phone).
  unknownBill,
}

/// A billing rule was broken. Carries a machine-readable [problem] so the UI
/// can show a message in the user's language.
class SaleException implements Exception {
  final SaleProblem problem;
  const SaleException(this.problem);

  @override
  String toString() => 'SaleException($problem)';
}
