import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/entities.dart';
import '../domain/stock.dart';
import 'components/components.dart';
import 'labels.dart';
import 'screen_factory.dart';
import 'shell_scope.dart';
import 'viewmodels.dart';
import 'widgets/product_tile.dart';
import 'widgets/restock_dialog.dart';

/// Home screen. When [location] is given, shows only that location's products.
/// The page owns (and disposes) the [viewModel] it is given.
class ProductListPage extends StatefulWidget {
  final ProductListViewModel viewModel;
  final ScreenFactory screens;
  final StorageLocation? location;

  const ProductListPage({super.key, required this.viewModel, required this.screens, this.location});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  ProductListViewModel get _vm => widget.viewModel;
  ScreenFactory get _screens => widget.screens;

  Listenable? _dataChanged;

  @override
  void initState() {
    super.initState();
    _vm.locationFilter = widget.location?.id;
    _vm.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A category or location was added from the menu: refresh without a loading bar.
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
    _vm.dispose();
    super.dispose();
  }

  Future<T?> _push<T>(Widget page) => Navigator.push<T>(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _open(Widget page) async {
    await _push(page);
    _vm.load(quiet: true);
  }

  /// Main list: choose between receiving new goods and correcting the total.
  Future<void> _stockActions(Product p) async {
    final restock = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: Text(Bn.restock),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(Bn.editTotal),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (restock == null || !mounted) return;
    if (restock) {
      final input = await showRestockDialog(context, product: p, locations: _vm.locations);
      if (input == null) return;
      await _vm.restock(p, input.quantity, locationId: input.locationId, purchasePrice: input.purchasePrice);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(Bn.restockDone), duration: Duration(seconds: 2)));
      }
    } else {
      final value = await showNumberDialog(context, title: p.name, label: '${Bn.stock} (${Bn.unitName(p.unit)})', initial: p.stock);
      if (value != null) await _vm.updateStock(p, value);
    }
  }

  /// Tapping the stock pill: on a location's screen it is a physical COUNT at
  /// that location (the total follows); on the main list it edits the TOTAL.
  Future<void> _editStock(Product p) async {
    final location = widget.location;
    try {
      if (location != null) {
        final value = await showNumberDialog(
          context,
          title: p.name,
          label: '${Bn.countHere} (${Bn.unitName(p.unit)})',
          initial: p.quantityAt(location.id),
        );
        if (value != null) await _vm.recount(p, location.id!, value);
      } else {
        await _stockActions(p);
      }
    } on StockException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(stockProblemMessage(e.problem))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: menuButton(context),
          title: Text(location != null ? '${Bn.location}: ${location.name}' : Bn.navInventory),
          actions: cartActions(context),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _open(_screens.productForm(initialLocationId: location?.id)),
          icon: const Icon(Icons.add),
          label: Text(Bn.addProduct),
        ),
        body: Column(
          children: [
            SearchField(hint: Bn.search, onChanged: _vm.setQuery),
            ChoiceChipBar<int>(
              options: [for (final c in _vm.categories) ChipOption(c.id!, c.name)],
              selected: _vm.categoryFilter,
              onSelected: _vm.setCategoryFilter,
              allLabel: Bn.all,
            ),
            SummaryBar(
              left: '${Bn.totalItems}: ${toBanglaDigits('${_vm.products.length}')}',
              right: '${Bn.stockValue}: ${formatMoney(_vm.totalStockValue)}',
            ),
            Expanded(
              child: AsyncListView<Product>(
                items: _vm.products,
                loading: _vm.loading,
                emptyMessage: _vm.hasFilter ? Bn.noResults : Bn.noProducts,
                itemKey: (p) => p.id!,
                onDelete: _vm.delete,
                itemBuilder: (context, p) => ProductTile(
                  product: p,
                  categoryName: _vm.categoryName(p.categoryId),
                  placements: [
                    for (final pl in p.placements) (name: _vm.locationName(pl.locationId), quantity: pl.quantity),
                  ],
                  stockShown: location == null ? null : p.quantityAt(location.id),
                  onTap: () => _open(_screens.productForm(product: p)),
                  onStockTap: () => _editStock(p),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
