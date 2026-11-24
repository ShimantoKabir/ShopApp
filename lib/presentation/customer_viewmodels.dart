import 'package:flutter/foundation.dart';

import '../domain/customer_rules.dart';
import '../domain/customers.dart';
import '../domain/payments.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';

/// The customer list: everyone, searchable, optionally only those who owe.
class CustomerListViewModel extends ChangeNotifier {
  final CustomerRepository _customers;
  CustomerListViewModel(this._customers);

  List<CustomerSummary> _all = [];
  String _query = '';
  bool _onlyDue = false;
  bool loading = true;

  bool get onlyDue => _onlyDue;
  int get totalCustomers => _all.length;

  /// What all customers together owe.
  double get totalDue => _all.fold(0.0, (sum, c) => sum + c.due);

  /// The customers matching the search (name, or any part of a phone number
  /// in either digits) and the "owes" filter. Those who owe most come first
  /// when filtering by due; otherwise the most recent buyers do.
  List<CustomerSummary> get customers {
    final text = _query.trim().toLowerCase();
    final digits = digitsOnly(text);
    final matches = _all.where((c) {
      if (_onlyDue && !c.owes) return false;
      if (text.isEmpty) return true;
      if (c.name.toLowerCase().contains(text) || c.address.toLowerCase().contains(text)) return true;
      return digits.isNotEmpty && (c.mobile.contains(digits) || c.whatsapp.contains(digits));
    }).toList();
    if (_onlyDue) matches.sort((a, b) => b.due.compareTo(a.due));
    return matches;
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    _all = await _customers.all();
    loading = false;
    notifyListeners();
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  void setOnlyDue(bool value) {
    _onlyDue = value;
    notifyListeners();
  }
}

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
