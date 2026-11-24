import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../../domain/sales.dart';
import '../components/components.dart';
import '../labels.dart';

/// One product on the sell screen: price and stock at a glance, an add-to-cart
/// button, and a tap on the card for a custom quantity or price.
class SellTile extends StatelessWidget {
  final Product product;

  /// How much of this product is already in the cart.
  final double inCart;
  final VoidCallback onAdd;
  final VoidCallback onSellMore;

  const SellTile({
    super.key,
    required this.product,
    this.inCart = 0,
    required this.onAdd,
    required this.onSellMore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = product.stock - inCart;
    final canAdd = left > 0;
    return ItemCard(
      title: product.name,
      subtitle: product.variantParts.join(' • '),
      onTap: canAdd ? onSellMore : null,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(product.kind.icon),
      ),
      chips: [
        InfoChip(
          label: '${formatMoney(product.sellingPrice)} / ${Bn.unitName(product.unit)}',
          background: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer,
        ),
        InfoChip(
          label: '${Bn.available}: ${formatNumber(product.stock)}',
          background: product.stock > 0 ? null : scheme.errorContainer,
          foreground: product.stock > 0 ? null : scheme.onErrorContainer,
        ),
        if (inCart > 0)
          InfoChip(
            label: '${Bn.cartLines}: ${formatNumber(inCart)}',
            icon: Icons.shopping_cart_outlined,
            background: scheme.primaryContainer,
            foreground: scheme.onPrimaryContainer,
          ),
      ],
      trailing: FilledButton.tonal(
        onPressed: canAdd ? onAdd : null,
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
        child: Text(product.stock > 0 ? Bn.addOneLabel(product.unit) : Bn.soldOut),
      ),
    );
  }
}

/// The bar at the bottom of the sell screen while the cart has items: what is
/// in it, and a button to go to checkout (where the customer's details are taken).
class CartBar extends StatelessWidget {
  final int items;
  final double total;
  final VoidCallback onCheckout;

  const CartBar({super.key, required this.items, required this.total, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(Icons.shopping_cart, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                Bn.cartSummary(items, total),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(onPressed: onCheckout, child: Text(Bn.completeSale)),
          ],
        ),
      ),
    );
  }
}

/// One bill in the daily account.
class BillTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback onTap;

  /// Show the date and time instead of the customer's name (for lists that
  /// span many days and belong to one customer).
  final bool showDate;

  /// Small extras along the bottom of the card (e.g. call / share).
  final Widget? footer;
  const BillTile({super.key, required this.bill, required this.onTap, this.showDate = false, this.footer});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = bill.lines.map((l) => l.productName).toList();
    final items = names.length <= 2 ? names.join(', ') : '${names.take(2).join(', ')} +${toBanglaDigits('${names.length - 2}')}';
    return ItemCard(
      title: showDate ? formatDateTime(bill.at) : (bill.customerName.isNotEmpty ? bill.customerName : Bn.retailSale),
      subtitle: [
        showDate ? items : '$items • ${formatTime(bill.at)}',
        if (bill.soldBy.isNotEmpty) '${Bn.soldByLabel}: ${bill.soldBy}',
      ].join('\n'),
      onTap: onTap,
      footer: footer,
      leading: CircleAvatar(
        backgroundColor: bill.due > 0 ? scheme.errorContainer : scheme.secondaryContainer,
        foregroundColor: bill.due > 0 ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        child: const Icon(Icons.receipt_long),
      ),
      chips: [
        if (bill.customerMobile.isNotEmpty) InfoChip(label: bill.customerMobile, icon: Icons.phone_outlined),
        if (bill.due > 0)
          InfoChip(
            label: '${Bn.dueLabel}: ${formatMoney(bill.due)}',
            icon: Icons.schedule,
            background: scheme.errorContainer,
            foreground: scheme.onErrorContainer,
          ),
      ],
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMoney(bill.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(
            '${bill.profit < 0 ? Bn.loss : Bn.profit} ${formatMoney(bill.profit.abs())}',
            style: TextStyle(fontSize: 12, color: bill.profit < 0 ? scheme.error : Colors.green.shade700),
          ),
        ],
      ),
    );
  }
}

/// Totals for the day: sales, profit and how many bills; plus what is still owed.
class DaySummaryCard extends StatelessWidget {
  final DaySummary summary;
  const DaySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final loss = summary.profit < 0;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color ?? scheme.onPrimaryContainer),
              ),
            ],
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              stat(Bn.totalSales, formatMoney(summary.revenue)),
              stat(loss ? Bn.loss : Bn.totalProfit, formatMoney(summary.profit.abs()), color: loss ? scheme.error : null),
              stat(Bn.salesCount, toBanglaDigits('${summary.saleCount}')),
            ],
          ),
          if (summary.collected > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.south_west, size: 18, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  '${Bn.collectedLabel}: ${formatMoney(summary.collected)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          if (summary.due > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.error),
                const SizedBox(width: 6),
                Text(
                  '${Bn.dueTotal}: ${formatMoney(summary.due)}',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.error, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
