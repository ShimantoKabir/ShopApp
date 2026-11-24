import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../components/components.dart';
import '../labels.dart';

/// A location's name and the quantity of a product kept there.
typedef PlacementLabel = ({String name, double quantity});

/// Product-specific composition of the generic [ItemCard], [InfoChip] and [TappableValue].
class ProductTile extends StatelessWidget {
  final Product product;
  final String categoryName;

  /// Where the stock is kept, with location names already resolved.
  final List<PlacementLabel> placements;

  /// The quantity in the stock pill. Defaults to the product's total; the
  /// per-location screen passes the quantity at that location instead.
  final double? stockShown;

  final VoidCallback onTap;
  final VoidCallback onStockTap;

  const ProductTile({
    super.key,
    required this.product,
    required this.categoryName,
    required this.placements,
    this.stockShown,
    required this.onTap,
    required this.onStockTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = stockShown ?? product.stock;
    final outOfStock = shown <= 0;
    final noPrice = product.sellingPrice == 0;
    final unplaced = product.unplacedQuantity;

    return ItemCard(
      title: product.name,
      subtitle: [...product.variantParts, categoryName].where((s) => s.isNotEmpty).join(' • '),
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Icon(product.kind.icon),
      ),
      chips: [
        InfoChip(label: '${Bn.purchasePrice} ${formatMoney(product.purchasePrice)}'),
        noPrice
            ? InfoChip(
                label: Bn.priceMissing,
                icon: Icons.warning_amber_rounded,
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
              )
            : InfoChip(
                label: '${Bn.sellingPrice} ${formatMoney(product.sellingPrice)}',
                background: scheme.tertiaryContainer,
                foreground: scheme.onTertiaryContainer,
              ),
        for (final p in placements)
          InfoChip(label: '${p.name} · ${formatNumber(p.quantity)}', icon: Icons.place_outlined),
        // Stock exists that nobody has assigned to a location yet.
        if (product.stock > 0 && unplaced > 0)
          InfoChip(
            label: '${Bn.unplaced}: ${formatNumber(unplaced)}',
            icon: Icons.help_outline,
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
      ],
      trailing: TappableValue(
        value: formatNumber(shown),
        caption: Bn.unitName(product.unit),
        onTap: onStockTap,
        background: outOfStock ? scheme.errorContainer : null,
        foreground: outOfStock ? scheme.onErrorContainer : null,
      ),
    );
  }
}
