import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';

import 'dialogs.dart';
import 'display_parts.dart';

/// Wraps any child with swipe-to-delete. The confirmation is injectable.
class SwipeToDelete extends StatelessWidget {
  final Object itemKey;
  final Widget child;
  final VoidCallback onDelete;
  final Future<bool> Function(BuildContext context)? confirm;

  const SwipeToDelete({super.key, required this.itemKey, required this.child, required this.onDelete, this.confirm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(itemKey),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      confirmDismiss: (_) => (confirm ?? showConfirmDeleteDialog)(context),
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }
}

/// Card row with a trailing delete button (confirmed). If [blockedMessage] is
/// set, the button explains why the item can't be deleted instead.
class DeletableListTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback onDelete;
  final String? blockedMessage;

  /// When given, an edit button is shown beside the delete button. It is never
  /// blocked, even when deleting is.
  final VoidCallback? onEdit;

  const DeletableListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
    required this.onDelete,
    this.blockedMessage,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: leading,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          onTap: onTap,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: Bn.edit, onPressed: onEdit),
              IconButton(
                icon: Icon(blockedMessage == null ? Icons.delete_outline : Icons.lock_outline),
                tooltip: Bn.delete,
                onPressed: () async {
                  if (blockedMessage != null) {
                    await showInfoDialog(context, message: blockedMessage!);
                  } else if (await showConfirmDeleteDialog(context)) {
                    onDelete();
                  }
                },
              ),
            ],
          ),
        ),
      );
}

/// Generic list of cards with loading and empty states. Pass [onDelete] and
/// [itemKey] to enable swipe-to-delete.
class AsyncListView<T> extends StatelessWidget {
  final List<T> items;
  final bool loading;
  final String emptyMessage;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Object Function(T item)? itemKey;
  final ValueChanged<T>? onDelete;

  /// Replaces the default "delete?" confirmation for swipe-to-delete.
  final Future<bool> Function(BuildContext context)? deleteConfirm;

  /// When given, only the rows it returns true for can be swiped away.
  final bool Function(T item)? canDelete;

  const AsyncListView({
    super.key,
    required this.items,
    required this.loading,
    required this.emptyMessage,
    required this.itemBuilder,
    this.itemKey,
    this.onDelete,
    this.deleteConfirm,
    this.canDelete,
  }) : assert(onDelete == null || itemKey != null, 'itemKey is required when onDelete is set');

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return EmptyState(message: emptyMessage);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = items[i];
        final child = itemBuilder(context, item);
        if (onDelete == null || (canDelete != null && !canDelete!(item))) return child;
        return SwipeToDelete(
          itemKey: itemKey!(item),
          onDelete: () => onDelete!(item),
          confirm: deleteConfirm,
          child: child,
        );
      },
    );
  }
}

/// A screen that lists named items with an "add" button and delete buttons.
/// Categories and locations are both just instances of this.
class ManageListScaffold<T> extends StatelessWidget {
  final String title;
  final String addLabel;
  final Listenable listenable;
  final List<T> Function() items;
  final String Function(T item) titleOf;
  final String? Function(T item)? subtitleOf;
  final Widget? Function(T item)? leadingOf;
  final ValueChanged<T>? onTap;
  final ValueChanged<T> onDelete;
  final VoidCallback onAdd;

  /// When given, each row has an edit button.
  final ValueChanged<T>? onEdit;

  /// Extra buttons in the top bar (e.g. a scanner).
  final List<Widget>? actions;

  /// Return a message to block deleting [item] (and explain why), or null to allow it.
  final String? Function(T item)? deleteBlockedMessage;

  const ManageListScaffold({
    super.key,
    required this.title,
    required this.addLabel,
    required this.listenable,
    required this.items,
    required this.titleOf,
    required this.onDelete,
    required this.onAdd,
    this.subtitleOf,
    this.leadingOf,
    this.onTap,
    this.deleteBlockedMessage,
    this.onEdit,
    this.actions,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
        body: ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final all = items();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: all.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final item = all[i];
                return DeletableListTile(
                  leading: leadingOf?.call(item),
                  title: titleOf(item),
                  subtitle: subtitleOf?.call(item),
                  onTap: onTap == null ? null : () => onTap!(item),
                  onDelete: () => onDelete(item),
                  blockedMessage: deleteBlockedMessage?.call(item),
                  onEdit: onEdit == null ? null : () => onEdit!(item),
                );
              },
            );
          },
        ),
      );
}
