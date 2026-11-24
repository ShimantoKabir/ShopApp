import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customer_rules.dart';
import '../../domain/services.dart';

/// A small button for a number field: choose the customer from the phone's
/// contacts instead of typing. Shows nothing when there is no [picker].
class ContactPickButton extends StatelessWidget {
  final ContactPicker? picker;

  /// Called with the chosen contact; the number is already tidied into the
  /// usual 01XXXXXXXXX form when it is a Bangladeshi mobile number.
  final void Function(PickedContact contact) onPicked;
  const ContactPickButton({super.key, required this.picker, required this.onPicked});

  Future<void> _pick() async {
    final contact = await picker!.pick();
    if (contact == null) return;
    final tidy = normalizeMobile(contact.number);
    onPicked(PickedContact(name: contact.name, number: isValidMobile(tidy) ? tidy : contact.number));
  }

  @override
  Widget build(BuildContext context) => picker == null
      ? const SizedBox.shrink()
      : IconButton(onPressed: _pick, icon: const Icon(Icons.contacts_outlined), tooltip: Bn.pickContact);
}
