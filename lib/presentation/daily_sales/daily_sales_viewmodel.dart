import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customers.dart';
import '../../domain/payments.dart';
import '../../domain/repositories.dart';
import '../../domain/sales.dart';
import '../../domain/services.dart';

/// The daily account: bills of one day, with totals, browsable day by day.
class SalesSummaryViewModel extends ChangeNotifier {
  final SalesRepository _sales;
  final Clock _clock;
  final CustomerRepository? _customers;

  /// With [_customers], a sale that has a due can be paid off from the account.
  SalesSummaryViewModel(this._sales, this._clock, {this._customers})
      : day = _clock.now();

  /// Whether dues can be collected from this screen.
  bool get canCollect => _customers != null;

  DateTime day;
  List<Bill> bills = [];
  List<PaymentReceipt> payments = [];
  DaySummary summary = const DaySummary(saleCount: 0, revenue: 0, cost: 0);
  bool loading = true;

  DateTime get _today => DateTime(_clock.now().year, _clock.now().month, _clock.now().day);
  DateTime get _dayOnly => DateTime(day.year, day.month, day.day);

  bool get isToday => _dayOnly == _today;
  String get label => dayLabel(day, _clock.now());

  Future<void> load() async {
    loading = true;
    notifyListeners();
    bills = await _sales.billsOn(day);
    payments = await _sales.paymentsOn(day);
    summary = DaySummary.of(bills).withCollected(await _sales.collectedOn(day));
    loading = false;
    notifyListeners();
  }

  /// What happened that day, newest first: sales (a [Bill]) and money received
  /// from customers paying a due (a [PaymentReceipt]).
  List<Object> get entries {
    DateTime at(Object e) => e is Bill ? e.at : (e as PaymentReceipt).payment.at;
    return [...bills, ...payments]..sort((a, b) => at(b).compareTo(at(a)));
  }

  Future<void> previousDay() {
    day = DateTime(day.year, day.month, day.day - 1);
    return load();
  }

  /// Never goes past today.
  Future<void> nextDay() {
    if (isToday) return Future.value();
    day = DateTime(day.year, day.month, day.day + 1);
    return load();
  }

  Future<void> voidBill(Bill bill) async {
    await _sales.voidBill(bill.id!);
    await load();
  }

  /// The customer of [bill] as they are now (with what they owe in all), or
  /// null if the sale has no customer.
  Future<CustomerSummary?> customerOf(Bill bill) async {
    final id = bill.customerId;
    return id == null || _customers == null ? null : _customers.byId(id);
  }

  /// Takes [amount] from the customer of [bill] against what they owe (their
  /// oldest unpaid bill first, as on the customer's page) and returns the
  /// receipt. Throws [PaymentException] if the amount is not sensible.
  Future<PaymentReceipt> collect(Bill bill, double amount) async {
    final customers = _customers!;
    final id = bill.customerId!;
    final payment = await customers.collectPayment(id, amount);
    await load();
    final after = await customers.byId(id);
    return PaymentReceipt(
      payment: payment,
      customerName: after?.name ?? bill.customerName,
      customerMobile: after?.mobile ?? bill.customerMobile,
      customerWhatsApp: after?.whatsapp ?? bill.customerWhatsApp,
      dueAfter: after?.due ?? 0,
    );
  }

  /// Adds the customer to a bill that was sold without one.
  Future<void> attachCustomer(Bill bill, CustomerInfo customer) async {
    await _sales.attachCustomer(bill.id!, customer);
    await load();
  }
}
