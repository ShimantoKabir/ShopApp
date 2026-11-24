import 'package:flutter/foundation.dart';

import '../../domain/customers.dart';
import '../../domain/payments.dart';
import '../../domain/repositories.dart';
import '../../domain/sales.dart';

/// One customer: their totals and every bill they have had.
class CustomerDetailViewModel extends ChangeNotifier {
  final CustomerRepository _customers;
  final SalesRepository _sales;
  CustomerDetailViewModel(this._customers, this._sales);

  CustomerSummary? customer;
  List<Bill> bills = [];
  List<Payment> payments = [];
  bool loading = true;

  Future<void> load(int customerId) async {
    loading = true;
    notifyListeners();
    customer = await _customers.byId(customerId);
    bills = customer == null ? [] : await _sales.billsOfCustomer(customerId);
    payments = customer == null ? [] : await _customers.paymentsOf(customerId);
    loading = false;
    notifyListeners();
  }

  /// Takes [amount] off what this customer owes. Throws [PaymentException] if
  /// it is not a sensible amount (nothing changes then). Refreshes everything
  /// shown, so [customer] already reflects the payment when this returns.
  Future<Payment> collect(double amount) async {
    final id = customer!.id;
    final payment = await _customers.collectPayment(id, amount);
    await load(id);
    return payment;
  }
}
