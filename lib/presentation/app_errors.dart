import 'package:material_ui/material_ui.dart';

import 'labels.dart';

/// Shows a broken rule (no connection, not enough stock...) as a message,
/// wherever on screen it came from. Returns true if it was one of those and has
/// been shown; false for a real fault, which must not be hidden.
///
/// This is the safety net for any screen that did not catch the error itself.
bool showRuleError(GlobalKey<ScaffoldMessengerState> messenger, Object error) {
  final message = ruleMessage(error);
  if (message == null) return false;
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return true;
}
