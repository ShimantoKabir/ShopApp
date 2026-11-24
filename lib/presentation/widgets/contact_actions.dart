import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/customer_rules.dart';
import '../../domain/services.dart';

/// Two small buttons to reach a customer: call, and share a message (a due
/// reminder, say) on any app through the phone's share sheet. Meant to sit
/// inside a card. Shows nothing when there is no valid number; the share
/// button is left out when there is no [message] to share.
class ContactActions extends StatelessWidget {
  final ContactLauncher launcher;
  final String mobile;
  final String whatsapp;
  final String message;

  const ContactActions({super.key, required this.launcher, this.mobile = '', this.whatsapp = '', this.message = ''});

  /// Whether there is any number to reach them on.
  static bool canReach(String mobile, String whatsapp) => [mobile, whatsapp].any(isValidMobile);

  Future<void> _run(BuildContext context, Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await action()) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Bn.contactFailed)));
    }
  }

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed) => IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 18,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );

  @override
  Widget build(BuildContext context) {
    final phone = [mobile, whatsapp].where(isValidMobile).firstOrNull;
    if (phone == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.call_outlined, Bn.contactCall, () => _run(context, () => launcher.call(phone))),
        if (message.isNotEmpty) ...[
          const SizedBox(width: 10),
          _button(Icons.share_outlined, Bn.contactShare, () => _run(context, () => launcher.share(message))),
        ],
      ],
    );
  }
}
