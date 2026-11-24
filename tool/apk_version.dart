/// The version rules for `tool/build_apk.dart`, kept apart so they can be tested.
library;

/// Which part of the version a build raises. The build number (the part after
/// "+") always goes up by one, whatever is chosen.
enum VersionPart { patch, minor, major }

/// A version as written in pubspec.yaml: `1.2.3+4`.
class AppVersion {
  final int major;
  final int minor;
  final int patch;
  final int build;
  const AppVersion(this.major, this.minor, this.patch, this.build);

  /// Reads `1.2.3+4`. Throws [FormatException] for anything else.
  factory AppVersion.parse(String text) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(text.trim());
    if (m == null) throw FormatException('Expected a version like 1.2.3+4, got "$text"');
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
  }

  /// The next version: [part] goes up (lower parts reset), the build number goes up by one.
  AppVersion bump(VersionPart part) => switch (part) {
        VersionPart.patch => AppVersion(major, minor, patch + 1, build + 1),
        VersionPart.minor => AppVersion(major, minor + 1, 0, build + 1),
        VersionPart.major => AppVersion(major + 1, 0, 0, build + 1),
      };

  /// `1.2.3` (what people see as the version).
  String get name => '$major.$minor.$patch';

  @override
  String toString() => '$name+$build';

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.major == major && other.minor == minor && other.patch == patch && other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

/// The APK's file name, with the version in it: `dokan-khata-1.2.3-build4.apk`.
String apkFileName(AppVersion version) => 'dokan-khata-${version.name}-build${version.build}.apk';

/// [pubspec] with its `version:` line changed to [version]. Throws
/// [FormatException] if there is no such line.
String withVersion(String pubspec, AppVersion version) {
  final line = RegExp(r'^version:.*$', multiLine: true);
  if (!line.hasMatch(pubspec)) throw const FormatException('pubspec.yaml has no "version:" line');
  return pubspec.replaceFirst(line, 'version: $version');
}

/// The version written in [pubspec].
AppVersion versionIn(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  if (m == null) throw const FormatException('pubspec.yaml has no "version:" line');
  return AppVersion.parse(m[1]!);
}
