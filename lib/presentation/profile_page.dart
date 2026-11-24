import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/users.dart';
import 'auth_viewmodels.dart';
import 'components/components.dart';
import 'labels.dart';

/// Someone's own details (name, mobile, other phone, address) and their PIN.
/// The page owns (and disposes) its [viewModel].
class ProfilePage extends StatefulWidget {
  final ProfileViewModel viewModel;
  const ProfilePage({super.key, required this.viewModel});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _detailsKey = GlobalKey<FormState>();
  final _pinKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _me.name);
  late final _mobile = TextEditingController(text: _me.mobile);
  late final _phone = TextEditingController(text: _me.phone);
  late final _address = TextEditingController(text: _me.address);
  final _currentPin = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _savingDetails = false;
  bool _savingPin = false;

  ProfileViewModel get _vm => widget.viewModel;
  AppUser get _me => _vm.user!;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _phone, _address, _currentPin, _newPin, _confirmPin]) {
      c.dispose();
    }
    _vm.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action]; a broken rule is shown instead of crashing.
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

  Future<void> _saveDetails() async {
    if (!_detailsKey.currentState!.validate() || _savingDetails) return;
    setState(() => _savingDetails = true);
    final ok = await _try(() => _vm.save(name: _name.text, mobile: _mobile.text, phone: _phone.text, address: _address.text));
    if (!mounted) return;
    setState(() => _savingDetails = false);
    if (ok) _say(Bn.profileSaved);
  }

  Future<void> _changePin() async {
    if (!_pinKey.currentState!.validate() || _savingPin) return;
    setState(() => _savingPin = true);
    final ok = await _try(() => _vm.changePin(_currentPin.text, _newPin.text));
    if (!mounted) return;
    setState(() => _savingPin = false);
    if (ok) {
      for (final c in [_currentPin, _newPin, _confirmPin]) {
        c.clear();
      }
      _say(Bn.pinChanged);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(Bn.profileTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Form(
              key: _detailsKey,
              child: SectionCard(
                title: Bn.profileDetails,
                icon: Icons.person_outline,
                children: [
                  RequiredTextFormField(controller: _name, label: Bn.userName),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: Bn.profileMobile),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: Bn.profilePhone),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    minLines: 2,
                    maxLines: 3,
                    keyboardType: TextInputType.streetAddress,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: Bn.profileAddress),
                  ),
                  const SizedBox(height: 16),
                  ActionButtonRow(primaryLabel: Bn.save, onPrimary: _saveDetails, busy: _savingDetails),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Form(
              key: _pinKey,
              child: SectionCard(
                title: Bn.profilePinSection,
                icon: Icons.password,
                children: [
                  PinField(controller: _currentPin, label: Bn.currentPinLabel, validate: true),
                  const SizedBox(height: 12),
                  PinField(controller: _newPin, label: Bn.newPinLabel, validate: true),
                  const SizedBox(height: 12),
                  PinField(
                    controller: _confirmPin,
                    label: Bn.pinConfirm,
                    validate: true,
                    mustMatch: _newPin,
                    onSubmitted: (_) => _changePin(),
                  ),
                  const SizedBox(height: 16),
                  ActionButtonRow(primaryLabel: Bn.profilePinSection, onPrimary: _changePin, busy: _savingPin),
                ],
              ),
            ),
          ],
        ),
      );
}
