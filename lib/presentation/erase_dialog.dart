import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';

/// Asks the owner to confirm erasing all data: a warning, a tick saying they
/// are fully aware, and a word to type. Only when all of that is done can the
/// button be used. Returns true if they confirmed.
Future<bool> askConfirmErase(BuildContext context, {required bool shared}) async =>
    await showDialog<bool>(context: context, builder: (_) => _EraseDialog(shared: shared)) ?? false;

class _EraseDialog extends StatefulWidget {
  final bool shared;
  const _EraseDialog({required this.shared});

  @override
  State<_EraseDialog> createState() => _EraseDialogState();
}

class _EraseDialogState extends State<_EraseDialog> {
  final _word = TextEditingController();
  bool _aware = false;

  @override
  void dispose() {
    _word.dispose();
    super.dispose();
  }

  bool get _ready => _aware && _word.text.trim().toUpperCase() == Bn.eraseWord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 36),
      title: Text(Bn.eraseDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Bn.eraseWarning, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
            if (widget.shared) ...[
              const SizedBox(height: 12),
              Text(Bn.eraseSharedWarning),
            ],
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _aware,
              onChanged: (v) => setState(() => _aware = v ?? false),
              title: Text(Bn.eraseConsent),
            ),
            const SizedBox(height: 4),
            Text(Bn.eraseTypePrompt),
            const SizedBox(height: 8),
            TextField(
              controller: _word,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: Bn.eraseWord),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(Bn.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: _ready ? () => Navigator.pop(context, true) : null,
          child: Text(Bn.eraseConfirm),
        ),
      ],
    );
  }
}
