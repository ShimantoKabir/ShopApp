import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';

// Every dialog with a text field is a small StatefulWidget that OWNS its
// controller. Flutter disposes it only after the dialog has finished animating
// away. (Disposing a controller as soon as showDialog's future completes is a
// bug: the field is still on screen during the exit animation and crashes.)

/// Asks for one line of text. Returns null if cancelled or empty.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String? initialText,
  String? confirmLabel,
  String? cancelLabel,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(title: title, hint: hint, initialText: initialText, confirmLabel: confirmLabel ?? Bn.add, cancelLabel: cancelLabel ?? Bn.cancel),
    );

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String? initialText;
  final String confirmLabel;
  final String cancelLabel;
  const _TextPromptDialog({required this.title, this.hint, this.initialText, required this.confirmLabel, required this.cancelLabel});

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.hint),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// Asks for a line of text plus one choice from [options] (e.g. a name and a type).
/// Returns null if cancelled or the text is empty.
Future<({String text, V choice})?> showTextWithChoiceDialog<V>(
  BuildContext context, {
  required String title,
  required String choiceLabel,
  required List<({V value, String label})> options,
  required V initialChoice,
  String? hint,
  String? initialText,
  String? confirmLabel,
  String? cancelLabel,
  NewChoice<V>? newChoice,
}) =>
    showDialog<({String text, V choice})>(
      context: context,
      builder: (_) => _TextWithChoiceDialog<V>(
        newChoice: newChoice,
        title: title,
        choiceLabel: choiceLabel,
        options: options,
        initialChoice: initialChoice,
        hint: hint,
        initialText: initialText,
        confirmLabel: confirmLabel ?? Bn.add,
        cancelLabel: cancelLabel ?? Bn.cancel,
      ),
    );

/// Lets the person make up a choice that is not in the list: a "+" chip that
/// asks for a name (titled [title]) and turns it into a choice with [create].
class NewChoice<V> {
  final String label;
  final String title;
  final String? hint;
  final ({V value, String label}) Function(String name) create;
  const NewChoice({required this.label, required this.title, this.hint, required this.create});
}

class _TextWithChoiceDialog<V> extends StatefulWidget {
  final NewChoice<V>? newChoice;
  final String title;
  final String choiceLabel;
  final List<({V value, String label})> options;
  final V initialChoice;
  final String? hint;
  final String? initialText;
  final String confirmLabel;
  final String cancelLabel;

  const _TextWithChoiceDialog({
    this.newChoice,
    required this.title,
    required this.choiceLabel,
    required this.options,
    required this.initialChoice,
    this.hint,
    this.initialText,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  State<_TextWithChoiceDialog<V>> createState() => _TextWithChoiceDialogState<V>();
}

class _TextWithChoiceDialogState<V> extends State<_TextWithChoiceDialog<V>> {
  late final _controller = TextEditingController(text: widget.initialText);
  late V _choice = widget.initialChoice;
  late final List<({V value, String label})> _options = [...widget.options];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, (text: v, choice: _choice));
  }

  Future<void> _addChoice() async {
    final make = widget.newChoice!;
    final name = await showTextPromptDialog(context, title: make.title, hint: make.hint);
    if (name == null || !mounted) return;
    final made = make.create(name);
    setState(() {
      if (!_options.any((o) => o.value == made.value)) _options.add(made);
      _choice = made.value;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(hintText: widget.hint),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text(widget.choiceLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final o in _options)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: _choice == o.value,
                    onSelected: (_) => setState(() => _choice = o.value),
                  ),
                if (widget.newChoice != null)
                  ActionChip(avatar: const Icon(Icons.add, size: 18), label: Text(widget.newChoice!.label), onPressed: _addChoice),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// Asks for one choice from [options] plus a number (Bangla or English digits).
/// Returns null if cancelled. An invalid number keeps the dialog open.
Future<({V choice, double number})?> showChoiceNumberDialog<V>(
  BuildContext context, {
  required String title,
  required String choiceLabel,
  required List<({V value, String label})> options,
  required V initialChoice,
  required String numberLabel,
  double? initialNumber,
  String? confirmLabel,
  String? cancelLabel,
}) =>
    showDialog<({V choice, double number})>(
      context: context,
      builder: (_) => _ChoiceNumberDialog<V>(
        title: title,
        choiceLabel: choiceLabel,
        options: options,
        initialChoice: initialChoice,
        numberLabel: numberLabel,
        initialNumber: initialNumber,
        confirmLabel: confirmLabel ?? Bn.save,
        cancelLabel: cancelLabel ?? Bn.cancel,
      ),
    );

class _ChoiceNumberDialog<V> extends StatefulWidget {
  final String title;
  final String choiceLabel;
  final List<({V value, String label})> options;
  final V initialChoice;
  final String numberLabel;
  final double? initialNumber;
  final String confirmLabel;
  final String cancelLabel;

  const _ChoiceNumberDialog({
    required this.title,
    required this.choiceLabel,
    required this.options,
    required this.initialChoice,
    required this.numberLabel,
    this.initialNumber,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  State<_ChoiceNumberDialog<V>> createState() => _ChoiceNumberDialogState<V>();
}

class _ChoiceNumberDialogState<V> extends State<_ChoiceNumberDialog<V>> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNumber == null ? '' : formatNumber(widget.initialNumber!),
  );
  late V _choice = widget.initialChoice;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final n = parseNumber(_controller.text);
    if (n == null) return;
    Navigator.pop(context, (choice: _choice, number: n));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<V>(
              initialValue: _choice,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.choiceLabel),
              items: [for (final o in widget.options) DropdownMenuItem(value: o.value, child: Text(o.label))],
              onChanged: (v) => setState(() => _choice = v ?? _choice),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: widget.numberLabel),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// Asks for a number (Bangla or English digits). Returns null if cancelled or invalid.
Future<double?> showNumberDialog(
  BuildContext context, {
  required String title,
  required String label,
  double? initial,
  String? confirmLabel,
  String? cancelLabel,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _NumberDialog(
        title: title,
        label: label,
        initial: initial,
        confirmLabel: confirmLabel ?? Bn.save,
        cancelLabel: cancelLabel ?? Bn.cancel,
      ),
    );

class _NumberDialog extends StatefulWidget {
  final String title;
  final String label;
  final double? initial;
  final String confirmLabel;
  final String cancelLabel;
  const _NumberDialog({
    required this.title,
    required this.label,
    this.initial,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null ? '' : formatNumber(widget.initial!),
  )..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial == null ? 0 : formatNumber(widget.initial!).length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, parseNumber(_controller.text));

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      );
}

/// A message with a single OK button.
Future<void> showInfoDialog(BuildContext context, {required String message, String? okLabel}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(okLabel ?? Bn.understood))],
      ),
    );

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  String? cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel ?? Bn.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> showConfirmDeleteDialog(BuildContext context) =>
    showConfirmDialog(context, message: Bn.confirmDelete, confirmLabel: Bn.delete);
