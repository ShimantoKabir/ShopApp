import 'package:package_info_plus/package_info_plus.dart';

import '../domain/app_info.dart';

/// Reads the version from the installed app itself (what pubspec.yaml said
/// when it was built).
class PackageInfoVersionSource implements AppVersionSource {
  @override
  Future<String> label() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';
  }
}
