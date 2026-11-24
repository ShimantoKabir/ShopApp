import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';

class RestockInput {
  final double quantity;

  /// Set only if the buying price was changed.
  final double? purchasePrice;
  final int? locationId;
  const RestockInput({required this.quantity, this.purchasePrice, this.locationId});
}

/// Asks how much arrived, optionally at what new cost and where to put it.
Future<RestockInput?> showRestockDialog(
  BuildContext context, {
  required Product product,
  required List<StorageLocation> locations,
}) =>
    showDialog<RestockInput>(
      context: context,
      builder: (_) => _RestockDialog(product: product, locations: locations),
    );

class _RestockDialog extends StatefulWidget {
  final Product product;
  final List<StorageLocation> locations;
  const _RestockDialog({required this.product, required this.locations});

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _quantity = TextEditingController();
  late final _price = TextEditingController(text: formatNumber(widget.product.purchasePrice));
  int? _locationId;

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final q = parseNumber(_quantity.text);
    if (q == null || q <= 0) return;
    final price = parseNumber(_price.text);
    Navigator.pop(
      context,
      RestockInput(
        quantity: q,
        purchasePrice: (price != null && price != widget.product.purchasePrice) ? price : null,
        locationId: _locationId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      title: Text('${Bn.restock}: ${widget.product.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _quantity,
              autofocus: true,
              keyboardType: keyboard,
              decoration: InputDecoration(labelText: '${Bn.restockQuantity} (${Bn.unitName(widget.product.unit)})'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: keyboard,
              decoration: InputDecoration(labelText: Bn.restockPrice, prefixText: '${Bn.taka} '),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _locationId,
              isExpanded: true,
              decoration: InputDecoration(labelText: Bn.restockWhere),
              items: [
                DropdownMenuItem(value: null, child: Text(Bn.restockLater)),
                for (final l in widget.locations) DropdownMenuItem(value: l.id, child: Text(l.name)),
              ],
              onChanged: (v) => setState(() => _locationId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(Bn.cancel)),
        FilledButton(onPressed: _submit, child: Text(Bn.save)),
      ],
    );
  }
}
