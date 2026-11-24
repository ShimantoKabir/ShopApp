import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/customer_rules.dart';
import '../domain/customers.dart';
import '../domain/payments.dart';
import '../domain/services.dart';
import 'components/components.dart';
import 'customer_viewmodels.dart';
import 'labels.dart';
import 'receipt_text.dart';
import 'screen_factory.dart';
import 'widgets/contact_actions.dart';
import 'widgets/sale_widgets.dart';

/// One customer: contact details, what they bought and owe, and every bill
/// (tap one for its receipt). The page owns (and disposes) its [viewModel].
class CustomerDetailPage extends StatefulWidget {
  final CustomerDetailViewModel viewModel;
  final int customerId;
  final ScreenFactory screens;
  final ReceiptSender sender;

  /// When given, there are call / SMS / WhatsApp buttons for this customer.
  final ContactLauncher? contacts;

  /// The shop's name for receipts; the app's own name when none is given.
  final String? shopName;
  const CustomerDetailPage({
    super.key,
    required this.viewModel,
    required this.customerId,
    required this.screens,
    required this.sender,
    this.contacts,
    this.shopName,
  });

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  CustomerDetailViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.load(widget.customerId);
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Asks how much was received (the whole due is filled in; type less for a
  /// part payment), records it, then offers to tell the customer on WhatsApp.
  Future<void> _collect(CustomerSummary c) async {
    final amount = await showNumberDialog(
      context,
      title: Bn.collectTitle,
      label: '${Bn.collectAmountLabel} (${Bn.dueLabel}: ${formatMoney(c.due)})',
      initial: c.due,
      confirmLabel: Bn.collectConfirm,
    );
    if (amount == null) return;
    final Payment payment;
    try {
      payment = await _vm.collect(amount);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _say(message);
      return;
    }
    if (!mounted) return;
    final after = _vm.customer;
    if (after == null) return;
    final send = await showConfirmDialog(
      context,
      message: Bn.paymentDone(payment.amount, after.due),
      confirmLabel: Bn.sendPaymentReceipt,
      cancelLabel: Bn.receiptDone,
    );
    if (send && mounted) await _sendReceipt(payment, after);
  }

  Future<void> _sendReceipt(Payment payment, CustomerSummary c) async {
    final text = buildPaymentReceiptText(payment, c, shopName: widget.shopName ?? Bn.appTitle);
    final number = [c.whatsapp, c.mobile].where(isValidMobile).firstOrNull;
    if (number == null) {
      await widget.sender.share(text);
      return;
    }
    final opened = await widget.sender.sendWhatsApp(number, text);
    if (!opened) _say(Bn.whatsAppFailed);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          final c = _vm.customer;
          return Scaffold(
            appBar: AppBar(title: Text(c?.displayName ?? Bn.customerDetailTitle)),
            body: _vm.loading
                ? const Center(child: CircularProgressIndicator())
                : c == null
                    ? EmptyState(message: Bn.customerNotFound, icon: Icons.person_off_outlined)
                    : _content(c),
          );
        },
      );

  Widget _content(CustomerSummary c) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: Bn.customerInfoSection,
          icon: Icons.person_outline,
          children: [
            if (c.name.isNotEmpty) _info(Icons.badge_outlined, c.name),
            if (c.whatsapp.isNotEmpty) _info(Icons.chat_outlined, c.whatsapp),
            if (c.mobile.isNotEmpty && c.mobile != c.whatsapp) _info(Icons.phone_outlined, c.mobile),
            if (c.address.isNotEmpty) _info(Icons.place_outlined, c.address),
            if (c.nid.isNotEmpty) _info(Icons.credit_card_outlined, '${Bn.customerNidLabel}: ${c.nid}'),
            if (widget.contacts != null && ContactActions.canReach(c.mobile, c.whatsapp))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ContactActions(
                  launcher: widget.contacts!,
                  mobile: c.mobile,
                  whatsapp: c.whatsapp,
                  message: c.owes ? buildDueReminderText(name: c.name, due: c.due, shopName: widget.shopName ?? Bn.appTitle) : '',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: [
            StatTile(label: Bn.customerSpent, value: formatMoney(c.totalSpent), icon: Icons.shopping_bag_outlined),
            StatTile(
              label: Bn.customerDue,
              value: formatMoney(c.due),
              icon: Icons.schedule,
              color: c.owes ? scheme.error : null,
            ),
            StatTile(label: Bn.customerPaid, value: formatMoney(c.totalPaid), icon: Icons.payments_outlined),
            StatTile(label: Bn.customerBills, value: Bn.customerTimes(c.billCount), icon: Icons.receipt_long_outlined),
            StatTile(label: Bn.customerProducts, value: formatNumber(c.productCount.toDouble()), icon: Icons.category_outlined),
            StatTile(
              label: Bn.customerLastBuy,
              value: c.lastPurchase == null ? '-' : dayLabel(c.lastPurchase!, DateTime.now()),
              icon: Icons.event_outlined,
            ),
          ],
        ),
        if (c.owes) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _collect(c),
            icon: const Icon(Icons.payments_outlined),
            label: Text(Bn.collectPayment),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ],
        const SizedBox(height: 16),
        Text(Bn.paymentHistory, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_vm.payments.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(Bn.noPayments, style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          for (final p in _vm.payments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ItemCard(
                title: formatMoney(p.amount),
                subtitle: p.receivedBy.isEmpty ? formatDateTime(p.at) : '${formatDateTime(p.at)} • ${Bn.receivedByLabel}: ${p.receivedBy}',
                leading: CircleAvatar(
                  backgroundColor: scheme.tertiaryContainer,
                  foregroundColor: scheme.onTertiaryContainer,
                  child: const Icon(Icons.south_west),
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text(Bn.customerHistory, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_vm.bills.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(Bn.customerNoHistory, style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          for (final b in _vm.bills)
            BillTile(
              bill: b,
              showDate: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.receipt(b))),
            ),
      ],
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
