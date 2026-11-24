// Builds the release APK, raising the version first and putting it in the name.
//
//   dart run tool/build_apk.dart              1.0.0+1 -> 1.0.1+2   (patch + build number)
//   dart run tool/build_apk.dart --minor      1.0.5+9 -> 1.1.0+10
//   dart run tool/build_apk.dart --major      1.4.2+9 -> 2.0.0+10
//   dart run tool/build_apk.dart --no-bump    build again at the current version
//
// The new version is written to pubspec.yaml (so the app shows it), the build
// is run, and the APK is copied next to the usual one as
// build/app/outputs/flutter-apk/dokan-khata-<version>-build<number>.apk.
// If the build fails, pubspec.yaml is put back as it was.
//
// Flutter is taken from the FLUTTER environment variable if set, otherwise
// from the PATH.
import 'dart:io';

import 'apk_version.dart';

Future<void> main(List<String> args) async {
  final part = args.contains('--major')
      ? VersionPart.major
      : args.contains('--minor')
          ? VersionPart.minor
          : VersionPart.patch;
  final bump = !args.contains('--no-bump');

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Run this from the project folder (pubspec.yaml not found).');
    exit(2);
  }
  final original = pubspecFile.readAsStringSync();
  final current = versionIn(original);
  final next = bump ? current.bump(part) : current;
  if (bump) pubspecFile.writeAsStringSync(withVersion(original, next));
  stdout.writeln(bump ? 'Version $current -> $next' : 'Version $current (not raised)');

  final flutter = Platform.environment['FLUTTER'] ?? (Platform.isWindows ? 'flutter.bat' : 'flutter');
  final build = await Process.start(
    flutter,
    ['build', 'apk', '--release'],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await build.exitCode;
  if (code != 0) {
    if (bump) pubspecFile.writeAsStringSync(original); // nothing was released: keep the old number
    stderr.writeln('The build failed (exit $code). The version was put back to $current.');
    exit(code);
  }

  final built = File('build/app/outputs/flutter-apk/app-release.apk');
  final named = File('build/app/outputs/flutter-apk/${apkFileName(next)}');
  built.copySync(named.path);
  stdout.writeln('\nAPK: ${named.absolute.path} (${(named.lengthSync() / 1048576).toStringAsFixed(1)} MB)');
}
