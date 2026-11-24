import 'package:material_ui/material_ui.dart';

/// One bar: a short [label] under it and its [value].
class BarItem {
  final String label;
  final double value;
  const BarItem(this.label, this.value);
}

/// A simple bar chart with no dependencies. Bars share one scale (the biggest
/// value is the full height); the last bar is highlighted (normally "today").
/// A chart with only zeros shows flat stubs, never a divide-by-zero.
class BarChart extends StatelessWidget {
  final List<BarItem> items;
  final double height;

  /// Text shown above the highlighted bar (e.g. the formatted amount).
  final String Function(double value)? valueLabel;

  const BarChart({super.key, required this.items, this.height = 120, this.valueLabel});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final biggest = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    const labelHeight = 20.0;
    const valueTextHeight = 18.0;
    final barArea = height - labelHeight - valueTextHeight;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (i == items.length - 1 && valueLabel != null)
                    SizedBox(
                      height: valueTextHeight,
                      child: FittedBox(
                        child: Text(valueLabel!(items[i].value), style: TextStyle(fontSize: 11, color: scheme.primary)),
                      ),
                    )
                  else
                    const SizedBox(height: valueTextHeight),
                  Container(
                    key: ValueKey('bar-$i'),
                    height: biggest <= 0 ? 2 : (barArea * items[i].value / biggest).clamp(2.0, barArea),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == items.length - 1 ? scheme.primary : scheme.primary.withValues(alpha: 0.35),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  SizedBox(
                    height: labelHeight,
                    child: Center(
                      child: Text(
                        items[i].label,
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A figure with a caption: the building block of a dashboard.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  /// Colours the value (e.g. red for money owed). Defaults to normal text.
  final Color? color;

  /// A small line under the value (e.g. a comparison with the last period).
  final String? note;

  const StatTile({super.key, required this.label, required this.value, this.icon, this.color, this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
