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
