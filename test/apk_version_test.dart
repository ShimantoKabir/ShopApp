import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/apk_version.dart';

void main() {
  group('reading and raising the version', () {
    test('1.0.0+1 becomes 1.0.1+2 by default (patch and build number)', () {
      expect(AppVersion.parse('1.0.0+1').bump(VersionPart.patch).toString(), '1.0.1+2');
    });

    test('a minor bump resets the patch; a major bump resets both; the build number always goes up by one', () {
      expect(AppVersion.parse('1.0.5+9').bump(VersionPart.minor).toString(), '1.1.0+10');
      expect(AppVersion.parse('1.4.2+9').bump(VersionPart.major).toString(), '2.0.0+10');
    });

    test('numbers do not stop at nine', () {
      expect(AppVersion.parse('1.0.9+99').bump(VersionPart.patch).toString(), '1.0.10+100');
    });

    test('anything that is not major.minor.patch+build is refused', () {
      for (final bad in ['1.0.0', '1.0+1', 'a.b.c+d', '', '1.0.0+']) {
        expect(() => AppVersion.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('the APK name', () {
    test('has the version and the build number in it', () {
      expect(apkFileName(AppVersion.parse('1.0.1+2')), 'dokan-khata-1.0.1-build2.apk');
      expect(apkFileName(AppVersion.parse('2.3.4+15')), 'dokan-khata-2.3.4-build15.apk');
    });
  });

  group('pubspec.yaml', () {
    const pubspec = 'name: hardware_shop\nversion: 1.0.0+1\n\nenvironment:\n  sdk: ^3.0.0\n';

    test('the version is read from it and written back, changing nothing else', () {
      expect(versionIn(pubspec).toString(), '1.0.0+1');
      final changed = withVersion(pubspec, AppVersion.parse('1.0.1+2'));
      expect(changed, 'name: hardware_shop\nversion: 1.0.1+2\n\nenvironment:\n  sdk: ^3.0.0\n');
      expect(versionIn(changed).toString(), '1.0.1+2');
    });

    test('a pubspec with no version line is refused, not guessed at', () {
      expect(() => versionIn('name: x\n'), throwsFormatException);
      expect(() => withVersion('name: x\n', AppVersion.parse('1.0.0+1')), throwsFormatException);
    });

    test('the real pubspec.yaml has a valid version', () {
      expect(() => versionIn(File('pubspec.yaml').readAsStringSync()), returnsNormally);
    });
  });
}
