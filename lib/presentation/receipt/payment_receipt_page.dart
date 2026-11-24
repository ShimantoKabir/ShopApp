import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../core/language.dart';
import '../../domain/customer_rules.dart';
import '../../domain/payments.dart';
import '../../domain/settings.dart';
import '../../domain/services.dart';
import 'receipt_text.dart';

/// The receipt for money received from a customer paying a due: shown right
/// after collecting, and again any time from the daily account. It can be
/// sent to the customer's WhatsApp or shared.
class PaymentReceiptPage extends StatelessWidget {
  final PaymentReceipt receipt;
  final ReceiptSender sender;

  /// The shop's name for the receipt; the app's own name when none is given.
  final String? shopName;

  const PaymentReceiptPage({super.key, required this.receipt, required this.sender, this.shopName});

  String get _name => shopName ?? Bn.appTitle;
  String get _text => buildPaymentReceiptTextFor(receipt, shopName: _name);

  /// Where the receipt goes on WhatsApp, or null if the customer has no valid number.
  String? get _target => [receipt.customerWhatsApp, receipt.customerMobile].where(isValidMobile).firstOrNull;

  Future<void> _whatsApp(BuildContext context) async {
    final opened = await sender.sendWhatsApp(_target!, _text);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Bn.whatsAppFailed)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.paymentReceiptTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PaymentReceiptCard(receipt: receipt, shopName: _name),
            const SizedBox(height: 20),
            if (_target != null) ...[
              FilledButton.icon(
                onPressed: () => _whatsApp(context),
                icon: const Icon(Icons.chat),
                label: Text(Bn.sendWhatsApp),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () => sender.share(_text),
              icon: const Icon(Icons.share),
              label: Text(Bn.shareReceipt),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.maybePop(context), child: Text(Bn.receiptDone)),
          ],
        ),
      );
}

/// The payment receipt as it looks on screen. Always in Bangla: it is what the
/// customer is sent.
class PaymentReceiptCard extends StatelessWidget {
  final PaymentReceipt receipt;
  final String shopName;
  const PaymentReceiptCard({super.key, required this.receipt, required this.shopName});

  @override
  Widget build(BuildContext context) => Language.runAs(AppLanguage.bangla, () => _card(context));

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = receipt.payment;
    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: bold ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge),
              Text(
                value,
                style: (bold ? theme.textTheme.titleMedium : theme.textTheme.bodyLarge)
                    ?.copyWith(fontWeight: bold ? FontWeight.bold : null, color: color),
              ),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text(shopName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            Center(child: Text(Bn.paymentReceiptTitle, style: theme.textTheme.titleMedium)),
            Center(
              child: Text(
                formatDateTime(p.at),
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (receipt.customerName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('${Bn.customerLabel}: ${receipt.customerName}', style: theme.textTheme.bodyLarge),
            ],
            if (p.receivedBy.isNotEmpty)
              Text(
                '${Bn.receivedByLabel}: ${p.receivedBy}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const Divider(height: 24),
            row(Bn.paymentReceivedLabel, formatMoney(p.amount), bold: true),
            if (receipt.dueAfter > 0)
              row(Bn.paymentRemainingLabel, formatMoney(receipt.dueAfter), color: scheme.error)
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(Bn.allDuePaid, style: theme.textTheme.bodyLarge),
              ),
            const SizedBox(height: 14),
            Center(child: Text(Bn.receiptThanks, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
