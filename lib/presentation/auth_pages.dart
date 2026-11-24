import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/users.dart';
import 'auth_viewmodels.dart';
import 'components/components.dart';
import 'labels.dart';
import 'screen_factory.dart';

/// Decides what to show at start: set the shop up (first run), sign in, or the
/// app itself. Signing out comes back here. Owns (and disposes) its [viewModel].
class AuthGate extends StatefulWidget {
  final AuthViewModel viewModel;
  final ScreenFactory screens;
  const AuthGate({super.key, required this.viewModel, required this.screens});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthViewModel get _vm => widget.viewModel;
  StreamSubscription<void>? _wipedSubscription;

  @override
  void initState() {
    super.initState();
    _vm.load();
    // After everything was erased, every page opened on top (settings...) closes.
    _wipedSubscription = _vm.wiped.listen((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  void dispose() {
    _wipedSubscription?.cancel();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _vm,
        builder: (context, _) {
          if (_vm.signedIn) return widget.screens.shell(onSignOut: _vm.signOut);
          if (_vm.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return _vm.hasUsers ? LoginPage(viewModel: _vm) : SetupPage(viewModel: _vm, screens: widget.screens);
        },
      );
}

void _say(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Pick who you are and type your PIN.
class LoginPage extends StatefulWidget {
  final AuthViewModel viewModel;
  const LoginPage({super.key, required this.viewModel});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _pin = TextEditingController();
  AppUser? _selected;
  bool _busy = false;

  AuthViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    if (_vm.users.length == 1) _selected = _vm.users.single;
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final who = _selected;
    if (who == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _vm.signIn(who, _pin.text);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _pin.clear();
      if (mounted) _say(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 96)),
                  const SizedBox(height: 12),
                  Text(Bn.appTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  if (_vm.users.isEmpty)
                    EmptyState(message: Bn.noActiveUsers, icon: Icons.lock_outline)
                  else ...[
                    Text(Bn.chooseUser, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ChoiceChipBar<AppUser>(
                      options: [for (final u in _vm.users) ChipOption(u, u.name)],
                      selected: _selected,
                      onSelected: (u) => setState(() => _selected = u),
                      scrollable: false,
                    ),
                    const SizedBox(height: 16),
                    PinField(controller: _pin, label: Bn.pinLabel, onSubmitted: (_) => _signIn()),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _selected == null || _busy ? null : _signIn,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(Bn.signIn),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// First run: create the owner.
class SetupPage extends StatefulWidget {
  final AuthViewModel viewModel;
  final ScreenFactory screens;
  const SetupPage({super.key, required this.viewModel, required this.screens});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _pin, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  /// This is a new phone for a shop that already exists: download it, then the
  /// sign in screen takes over.
  Future<void> _join() async {
    final joined = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => widget.screens.joinShop()));
    if (joined == true) await widget.viewModel.load();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.viewModel.createOwner(_name.text, _pin.text);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      if (mounted) _say(context, message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(size: 96)),
                    const SizedBox(height: 12),
                    Text(Bn.setupTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(Bn.setupIntro, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    RequiredTextFormField(controller: _name, label: Bn.ownerName),
                    const SizedBox(height: 12),
                    PinField(controller: _pin, label: Bn.pinLabel, validate: true),
                    const SizedBox(height: 12),
                    PinField(
                      controller: _confirm,
                      label: Bn.pinConfirm,
                      validate: true,
                      mustMatch: _pin,
                      onSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 20),
                    ActionButtonRow(primaryLabel: Bn.createOwner, onPrimary: _create, busy: _busy),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _join, child: Text(Bn.joinShopLink)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
