import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/payments.dart';
import '../../domain/sales.dart';
import '../../domain/services.dart';
import '../components/components.dart';
import '../labels.dart';
import '../screen_factory.dart';
import '../home_shell/shell_scope.dart';
import '../receipt/payment_receipt_page.dart';
import '../receipt/receipt_text.dart';
import 'daily_sales_viewmodel.dart';
import '../widgets/attach_customer_dialog.dart';
import '../widgets/contact_actions.dart';
import '../widgets/sale_widgets.dart';

/// The daily account: totals and the bills of one day, browsable day by day.
/// Tap a bill for its receipt (to send again); swipe to cancel it (the stock
/// comes back). The page owns (and disposes) its [viewModel].
class DailySalesPage extends StatefulWidget {
  final SalesSummaryViewModel viewModel;
  final ScreenFactory screens;

  /// When given, a bill with a due gets call / SMS / WhatsApp buttons.
  final ContactLauncher? contacts;
  final String? shopName;

  /// When given, "Add customer" offers "choose from contacts".
  final ContactPicker? contactPicker;

  /// When given, a payment received can be opened as a receipt and sent.
  final ReceiptSender? sender;
  const DailySalesPage({
    super.key,
    required this.viewModel,
    required this.screens,
    this.contacts,
    this.shopName,
    this.contactPicker,
    this.sender,
  });

  @override
  State<DailySalesPage> createState() => _DailySalesPageState();
}

class _DailySalesPageState extends State<DailySalesPage> {
  SalesSummaryViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  Future<void> _void(Bill bill) async {
    await _vm.voidBill(bill);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(Bn.saleVoided)));
  }

  /// The receipt can add a customer, so the list is refreshed when it closes.
  Future<void> _openReceipt(Bill bill) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.receipt(bill)));
    if (mounted) await _vm.load();
  }

  void _openPaymentReceipt(PaymentReceipt r) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentReceiptPage(receipt: r, sender: widget.sender!, shopName: widget.shopName),
        ),
      );

  /// Money received from a customer paying a due: tap for its receipt.
  Widget _paymentTile(PaymentReceipt r) {
    final scheme = Theme.of(context).colorScheme;
    final p = r.payment;
    final who = r.customerName.isNotEmpty ? r.customerName : (r.customerMobile.isNotEmpty ? r.customerMobile : Bn.customerLabel);
    return ItemCard(
      title: who,
      subtitle: [
        '${Bn.paymentReceivedTitle} • ${formatTime(p.at)}',
        if (p.receivedBy.isNotEmpty) '${Bn.receivedByLabel}: ${p.receivedBy}',
      ].join('\n'),
      onTap: widget.sender == null ? null : () => _openPaymentReceipt(r),
      leading: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        foregroundColor: scheme.onTertiaryContainer,
        child: const Icon(Icons.south_west),
      ),
      chips: [
        if (r.dueAfter > 0)
          InfoChip(label: '${Bn.paymentRemainingLabel}: ${formatMoney(r.dueAfter)}', icon: Icons.schedule)
        else
          InfoChip(label: Bn.allDuePaid, icon: Icons.check_circle_outline),
      ],
      trailing: Text(
        formatMoney(p.amount),
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700),
      ),
    );
  }

  /// For a sale made without a customer: add one now.
  Future<void> _addCustomer(Bill bill) async {
    final info = await showAttachCustomerDialog(context, picker: widget.contactPicker);
    if (info == null || !mounted) return;
    try {
      await _vm.attachCustomer(bill, info);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Bn.customerAdded)));
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _addCustomerButton(Bill b) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => _addCustomer(b),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: Text(Bn.addCustomer),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      );

  /// Asks how much was received (the customer's whole due is filled in; type
  /// less for a part payment), records it, then shows the new receipt.
  Future<void> _collect(Bill bill) async {
    final customer = await _vm.customerOf(bill);
    if (customer == null || !mounted) return;
    final amount = await showNumberDialog(
      context,
      title: Bn.collectTitle,
      label: '${Bn.collectAmountLabel} (${Bn.dueLabel}: ${formatMoney(customer.due)})',
      initial: customer.due,
      confirmLabel: Bn.collectConfirm,
    );
    if (amount == null) return;
    final PaymentReceipt receipt;
    try {
      receipt = await _vm.collect(bill, amount);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (mounted && widget.sender != null) _openPaymentReceipt(receipt);
  }

  Widget _collectButton(Bill b) => TextButton.icon(
        onPressed: () => _collect(b),
        icon: const Icon(Icons.payments_outlined, size: 18),
        label: Text(Bn.collectPayment),
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      );

  /// For a bill that still has a due: take money, and/or reach the customer about it.
  Widget? _dueFooter(Bill b) {
    final reach = widget.contacts != null && ContactActions.canReach(b.customerMobile, b.customerWhatsApp);
    final collect = _vm.canCollect && b.customerId != null;
    if (!reach && !collect) return null;
    // The main action on the left, call and share on the right.
    return Row(children: [
      if (collect) _collectButton(b),
      const Spacer(),
      if (reach) _reminder(b),
    ]);
  }

  /// For a bill that still has a due: reach the customer about it.
  Widget _reminder(Bill b) => ContactActions(
        launcher: widget.contacts!,
        mobile: b.customerMobile,
        whatsapp: b.customerWhatsApp,
        message: buildDueReminderText(name: b.customerName, due: b.due, shopName: widget.shopName ?? Bn.appTitle),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: menuButton(context), title: Text(Bn.accountTitle), actions: cartActions(context)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(onPressed: _vm.previousDay, icon: const Icon(Icons.chevron_left), tooltip: Bn.previousDay),
                  SizedBox(
                    width: 140,
                    child: Text(_vm.label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    onPressed: _vm.isToday ? null : _vm.nextDay,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: Bn.nextDay,
                  ),
                ],
              ),
              DaySummaryCard(summary: _vm.summary),
              Expanded(
                child: AsyncListView<Object>(
                  items: _vm.entries,
                  loading: _vm.loading,
                  emptyMessage: Bn.noSalesThatDay,
                  itemKey: (e) => e is Bill ? 'bill-${e.id}' : 'payment-${(e as PaymentReceipt).payment.id}',
                  // Only a sale can be cancelled; money received stays on record.
                  canDelete: (e) => e is Bill,
                  onDelete: (e) => _void(e as Bill),
                  deleteConfirm: (ctx) => showConfirmDialog(
                    ctx,
                    message: Bn.voidSaleConfirm,
                    confirmLabel: Bn.voidSaleAction,
                  ),
                  itemBuilder: (context, e) => e is PaymentReceipt ? _paymentTile(e) : _billTile(e as Bill),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _billTile(Bill b) => BillTile(
        bill: b,
        onTap: () => _openReceipt(b),
        footer: !b.hasCustomer
            ? _addCustomerButton(b)
            : (b.due > 0 ? _dueFooter(b) : null),
      );
}
