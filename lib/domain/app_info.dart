/// Tells which version of the app this is (so people can say which one they
/// have when something goes wrong).
abstract class AppVersionSource {
  /// For example "1.0.0 (3)": the version, then the build number.
  Future<String> label();
}
