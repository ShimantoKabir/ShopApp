import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../core/language.dart';
import '../../domain/customer_rules.dart';
import '../../domain/sales.dart';
import '../../domain/settings.dart';
import '../../domain/services.dart';
import '../components/components.dart';
import '../labels.dart';
import 'receipt_text.dart';
import 'receipt_viewmodel.dart';
import '../widgets/attach_customer_dialog.dart';

/// A bill's receipt: look at it, send it to the customer's WhatsApp, or share
/// it. Opened after a sale, and again any time from the daily account.
class ReceiptPage extends StatefulWidget {
  final Bill bill;
  final ReceiptSender sender;
  /// The shop's name for the receipt; the app's own name when none is given.
  final String? shopName;

  /// When given, a sale made without a customer gets an "Add customer" button.
  /// The page owns (and disposes) it.
  final ReceiptViewModel? viewModel;

  /// Whether this person may replace a customer that is already on the sale
  /// (the owner). Adding one to a sale that has none is open to everybody.
  final bool canChangeCustomer;

  /// When given, the add-customer form offers "choose from contacts".
  final ContactPicker? contactPicker;

  const ReceiptPage({
    super.key,
    required this.bill,
    required this.sender,
    this.shopName,
    this.viewModel,
    this.canChangeCustomer = false,
    this.contactPicker,
  });

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  ReceiptSender get sender => widget.sender;
  String? get shopName => widget.shopName;
  ReceiptViewModel? get _vm => widget.viewModel;
  Bill get bill => _vm?.bill ?? widget.bill;

  @override
  void dispose() {
    _vm?.dispose();
    super.dispose();
  }

  String get _text => buildReceiptText(bill, shopName: shopName ?? Bn.appTitle);

  /// A sale without a customer can get one now; changing one is for the owner.
  bool get _canAddCustomer => _vm != null && bill.id != null && (!bill.hasCustomer || widget.canChangeCustomer);

  Future<void> _addCustomer(BuildContext context) async {
    final vm = _vm!;
    final info = await showAttachCustomerDialog(
      context,
      initial: CustomerInfo(
        name: bill.customerName,
        mobile: bill.customerMobile,
        address: bill.customerAddress,
        whatsapp: bill.customerWhatsApp,
      ),
      dueRequired: bill.due > 0,
      lookUp: vm.findCustomer,
      picker: widget.contactPicker,
    );
    if (info == null || !context.mounted) return;
    try {
      await vm.attachCustomer(info);
      if (context.mounted) _say(context, Bn.customerAdded);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      if (context.mounted) _say(context, message);
    }
  }

  void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// The number to send to: the WhatsApp number given at the sale, or (for
  /// bills made before that was required) the mobile number. Null if neither.
  String? get _target => [bill.customerWhatsApp, bill.customerMobile].where(isValidMobile).firstOrNull;

  /// Sends to the bill's WhatsApp number; if there is none, asks for one.
  Future<void> _whatsApp(BuildContext context) async {
    var mobile = _target ?? '';
    if (!isValidMobile(mobile)) {
      final typed = await showTextPromptDialog(
        context,
        title: Bn.whatsAppNumberLabel,
        hint: toBanglaDigits('01712345678'),
        confirmLabel: Bn.send,
      );
      if (typed == null) return;
      if (!isValidMobile(typed)) {
        if (context.mounted) _say(context, Bn.whatsAppBadNumber);
        return;
      }
      mobile = typed;
    }
    final opened = await sender.sendWhatsApp(mobile, _text);
    if (!opened && context.mounted) _say(context, Bn.whatsAppFailed);
  }

  @override
  Widget build(BuildContext context) => _vm == null ? _page(context) : ListenableBuilder(listenable: _vm!, builder: (c, _) => _page(c));

  Widget _page(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.receiptTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ReceiptCard(bill: bill, shopName: shopName ?? Bn.appTitle),
            const SizedBox(height: 20),
            if (_canAddCustomer) ...[
              // Same size and spacing as the WhatsApp and share buttons below.
              OutlinedButton.icon(
                onPressed: () => _addCustomer(context),
                icon: Icon(bill.hasCustomer ? Icons.edit_outlined : Icons.person_add_alt_1_outlined),
                label: Text(bill.hasCustomer ? Bn.changeCustomer : Bn.addCustomer),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: () => _whatsApp(context),
              icon: const Icon(Icons.chat),
              label: Text(Bn.sendWhatsApp),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
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

/// The receipt as it looks on screen.
class ReceiptCard extends StatelessWidget {
  final Bill bill;
  final String shopName;
  const ReceiptCard({super.key, required this.bill, required this.shopName});

  /// The card shows what the customer is sent, so it is always in Bangla.
  @override
  Widget build(BuildContext context) => Language.runAs(AppLanguage.bangla, () => _card(context));

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            Center(
              child: Text(
                '${Bn.receiptNo}: ${toBanglaDigits('${bill.id ?? ''}')} • ${formatDateTime(bill.at)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (bill.customerName.isNotEmpty || bill.customerAddress.isNotEmpty) const SizedBox(height: 10),
            if (bill.customerName.isNotEmpty)
              Text('${Bn.customerLabel}: ${bill.customerName}', style: theme.textTheme.bodyLarge),
            if (bill.customerAddress.isNotEmpty)
              Text('${Bn.customerAddress}: ${bill.customerAddress}', style: theme.textTheme.bodyMedium),
            if (bill.soldBy.isNotEmpty)
              Text('${Bn.soldByLabel}: ${bill.soldBy}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const Divider(height: 24),
            for (final l in bill.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.productName, style: theme.textTheme.titleSmall),
                          Text(
                            '${formatNumber(l.quantity)} ${Bn.unitName(l.unit)} × ${formatMoney(l.unitPrice)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(formatMoney(l.total), style: theme.textTheme.titleSmall),
                  ],
                ),
              ),
            const Divider(height: 24),
            row(Bn.saleTotal, formatMoney(bill.total), bold: true),
            row(Bn.paidLabel, formatMoney(bill.paid)),
            if (bill.due > 0) row(Bn.dueLabel, formatMoney(bill.due), bold: true, color: scheme.error),
            const SizedBox(height: 14),
            Center(child: Text(Bn.receiptThanks, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
