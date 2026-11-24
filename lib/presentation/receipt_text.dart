import '../core/bangla.dart';
import '../core/language.dart';
import '../domain/settings.dart';
import '../domain/customers.dart';
import '../domain/payments.dart';
import '../domain/sales.dart';

/// The receipt as plain text, for WhatsApp / SMS / sharing. The customer's NID
/// and phone numbers are never included (it goes to their own WhatsApp).
/// Always in Bangla, whatever language the app is shown in: it goes to the customer.
String buildReceiptText(Bill bill, {required String shopName}) =>
    Language.runAs(AppLanguage.bangla, () => _receiptText(bill, shopName));

String _receiptText(Bill bill, String shopName) {
  final b = StringBuffer()
    ..writeln(shopName)
    ..writeln('${Bn.receiptNo}: ${toBanglaDigits('${bill.id ?? ''}')} • ${formatDateTime(bill.at)}');
  if (bill.customerName.isNotEmpty) b.writeln('${Bn.customerLabel}: ${bill.customerName}');
  if (bill.customerAddress.isNotEmpty) b.writeln('${Bn.customerAddress}: ${bill.customerAddress}');
  b.writeln('────────────────');
  for (final l in bill.lines) {
    b
      ..writeln(l.productName)
      ..writeln('  ${formatNumber(l.quantity)} ${Bn.unitName(l.unit)} × ${formatMoney(l.unitPrice)} = ${formatMoney(l.total)}');
  }
  b
    ..writeln('────────────────')
    ..writeln('${Bn.saleTotal}: ${formatMoney(bill.total)}')
    ..writeln('${Bn.paidLabel}: ${formatMoney(bill.paid)}');
  if (bill.due > 0) b.writeln('${Bn.dueLabel}: ${formatMoney(bill.due)}');
  b
    ..writeln()
    ..write(Bn.receiptThanks);
  return b.toString();
}

/// A reminder to send a customer who owes money (by SMS or WhatsApp).
/// Always in Bangla, whatever language the app is shown in.
String buildDueReminderText({required String name, required double due, required String shopName}) =>
    Language.runAs(AppLanguage.bangla, () => Bn.dueReminder(name, due, shopName));

/// A note for the customer's WhatsApp that their payment was received, and
/// what (if anything) they still owe. [after] is the customer as they are
/// after this payment. No phone number or NID is included. Always in Bangla.
String buildPaymentReceiptText(Payment payment, CustomerSummary after, {required String shopName}) =>
    Language.runAs(AppLanguage.bangla, () => _paymentText(payment, after, shopName));

String _paymentText(Payment payment, CustomerSummary after, String shopName) {
  final b = StringBuffer()
    ..writeln(shopName)
    ..writeln('${Bn.paymentReceiptTitle} • ${formatDateTime(payment.at)}');
  if (after.name.isNotEmpty) b.writeln('${Bn.customerLabel}: ${after.name}');
  b
    ..writeln('────────────────')
    ..writeln('${Bn.paymentReceivedLabel}: ${formatMoney(payment.amount)}')
    ..writeln(after.due > 0 ? '${Bn.paymentRemainingLabel}: ${formatMoney(after.due)}' : Bn.allDuePaid)
    ..writeln()
    ..write(Bn.receiptThanks);
  return b.toString();
}
