/// Where CSV text comes from (file picker, tests, ...). Returns null if the
/// user cancelled.
abstract class CsvSource {
  Future<String?> pick();
}
