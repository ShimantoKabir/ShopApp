import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customer_rules.dart';

/// Lays fields out side by side with equal width and spacing.
class FieldRow extends StatelessWidget {
  final List<Widget> children;
  const FieldRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: children[i]),
          ],
        ],
      );
}

/// Number input that accepts Bangla or English digits and validates itself.
class NumberFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final TextInputAction action;

  const NumberFormField({
    super.key,
    required this.controller,
    required this.label,
    this.prefix,
    this.action = TextInputAction.next,
  });

  static String? validate(String? v) {
    if (v == null || v.trim().isEmpty) return Bn.required;
    return parseNumber(v) == null ? Bn.invalidNumber : null;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9০-৯.,।]'))],
        textInputAction: action,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix == null ? null : '$prefix ',
          ),
        validator: validate,
      );
}

/// Required plain-text field.
class RequiredTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final bool autofocus;

  const RequiredTextFormField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label),
        validator: (v) => (v == null || v.trim().isEmpty) ? Bn.required : null,
      );
}

/// Optional plain-text field (no validation).
class OptionalTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputAction action;

  const OptionalTextFormField({
    super.key,
    required this.controller,
    required this.label,
    this.action = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        textInputAction: action,
        decoration: InputDecoration(labelText: label),
      );
}

class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final pill = OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: pill,
          enabledBorder: pill,
        ),
      ),
    );
  }
}

/// Dropdown with a side action button (e.g. "add new" or "scan QR").
class DropdownWithAction<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?> onChanged;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback onAction;

  /// An optional second button beside the first (e.g. "new" next to "scan").
  final IconData? secondActionIcon;
  final String? secondActionTooltip;
  final VoidCallback? onSecondAction;

  const DropdownWithAction({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.actionIcon,
    required this.actionTooltip,
    required this.onAction,
    this.secondActionIcon,
    this.secondActionTooltip,
    this.onSecondAction,
  });

  @override
  Widget build(BuildContext context) {
    // A dropdown must never be given a value that is not among its items (it
    // asserts). That happens while the items are still loading, so ignore the
    // value until its item exists; the key below rebuilds the field once the
    // items arrive.
    final selectable = items.any((i) => i.value == value);
    return Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<T?>(
              key: ValueKey('$label-$value-${items.length}'),
              initialValue: selectable ? value : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: items,
              onChanged: onChanged,
            ),
          ),
          IconButton.filledTonal(onPressed: onAction, icon: Icon(actionIcon), tooltip: actionTooltip),
          if (onSecondAction != null)
            IconButton.filledTonal(onPressed: onSecondAction, icon: Icon(secondActionIcon), tooltip: secondActionTooltip),
        ],
      );
  }
}

/// A full-width primary button, optionally paired with a secondary one.
class ActionButtonRow extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  const ActionButtonRow({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    const size = Size.fromHeight(52);
    final primary = FilledButton(
      onPressed: busy ? null : onPrimary,
      style: FilledButton.styleFrom(minimumSize: size),
      child: Text(primaryLabel),
    );
    if (secondaryLabel == null) return primary;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onSecondary,
            style: OutlinedButton.styleFrom(minimumSize: size),
            child: Text(secondaryLabel!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: primary),
      ],
    );
  }
}

/// A PIN: 4-6 digits (Bangla or English), hidden as it is typed.
/// With [validate] it checks the length; with [mustMatch] it must equal that
/// other field (for "type it again").
class PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool validate;
  final TextEditingController? mustMatch;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;

  const PinField({
    super.key,
    required this.controller,
    required this.label,
    this.validate = false,
    this.mustMatch,
    this.onSubmitted,
    this.obscure = true,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9০-৯]')), LengthLimitingTextInputFormatter(6)],
        textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.done,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(labelText: label),
        validator: validate
            ? (v) {
                final pin = digitsOnly(v ?? '');
                if (pin.length < 4) return Bn.authInvalidPin;
                if (mustMatch != null && pin != digitsOnly(mustMatch!.text)) return Bn.pinMismatch;
                return null;
              }
            : null,
      );
}
