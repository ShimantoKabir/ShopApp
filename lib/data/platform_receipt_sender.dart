import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/customer_rules.dart';
import '../domain/services.dart';

/// The WhatsApp link that opens a chat with [mobile] and the message typed in,
/// or null if [mobile] is not a valid Bangladeshi mobile number.
Uri? whatsAppUri(String mobile, String message) {
  final number = whatsAppNumber(mobile);
  if (number == null) return null;
  return Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
}

/// Calls and messages customers through the phone's own apps.
class PlatformContactLauncher implements ContactLauncher {
  Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> call(String mobile) {
    if (!isValidMobile(mobile)) return Future.value(false);
    return _open(Uri(scheme: 'tel', path: normalizeMobile(mobile)));
  }

  @override
  Future<bool> share(String message) async {
    if (message.trim().isEmpty) return false;
    try {
      await SharePlus.instance.share(ShareParams(text: message));
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Sends receipts through the phone: WhatsApp via its public wa.me link, or
/// the system share sheet.
class PlatformReceiptSender implements ReceiptSender {
  @override
  Future<bool> sendWhatsApp(String mobile, String message) async {
    final uri = whatsAppUri(mobile, message);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> share(String message) => SharePlus.instance.share(ShareParams(text: message));
}
