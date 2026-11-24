import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/repositories.dart';
import '../../domain/sales.dart';

/// One receipt, which can get its customer after the sale.
class ReceiptViewModel extends ChangeNotifier {
  final SalesRepository _sales;
  final CustomerRepository _customers;

  ReceiptViewModel(this._sales, this._customers, this._bill);

  Bill _bill;
  Bill get bill => _bill;

  /// True once the customer was added or changed from this receipt.
  bool changed = false;

  /// A customer seen before, by number (to fill in the form).
  Future<CustomerInfo?> findCustomer(String number) => _customers.findByPhone(number);

  /// Adds (or changes) the customer of this sale. Throws [SaleException].
  Future<void> attachCustomer(CustomerInfo customer) async {
    _bill = await _sales.attachCustomer(_bill.id!, customer);
    changed = true;
    notifyListeners();
  }
}
