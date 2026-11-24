import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/entities.dart';
import '../../domain/stock.dart';
import '../components/components.dart';
import '../labels.dart';

enum PlacementAction { recount, move, remove }

/// Shows where a saved product's stock is kept and offers actions on each
/// place: recount, move, remove. All behaviour comes in as callbacks.
class PlacementEditor extends StatelessWidget {
  final Product product;
  final String Function(int locationId) locationName;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onHistory;
  final void Function(StockPlacement placement, PlacementAction action) onAction;

  const PlacementEditor({
    super.key,
    required this.product,
    required this.locationName,
    required this.onAdd,
    required this.onScan,
    required this.onHistory,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unplaced = product.unplacedQuantity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in product.placements)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(locationName(p.locationId)),
            subtitle: Text('${formatNumber(p.quantity)} ${Bn.unitName(product.unit)}'),
            trailing: PopupMenuButton<PlacementAction>(
              onSelected: (a) => onAction(p, a),
              itemBuilder: (_) => [
                PopupMenuItem(value: PlacementAction.recount, child: Text(Bn.recountAction)),
                PopupMenuItem(value: PlacementAction.move, child: Text(Bn.moveAction)),
                PopupMenuItem(value: PlacementAction.remove, child: Text(Bn.removeFromLocation)),
              ],
            ),
          ),
        if (unplaced > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InfoChip(
              label: '${Bn.unplaced}: ${formatNumber(unplaced)} ${Bn.unitName(product.unit)}',
              icon: Icons.help_outline,
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(Bn.addPlacement),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(onPressed: onScan, icon: const Icon(Icons.qr_code_scanner), tooltip: Bn.scanQr),
            IconButton(onPressed: onHistory, icon: const Icon(Icons.history), tooltip: Bn.history),
          ],
        ),
      ],
    );
  }
}

/// Bottom sheet listing the stock history of a product, newest first.
Future<void> showStockHistory(
  BuildContext context, {
  required List<StockLogEntry> entries,
  required String Function(int? locationId) locationName,
  required String unit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(Bn.historyTitle, style: Theme.of(ctx).textTheme.titleLarge),
          ),
          Expanded(
            child: entries.isEmpty
                ? EmptyState(message: Bn.noHistory, icon: Icons.history)
                : ListView.builder(
                    controller: scroll,
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final e = entries[i];
                      final sign = e.delta > 0 ? '+' : '−';
                      final where = e.locationId == null ? '' : ' • ${locationName(e.locationId)}';
                      return ListTile(
                        leading: Icon(e.reason.icon),
                        title: Text('${e.reason.label}$where'),
                        subtitle: Text(e.userName.isEmpty ? formatDateTime(e.at) : '${formatDateTime(e.at)} • ${e.userName}'),
                        trailing: Text(
                          '$sign${formatNumber(e.delta.abs())} $unit',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: e.delta > 0 ? Colors.green.shade700 : Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
