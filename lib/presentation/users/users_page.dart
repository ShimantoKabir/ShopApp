import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/users.dart';
import 'users_viewmodel.dart';
import '../components/components.dart';
import '../labels.dart';

/// The owner's list of people who can use the app: add someone, change a PIN,
/// switch someone off (they can no longer sign in; what they did stays on
/// record). The page owns (and disposes) its [viewModel].
class UsersPage extends StatefulWidget {
  final UsersViewModel viewModel;

  /// Only the owner may add people, change PINs or switch people off; anyone else just sees the list.
  final bool canManage;
  const UsersPage({super.key, required this.viewModel, this.canManage = true});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  UsersViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action]; a broken rule is shown to the user instead of crashing.
  Future<bool> _try(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _say(message);
      return false;
    }
  }

  Future<void> _add() async {
    final input = await showUserDialog(context, title: Bn.addUser, askNameAndRole: true);
    if (input == null) return;
    if (await _try(() => _vm.add(input.name, input.pin, input.role))) _say(Bn.userAdded);
  }

  Future<void> _resetPin(AppUser user) async {
    final input = await showUserDialog(context, title: '${Bn.resetPin}: ${user.name}', askNameAndRole: false);
    if (input == null) return;
    if (await _try(() => _vm.resetPin(user, input.pin))) _say(Bn.pinChanged);
  }

  Future<void> _options(AppUser user) async {
    final isMe = user.id == _vm.me?.id;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.password), title: Text(Bn.resetPin), onTap: () => Navigator.pop(ctx, 'pin')),
            if (!isMe)
              ListTile(
                leading: Icon(user.active ? Icons.person_off_outlined : Icons.person_outline),
                title: Text(user.active ? Bn.switchOff : Bn.switchOn),
                onTap: () => Navigator.pop(ctx, 'toggle'),
              ),
          ],
        ),
      ),
    );
    if (choice == 'pin') await _resetPin(user);
    if (choice == 'toggle') await _try(() => _vm.setActive(user, !user.active));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.usersTitle)),
        floatingActionButton: !widget.canManage ? null : FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(Bn.addUser),
        ),
        body: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) {
            final scheme = Theme.of(context).colorScheme;
            if (_vm.loading) return const Center(child: CircularProgressIndicator());
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: _vm.users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = _vm.users[i];
                return ItemCard(
                  title: u.name,
                  subtitle: [u.mobile, u.address].where((e) => e.isNotEmpty).join(' • '),
                  onTap: widget.canManage ? () => _options(u) : null,
                  leading: CircleAvatar(
                    backgroundColor: u.active ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
                    foregroundColor: u.active ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                    child: Icon(u.isOwner ? Icons.admin_panel_settings_outlined : Icons.person_outline),
                  ),
                  chips: [
                    InfoChip(label: roleLabel(u.role)),
                    if (u.id == _vm.me?.id) InfoChip(label: Bn.youChip, icon: Icons.check),
                    if (!u.active)
                      InfoChip(label: Bn.inactiveChip, background: scheme.errorContainer, foreground: scheme.onErrorContainer),
                  ],
                );
              },
            );
          },
        ),
      );
}

/// Asks for a PIN, and (for a new person) a name and a role.
Future<({String name, String pin, UserRole role})?> showUserDialog(
  BuildContext context, {
  required String title,
  required bool askNameAndRole,
}) =>
    showDialog<({String name, String pin, UserRole role})>(
      context: context,
      builder: (_) => _UserDialog(title: title, askNameAndRole: askNameAndRole),
    );

class _UserDialog extends StatefulWidget {
  final String title;
  final bool askNameAndRole;
  const _UserDialog({required this.title, required this.askNameAndRole});

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  UserRole _role = UserRole.staff;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (name: _name.text.trim(), pin: _pin.text, role: _role));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.askNameAndRole) ...[
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: Bn.userName),
                    validator: (v) => (v ?? '').trim().isEmpty ? Bn.authInvalidName : null,
                  ),
                  const SizedBox(height: 12),
                ],
                PinField(
                  controller: _pin,
                  label: widget.askNameAndRole ? Bn.pinLabel : Bn.newPinLabel,
                  validate: true,
                  obscure: false, // the owner is choosing this for someone else
                  onSubmitted: (_) => _submit(),
                ),
                if (widget.askNameAndRole) ...[
                  const SizedBox(height: 12),
                  ChoiceChipBar<UserRole>(
                    options: [for (final r in UserRole.values.reversed) ChipOption(r, roleLabel(r))],
                    selected: _role,
                    onSelected: (r) => setState(() => _role = r ?? UserRole.staff),
                    scrollable: false,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(Bn.cancel)),
          FilledButton(onPressed: _submit, child: Text(Bn.save)),
        ],
      );
}
