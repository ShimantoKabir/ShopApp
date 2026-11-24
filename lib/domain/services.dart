/// Small abstractions for things that were previously hardcoded inside
/// repositories (time, randomness), so they can be replaced and tested.
abstract class Clock {
  DateTime now();
}

abstract class LocationCodeGenerator {
  /// Returns a new unique-looking code to encode in a location QR.
  String generate();
}

/// Reaches a customer by phone: a call, an SMS, or WhatsApp. Behind an
/// interface so screens do not depend on the plugin and tests can record it.
/// Each returns false if the number is not a valid Bangladeshi mobile number or
/// nothing on the phone could open it.
abstract class ContactLauncher {
  /// Opens the phone's dialer with the number ready.
  Future<bool> call(String mobile);

  /// Opens the share sheet with [message], so it can be sent on any app
  /// (WhatsApp, SMS, Messenger...). False if it could not be opened.
  Future<bool> share(String message);
}

/// Gets a receipt to the customer. Behind an interface so screens don't depend
/// on any particular app or plugin, and so tests can record what was sent.
abstract class ReceiptSender {
  /// Opens WhatsApp with [message] ready to send to [mobile] (a Bangladeshi
  /// mobile number in any usual format). Staff still tap Send in WhatsApp:
  /// sending with no tap needs the paid WhatsApp Business API and a server.
  /// Returns false if [mobile] is not valid or WhatsApp could not be opened.
  Future<bool> sendWhatsApp(String mobile, String message);

  /// Opens the system share sheet with [message] (WhatsApp, SMS, Messenger...).
  Future<void> share(String message);
}
