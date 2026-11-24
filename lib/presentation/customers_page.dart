import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/customers.dart';
import '../domain/services.dart';
import 'components/components.dart';
import 'customer_viewmodels.dart';
import 'screen_factory.dart';
import 'receipt_text.dart';
import 'shell_scope.dart';
import 'widgets/contact_actions.dart';

/// Everyone who has bought from the shop: search by name or number, filter to
/// those who owe, tap one for details. The page owns (and disposes) its [viewModel].
class CustomersPage extends StatefulWidget {
  final CustomerListViewModel viewModel;
  final ScreenFactory screens;

  /// When given, each customer with a number gets call / SMS / WhatsApp buttons.
  final ContactLauncher? contacts;
  final String? shopName;
  const CustomersPage({super.key, required this.viewModel, required this.screens, this.contacts, this.shopName});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  CustomerListViewModel get _vm => widget.viewModel;

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

  Future<void> _open(CustomerSummary c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.customerDetail(c.id)));
    if (mounted) _vm.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: menuButton(context), title: Text(Bn.customersTitle), actions: cartActions(context)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            final scheme = Theme.of(context).colorScheme;
            final shown = _vm.customers;
            return Column(
              children: [
                SearchField(hint: Bn.customerSearchHint, onChanged: _vm.search),
                ChoiceChipBar<bool>(
                  options: [ChipOption(false, Bn.customerFilterAll), ChipOption(true, Bn.customerFilterDue)],
                  selected: _vm.onlyDue,
                  onSelected: (v) => _vm.setOnlyDue(v ?? false),
                ),
                SummaryBar(
                  left: Bn.customerCount(_vm.totalCustomers),
                  right: _vm.totalDue > 0 ? '${Bn.customerPeopleDue}: ${formatMoney(_vm.totalDue)}' : '',
                ),
                Expanded(
                  child: _vm.loading
                      ? const Center(child: CircularProgressIndicator())
                      : shown.isEmpty
                          ? EmptyState(
                              message: _vm.totalCustomers == 0 ? Bn.noCustomers : Bn.noCustomerMatch,
                              icon: Icons.people_outline,
                            )
                          : ListView.separated(
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              itemCount: shown.length,
                              itemBuilder: (context, i) {
                                final c = shown[i];
                                return ItemCard(
                                  title: c.displayName,
                                  subtitle: [
                                    if (c.name.isNotEmpty) (c.whatsapp.isNotEmpty ? c.whatsapp : c.mobile),
                                    c.address,
                                  ].where((s) => s.isNotEmpty).join(' • '),
                                  onTap: () => _open(c),
                                  footer: widget.contacts != null && ContactActions.canReach(c.mobile, c.whatsapp)
                                      ? ContactActions(
                                          launcher: widget.contacts!,
                                          mobile: c.mobile,
                                          whatsapp: c.whatsapp,
                                          message: c.owes
                                              ? buildDueReminderText(name: c.name, due: c.due, shopName: widget.shopName ?? Bn.appTitle)
                                              : '',
                                        )
                                      : null,
                                  leading: CircleAvatar(
                                    backgroundColor: c.owes ? scheme.errorContainer : scheme.secondaryContainer,
                                    foregroundColor: c.owes ? scheme.onErrorContainer : scheme.onSecondaryContainer,
                                    child: const Icon(Icons.person),
                                  ),
                                  chips: [
                                    InfoChip(label: Bn.customerTimes(c.billCount), icon: Icons.receipt_long_outlined),
                                    if (c.owes)
                                      InfoChip(
                                        label: '${Bn.customerDue}: ${formatMoney(c.due)}',
                                        icon: Icons.schedule,
                                        background: scheme.errorContainer,
                                        foreground: scheme.onErrorContainer,
                                      ),
                                  ],
                                  trailing: Text(
                                    formatMoney(c.totalSpent),
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      );
}
