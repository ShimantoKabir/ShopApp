import 'dart:math';

import '../domain/services.dart';

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

class RandomLocationCodeGenerator implements LocationCodeGenerator {
  final Random _random;
  RandomLocationCodeGenerator([Random? random]) : _random = random ?? Random.secure();

  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  @override
  String generate() =>
      'HLOC-${List.generate(8, (_) => _chars[_random.nextInt(_chars.length)]).join()}';
}
