import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/entities.dart';
import '../domain/stock.dart';
import 'components/components.dart';
import 'labels.dart';
import 'screen_factory.dart';
import 'viewmodels.dart';

/// What is in the cart: change amounts, take things out, then sell it all (on
/// to checkout) or cancel it. Uses the shared cart ([viewModel]); this page
/// does not dispose it.
class CartPage extends StatefulWidget {
  final SellViewModel viewModel;
  final ScreenFactory screens;
  const CartPage({super.key, required this.viewModel, required this.screens});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  SellViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _catchUp(); // opening the cart: has another phone sold any of this?
  }

  Future<void> _catchUp() async {
    final shortages = await _vm.refreshFromShop();
    if (!mounted || shortages.isEmpty) return;
    _say(shortages.map((s) => Bn.stockChangedElsewhere(s.name, s.left)).join('\n'));
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Loose goods (by weight) go up and down by half; everything else by one.
  double _step(CartLine line, int direction) => direction * (line.product.kind == ProductKind.loose ? 0.5 : 1.0);

  void _change(CartLine line, double by) {
    try {
      _vm.setQuantity(line, line.quantity + by);
    } on StockException catch (e) {
      _say(stockProblemMessage(e.problem));
    }
  }

  Future<void> _cancelCart() async {
    final sure = await showConfirmDialog(context, message: Bn.cartCancelConfirm, confirmLabel: Bn.cartCancel);
    if (!sure || !mounted) return;
    _vm.clearCart();
    Navigator.pop(context);
  }

  Future<void> _sell() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.checkout(_vm)));
    // Sold (or the cart was emptied): nothing left to look at here.
    if (mounted && _vm.cartCount == 0) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.cartTitle)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            if (_vm.cartCount == 0) return EmptyState(message: Bn.cartEmpty, icon: Icons.shopping_cart_outlined);
            final theme = Theme.of(context);
            return Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _vm.cart.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final line = _vm.cart[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line.product.name, style: theme.textTheme.titleSmall),
                                    Text(
                                      '${formatMoney(line.unitPrice)} / ${Bn.unitName(line.product.unit)}',
                                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _change(line, _step(line, -1)),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              Text('${formatNumber(line.quantity)} ${Bn.unitName(line.product.unit)}', style: theme.textTheme.titleSmall),
                              IconButton(
                                onPressed: () => _change(line, _step(line, 1)),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              SizedBox(width: 64, child: Text(formatMoney(line.total), textAlign: TextAlign.end, style: theme.textTheme.titleSmall)),
                              IconButton(
                                onPressed: () => _vm.removeLine(line),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: Bn.removeFromCart,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  elevation: 6,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(Bn.saleTotal, style: theme.textTheme.titleMedium),
                              Text(formatMoney(_vm.cartTotal), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _cancelCart,
                                  icon: const Icon(Icons.close),
                                  label: Text(Bn.cartCancel),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _sell,
                                  icon: const Icon(Icons.point_of_sale),
                                  label: Text(Bn.cartSell),
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}
