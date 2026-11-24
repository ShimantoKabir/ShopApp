/// A customer with everything they have bought from the shop, added up.
class CustomerSummary {
  final int id;
  final String name;
  final String mobile;
  final String whatsapp;
  final String address;
  final String nid;

  /// How many purchases (bills) they have made.
  final int billCount;

  /// How many different products they have bought.
  final int productCount;

  /// The total of all their bills.
  final double totalSpent;

  /// What they have paid so far.
  final double totalPaid;

  /// What they still owe.
  final double due;

  /// When they last bought something, or null if they never have.
  final DateTime? lastPurchase;

  const CustomerSummary({
    required this.id,
    this.name = '',
    this.mobile = '',
    this.whatsapp = '',
    this.address = '',
    this.nid = '',
    this.billCount = 0,
    this.productCount = 0,
    this.totalSpent = 0,
    this.totalPaid = 0,
    this.due = 0,
    this.lastPurchase,
  });

  /// The name, or a phone number for customers whose name was never taken.
  String get displayName => name.isNotEmpty ? name : (whatsapp.isNotEmpty ? whatsapp : mobile);

  bool get owes => due > 0;
}
