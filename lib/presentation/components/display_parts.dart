import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/bangla.dart';

/// Centered icon + message for empty lists and search results.
class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyState({super.key, required this.message, this.icon = Icons.inventory_2_outlined});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two texts at opposite ends inside a tonal rounded container, e.g. a count and a total.
class SummaryBar extends StatelessWidget {
  final String left;
  final String right;
  const SummaryBar({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onSecondaryContainer);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(left, style: style), Flexible(child: Text(right, style: style, textAlign: TextAlign.end))],
      ),
    );
  }
}

/// A tappable big value with a small caption, in a rounded tonal pill
/// (e.g. "10 / কেজি"). Pass [background]/[foreground] to flag a state.
class TappableValue extends StatelessWidget {
  final String value;
  final String caption;
  final VoidCallback onTap;
  final Color? background;
  final Color? foreground;

  const TappableValue({
    super.key,
    required this.value,
    required this.caption,
    required this.onTap,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onPrimaryContainer;
    return Material(
      color: background ?? scheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: fg)),
              Text(caption, style: TextStyle(fontSize: 12, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded label, optionally with a leading icon.
class InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  const InfoChip({super.key, required this.label, this.icon, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: fg), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// A card for one list item: optional leading widget, title, subtitle, a row
/// of [chips] and a trailing widget. Knows nothing about what it shows.
class ItemCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Something small along the bottom edge inside the card (e.g. call / share).
  final Widget? footer;

  const ItemCard({
    super.key,
    required this.title,
    this.subtitle,
    this.chips = const [],
    this.leading,
    this.trailing,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: chips),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
              ),
              if (footer != null) Padding(padding: const EdgeInsets.only(top: 10), child: Align(alignment: Alignment.centerRight, child: footer)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled group of form fields inside a card.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;

  const SectionCard({super.key, required this.title, this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 20, color: theme.colorScheme.primary), const SizedBox(width: 8)],
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Shows the difference between [value] and [base] as a gain or loss.
/// Inputs are raw text so it can be driven straight from text fields.
class DeltaIndicator extends StatelessWidget {
  final String baseText;
  final String valueText;
  final String gainLabel;
  final String lossLabel;

  const DeltaIndicator({
    super.key,
    required this.baseText,
    required this.valueText,
    required this.gainLabel,
    required this.lossLabel,
  });

  @override
  Widget build(BuildContext context) {
    final base = parseNumber(baseText);
    final value = parseNumber(valueText);
    if (base == null || value == null) return const SizedBox(height: 24); // keep layout stable
    final diff = value - base;
    final isLoss = diff < 0;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '${isLoss ? lossLabel : gainLabel}: ${formatMoney(diff.abs())}',
        style: TextStyle(fontWeight: FontWeight.bold, color: isLoss ? scheme.error : Colors.green.shade700),
      ),
    );
  }
}

/// A QR code with a title above and a caption below.
class QrCard extends StatelessWidget {
  final String title;
  final String data;
  final String? caption;
  final double size;

  const QrCard({super.key, required this.title, required this.data, this.caption, this.size = 260});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.all(16),
            child: QrImageView(data: data, size: size),
          ),
          if (caption != null) ...[const SizedBox(height: 12), Text(caption!, textAlign: TextAlign.center)],
        ],
      );
}

/// A message card pinned to the bottom of a Stack (e.g. over a camera view).
class HintOverlay extends StatelessWidget {
  final String message;
  const HintOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(message, textAlign: TextAlign.center))),
        ),
      );
}
