import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../domain/services.dart';

/// Picks a customer with the phone's own contact chooser (no contacts
/// permission needed: the phone hands over only the contact that was chosen).
class PlatformContactPicker implements ContactPicker {
  final FlutterNativeContactPicker _picker;
  PlatformContactPicker([FlutterNativeContactPicker? picker]) : _picker = picker ?? FlutterNativeContactPicker();

  @override
  Future<PickedContact?> pick() async {
    try {
      final contact = await _picker.selectPhoneNumber();
      if (contact == null) return null;
      final number = (contact.selectedPhoneNumber ?? contact.phoneNumbers?.firstOrNull ?? '').trim();
      if (number.isEmpty) return null;
      return PickedContact(name: (contact.fullName ?? '').trim(), number: number);
    } catch (_) {
      return null;
    }
  }
}
