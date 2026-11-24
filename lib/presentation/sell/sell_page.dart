import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';
import '../labels.dart';
import '../screen_factory.dart';
import '../home_shell/shell_scope.dart';
import 'sell_viewmodel.dart';
import '../widgets/sale_widgets.dart';
import '../widgets/sell_sheet.dart';

/// Find products, add them to the cart, and sell. Uses the app's shared cart
/// ([viewModel]), which this page does not dispose.
class SellPage extends StatefulWidget {
  final SellViewModel viewModel;
  final ScreenFactory screens;
  const SellPage({super.key, required this.viewModel, required this.screens});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  SellViewModel get _vm => widget.viewModel;

  Listenable? _dataChanged;

  @override
  void initState() {
    super.initState();
    _vm.load();
    _catchUp(); // opening the selling screen: see what other phones sold
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final signal = ShellScope.maybeOf(context)?.dataChanged;
    if (signal != _dataChanged) {
      _dataChanged?.removeListener(_refreshQuietly);
      signal?.addListener(_refreshQuietly);
      _dataChanged = signal;
    }
  }

  void _refreshQuietly() => _vm.load(quiet: true);

  @override
  void dispose() {
    _dataChanged?.removeListener(_refreshQuietly);
    // The cart is shared by the whole app and lives on: it is not disposed here.
    super.dispose();
  }

  void _say(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action, duration: const Duration(seconds: 5)));
  }

  /// Runs [action]; a broken stock/billing rule becomes a message, anything
  /// else is rethrown (never hidden).
  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _say(message);
      return null;
    }
  }

  /// Catches up with the shop and says so if something in the cart was sold
  /// elsewhere meanwhile.
  Future<void> _catchUp() async {
    final shortages = await _vm.refreshFromShop();
    if (!mounted || shortages.isEmpty) return;
    _say(shortages.map((s) => Bn.stockChangedElsewhere(s.name, s.left)).join('\n'));
  }

  /// Adds to the cart after a quick look at the shop's latest stock.
  Future<void> _add(Product p, {double quantity = 1, double? unitPrice, int? fromLocationId}) async {
    await _catchUp();
    if (!mounted) return;
    final fresh = _vm.products.where((x) => x.id == p.id).firstOrNull ?? p;
    await _guard(() async => _vm.addToCart(fresh, quantity: quantity, unitPrice: unitPrice, fromLocationId: fromLocationId));
  }

  Future<void> _sellMore(Product picked) async {
    await _catchUp(); // the popup shows the latest stock
    if (!mounted) return;
    final p = _vm.products.where((x) => x.id == picked.id).firstOrNull ?? picked;
    final input = await showSellSheet(context, product: p, locationName: _vm.locationName, inCart: _vm.inCart(p));
    if (input == null) return;
    await _add(p, quantity: input.quantity, unitPrice: input.unitPrice, fromLocationId: input.fromLocationId);
  }

  /// Every sale goes through checkout: it takes the customer's address and WhatsApp number.
  void _openCheckout() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.checkout(_vm)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: menuButton(context), title: Text(Bn.sellTitle), actions: cartActions(context)),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Column(
            children: [
              SearchField(hint: Bn.sellSearch, onChanged: _vm.setQuery),
              const SizedBox(height: 4),
              Expanded(
                child: AsyncListView<Product>(
                  items: _vm.products,
                  loading: _vm.loading,
                  emptyMessage: _vm.query.isEmpty ? Bn.noSellable : Bn.noResults,
                  itemBuilder: (context, p) => SellTile(
                    product: p,
                    inCart: _vm.inCart(p),
                    onAdd: () => _add(p),
                    onSellMore: () => _sellMore(p),
                  ),
                ),
              ),
              if (_vm.cartCount > 0)
                CartBar(
                  items: _vm.cartCount,
                  total: _vm.cartTotal,
                  onCheckout: _openCheckout,
                ),
            ],
          ),
        ),
      );
}
