import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/dashboard.dart';
import '../components/components.dart';
import 'dashboard_viewmodel.dart';
import '../home_shell/shell_scope.dart';

/// How the business stands: sales and profit for a period, a day-by-day trend,
/// best sellers, money owed by customers and the state of the stock.
/// The page owns (and disposes) its [viewModel].
class DashboardPage extends StatefulWidget {
  final DashboardViewModel viewModel;
  const DashboardPage({super.key, required this.viewModel});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardViewModel get _vm => widget.viewModel;

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

  String _periodLabel(DashboardPeriod p) => switch (p) {
        DashboardPeriod.today => Bn.periodToday,
        DashboardPeriod.week => Bn.periodWeek,
        DashboardPeriod.month => Bn.periodMonth,
      };

  String? _changeNote() {
    final change = _vm.salesChange;
    if (change == null) return _vm.summary.revenue > 0 ? Bn.dashNoComparison : null;
    final percent = '${toBanglaDigits((change.abs() * 100).round().toString())}%';
    if (change.abs() < 0.005) return null;
    return change > 0 ? Bn.dashUp(percent) : Bn.dashDown(percent);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: menuButton(context), title: Text(Bn.navDashboard), actions: cartActions(context)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => RefreshIndicator(
            onRefresh: _vm.load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ChoiceChipBar<DashboardPeriod>(
                  options: [for (final p in DashboardPeriod.values) ChipOption(p, _periodLabel(p))],
                  selected: _vm.period,
                  onSelected: (p) => _vm.choose(p ?? DashboardPeriod.today),
                  allLabel: null,
                ),
                const SizedBox(height: 12),
                _figures(),
                const SizedBox(height: 12),
                _trend(),
                const SizedBox(height: 12),
                _topProducts(),
                const SizedBox(height: 12),
                _receivables(),
                const SizedBox(height: 12),
                _stock(),
              ],
            ),
          ),
        ),
      );

  Widget _figures() {
    final s = _vm.summary;
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        StatTile(label: Bn.dashSales, value: formatMoney(s.revenue), icon: Icons.sell_outlined, note: _changeNote()),
        StatTile(
          label: Bn.dashProfit,
          value: formatMoney(s.profit),
          icon: Icons.trending_up,
          color: s.profit < 0 ? scheme.error : Colors.green.shade700,
        ),
        StatTile(label: Bn.dashBills, value: formatNumber(s.saleCount.toDouble()), icon: Icons.receipt_long_outlined),
        StatTile(label: Bn.dashAverageBill, value: formatMoney(_vm.averageBill.roundToDouble()), icon: Icons.calculate_outlined),
        StatTile(label: Bn.dashCollected, value: formatMoney(s.collected), icon: Icons.south_west),
        StatTile(
          label: Bn.dashNewDue,
          value: formatMoney(s.due),
          icon: Icons.schedule,
          color: s.due > 0 ? scheme.error : null,
        ),
      ],
    );
  }

  Widget _trend() {
    final days = _vm.trend;
    final n = days.length;
    return SectionCard(
      title: Bn.dashSalesTrend,
      icon: Icons.bar_chart,
      children: [
        BarChart(
          items: [
            for (var i = 0; i < n; i++)
              BarItem(
                // A month has too many bars to name each one: every fifth only.
                n > 10 && (n - 1 - i) % 5 != 0 ? '' : toBanglaDigits('${days[i].day.day}'),
                days[i].revenue,
              ),
          ],
          valueLabel: (v) => formatMoney(v),
        ),
      ],
    );
  }

  Widget _topProducts() {
    final top = _vm.topProducts;
    return SectionCard(
      title: Bn.dashTopProducts,
      icon: Icons.emoji_events_outlined,
      children: [
        if (top.isEmpty)
          Text(Bn.dashNoSales, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          for (final p in top) _row('${p.name}  •  ${formatNumber(p.quantity)} ${Bn.unitName(p.unit)}', formatMoney(p.revenue)),
      ],
    );
  }

  Widget _receivables() {
    final r = _vm.receivables;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: Bn.dashReceivables,
      icon: Icons.account_balance_wallet_outlined,
      children: [
        if (r.totalDue <= 0)
          Text(Bn.dashNoDue, style: TextStyle(color: scheme.onSurfaceVariant))
        else ...[
          _row(
            '${Bn.dashTotalDue}  •  ${Bn.dashCustomers(r.customerCount)}',
            formatMoney(r.totalDue),
            valueColor: scheme.error,
            bold: true,
          ),
          const Divider(),
          for (final d in r.top) _row(d.name.isEmpty ? (d.mobile.isEmpty ? d.whatsapp : d.mobile) : d.name, formatMoney(d.due)),
          if (r.customerCount > r.top.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${Bn.dashMore} ${Bn.dashCustomers(r.customerCount - r.top.length)}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ],
    );
  }

  Widget _stock() {
    final i = _vm.inventory;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: Bn.dashStock,
      icon: Icons.inventory_2_outlined,
      children: [
        _row(Bn.dashProducts, formatNumber(i.productCount.toDouble())),
        _row(Bn.dashStockCost, formatMoney(i.stockValueAtCost)),
        _row(Bn.dashStockWorth, formatMoney(i.stockValueAtPrice)),
        _row(Bn.dashProfit, formatMoney(i.potentialProfit), valueColor: Colors.green.shade700),
        const Divider(),
        Text(Bn.dashNeedsAttention, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (i.outOfStockCount == 0 && i.missingPriceCount == 0 && i.unplacedCount == 0)
          Text(Bn.dashAllInStock, style: TextStyle(color: scheme.onSurfaceVariant))
        else ...[
          if (i.outOfStockCount > 0) _row(Bn.dashOutOfStock, formatNumber(i.outOfStockCount.toDouble()), valueColor: scheme.error),
          for (final name in i.outOfStock)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 2),
              child: Text('• $name', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          if (i.missingPriceCount > 0) _row(Bn.dashMissingPrice, formatNumber(i.missingPriceCount.toDouble())),
          if (i.unplacedCount > 0) _row(Bn.dashUnplaced, formatNumber(i.unplacedCount.toDouble())),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: valueColor)),
          ],
        ),
      );
}
