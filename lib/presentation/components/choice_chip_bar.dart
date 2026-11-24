import 'package:material_ui/material_ui.dart';

class ChipOption<V> {
  final V value;
  final String label;
  const ChipOption(this.value, this.label);
}

/// Single-select chips. Use for filters (scrollable, with an "all" chip)
/// or option pickers (wrapping, no "all").
class ChoiceChipBar<V> extends StatelessWidget {
  final List<ChipOption<V>> options;
  final V? selected;
  final ValueChanged<V?> onSelected;

  /// When set, adds a leading chip that clears the selection (null).
  final String? allLabel;
  final bool scrollable;

  const ChoiceChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allLabel,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    // An "all" chip with nothing to choose between is just noise.
    if (options.isEmpty) return const SizedBox.shrink();
    final chips = [
      if (allLabel != null) _chip(allLabel!, selected == null, () => onSelected(null)),
      for (final o in options) _chip(o.label, selected == o.value, () => onSelected(o.value)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    if (!scrollable) return Wrap(spacing: 8, children: chips);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
      ),
    );
  }

  Widget _chip(String label, bool isSelected, VoidCallback onTap) =>
      ChoiceChip(label: Text(label), selected: isSelected, onSelected: (_) => onTap());
}
