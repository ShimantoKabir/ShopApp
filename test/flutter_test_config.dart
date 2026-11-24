import 'dart:async';

import 'package:hardware_shop/core/language.dart';

/// The app now shows English digits. Most tests were written with Bangla
/// digits in what they expect, so they run with that switched off; the tests
/// of the English-digit behaviour switch it back on for themselves.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Language.englishDigits = false;
  await testMain();
}
