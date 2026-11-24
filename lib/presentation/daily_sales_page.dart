import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import 'components/components.dart';
import 'screen_factory.dart';
import 'shell_scope.dart';
import 'receipt_text.dart';
import 'viewmodels.dart';
import 'widgets/contact_actions.dart';
import 'widgets/sale_widgets.dart';

/// The daily account: totals and the bills of one day, browsable day by day.
/// Tap a bill for its receipt (to send again); swipe to cancel it (the stock
/// comes back). The page owns (and disposes) its [viewModel].
class DailySalesPage extends StatefulWidget {
  final SalesSummaryViewModel viewModel;
  final ScreenFactory screens;

  /// When given, a bill with a due gets call / SMS / WhatsApp buttons.
  final ContactLauncher? contacts;
  final String? shopName;
  const DailySalesPage({super.key, required this.viewModel, required this.screens, this.contacts, this.shopName});

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

  void _openReceipt(Bill bill) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.receipt(bill)));

  /// For a bill that still has a due: reach the customer about it.
  Widget _reminder(Bill b) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Bn.remindDue, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 10),
          ContactActions(
            launcher: widget.contacts!,
            mobile: b.customerMobile,
            whatsapp: b.customerWhatsApp,
            message: buildDueReminderText(name: b.customerName, due: b.due, shopName: widget.shopName ?? Bn.appTitle),
          ),
        ],
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
                child: AsyncListView<Bill>(
                  items: _vm.bills,
                  loading: _vm.loading,
                  emptyMessage: Bn.noSalesThatDay,
                  itemKey: (b) => b.id!,
                  onDelete: _void,
                  deleteConfirm: (ctx) => showConfirmDialog(
                    ctx,
                    message: Bn.voidSaleConfirm,
                    confirmLabel: Bn.voidSaleAction,
                  ),
                  itemBuilder: (context, b) => BillTile(
                    bill: b,
                    onTap: () => _openReceipt(b),
                    footer: widget.contacts != null && b.due > 0 && ContactActions.canReach(b.customerMobile, b.customerWhatsApp)
                        ? _reminder(b)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
