/// Money received from a customer against what they owe.
class Payment {
  final int? id;
  final int customerId;
  final double amount;
  final DateTime at;

  /// Who took the money. Empty on old entries.
  final String receivedBy;
  const Payment({this.id, required this.customerId, required this.amount, required this.at, this.receivedBy = ''});
}

enum PaymentProblem {
  /// Zero, negative or not a number.
  invalidAmount,

  /// More than the customer owes in total.
  exceedsDue,

  /// There is no such customer.
  unknownCustomer,
}

/// A payment rule was broken; nothing was recorded.
class PaymentException implements Exception {
  final PaymentProblem problem;
  const PaymentException(this.problem);

  @override
  String toString() => 'PaymentException($problem)';
}

/// A payment as it appears on its receipt: who paid, how much, and what they
/// still owed straight after it.
class PaymentReceipt {
  final Payment payment;
  final String customerName;
  final String customerMobile;
  final String customerWhatsApp;

  /// What the customer still owed right after this payment (zero if nothing).
  final double dueAfter;

  const PaymentReceipt({
    required this.payment,
    this.customerName = '',
    this.customerMobile = '',
    this.customerWhatsApp = '',
    this.dueAfter = 0,
  });
}
