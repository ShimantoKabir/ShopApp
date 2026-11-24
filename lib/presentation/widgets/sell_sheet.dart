import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';

class SellInput {
  final double quantity;
  final double unitPrice;

  /// Null = let the app choose where the units come from.
  final int? fromLocationId;
  const SellInput({required this.quantity, required this.unitPrice, this.fromLocationId});
}

/// Bottom sheet for a sale with a custom quantity or price.
Future<SellInput?> showSellSheet(
  BuildContext context, {
  required Product product,
  required String Function(int locationId) locationName,
  double inCart = 0,
}) =>
    showModalBottomSheet<SellInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SellSheet(product: product, locationName: locationName, inCart: inCart),
    );

class _SellSheet extends StatefulWidget {
  final Product product;
  final String Function(int locationId) locationName;

  /// Already in the cart, so not available again.
  final double inCart;
  const _SellSheet({required this.product, required this.locationName, required this.inCart});

  @override
  State<_SellSheet> createState() => _SellSheetState();
}

class _SellSheetState extends State<_SellSheet> {
  final _quantity = TextEditingController(text: formatNumber(1));
  late final _price = TextEditingController(text: formatNumber(widget.product.sellingPrice));
  int? _from;

  @override
  void initState() {
    super.initState();
    _quantity.addListener(() => setState(() {}));
    _price.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  double get _qty => parseNumber(_quantity.text) ?? 0;
  double get _unitPrice => parseNumber(_price.text) ?? 0;
  double get _available =>
      (_from == null ? widget.product.stock : widget.product.quantityAt(_from)) - widget.inCart;
  bool get _tooMany => _qty > _available + 1e-9;
  bool get _valid => _qty > 0 && !_tooMany && parseNumber(_price.text) != null;

  /// Loose goods (by weight) are sold in halves; everything else one at a time.
  bool get _byWeight => widget.product.kind == ProductKind.loose;
  double get _stepSize => _byWeight ? 0.5 : 1;

  void _step(double direction) {
    final size = _stepSize;
    final upper = _available > size ? _available : size;
    _quantity.text = formatNumber((_qty + direction * size).clamp(size, upper));
  }

  /// A tap puts this amount in (never more than there is).
  void _setQuantity(double amount) => setState(() => _quantity.text = formatNumber(amount));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    final profit = (_unitPrice - product.purchasePrice) * _qty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${Bn.available}: ${formatNumber(product.stock - widget.inCart)} ${Bn.unitName(product.unit)}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            // What it sells for and what it cost, so the price can be set knowing both.
            Wrap(
              spacing: 8,
              children: [
                InfoChip(label: '${Bn.sellingPrice}: ${formatMoney(product.sellingPrice)}', icon: Icons.sell_outlined),
                InfoChip(label: '${Bn.purchasePrice}: ${formatMoney(product.purchasePrice)}', icon: Icons.shopping_bag_outlined),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton.filledTonal(onPressed: () => _step(-1), icon: const Icon(Icons.remove)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(labelText: '${Bn.quantity} (${Bn.unitName(product.unit)})'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(onPressed: () => _step(1), icon: const Icon(Icons.add)),
              ],
            ),
            if (_byWeight) ...[
              // A customer who wants part of a unit (half a kilo...): one tap.
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (part, label) in const [(0.25, '¼'), (0.5, '½'), (1.0, '১')])
                    if (part <= _available + 1e-9) ActionChip(label: Text(label), onPressed: () => _setQuantity(part)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: Bn.unitPrice, prefixText: '${Bn.taka} '),
            ),
            if (product.purchasePrice > 0 && product.purchasePrice != product.sellingPrice) ...[
              // Two taps to choose between the usual price and "at what it cost":
              // no profit, no loss.
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('${Bn.sellAtPrice} ${formatMoney(product.sellingPrice)}'),
                    selected: _unitPrice == product.sellingPrice,
                    onSelected: (_) => _price.text = formatNumber(product.sellingPrice),
                  ),
                  ChoiceChip(
                    label: Text('${Bn.sellAtCost} ${formatMoney(product.purchasePrice)}'),
                    selected: _unitPrice == product.purchasePrice,
                    onSelected: (_) => _price.text = formatNumber(product.purchasePrice),
                  ),
                ],
              ),
            ],
            if (product.placements.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(Bn.sellFrom, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              ChoiceChipBar<int>(
                options: [
                  for (final p in product.placements)
                    ChipOption(p.locationId, '${widget.locationName(p.locationId)} · ${formatNumber(p.quantity)}'),
                ],
                selected: _from,
                allLabel: Bn.sellFromAny,
                scrollable: false,
                onSelected: (v) => setState(() => _from = v),
              ),
            ],
            const SizedBox(height: 16),
            if (_tooMany)
              Text(Bn.stockInsufficient, style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600))
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${Bn.saleTotal}: ${formatMoney(_qty * _unitPrice)}', style: theme.textTheme.titleMedium),
                  Text(
                    _unitPrice > 0 && profit.abs() < 1e-9
                        ? Bn.noProfit
                        : '${profit < 0 ? Bn.loss : Bn.profit}: ${formatMoney(profit.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: profit < 0
                          ? theme.colorScheme.error
                          : (profit.abs() < 1e-9 ? theme.colorScheme.onSurfaceVariant : Colors.green.shade700),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _valid
                  ? () => Navigator.pop(context, SellInput(quantity: _qty, unitPrice: _unitPrice, fromLocationId: _from))
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(Bn.addToCart),
            ),
          ],
        ),
      ),
    );
  }
}
