import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import '../domain/import/csv_source.dart';

/// Lets the user choose a CSV file from the phone.
class FilePickerCsvSource implements CsvSource {
  @override
  Future<String?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    // Tolerate stray bad bytes rather than failing the whole import.
    return utf8.decode(bytes, allowMalformed: true);
  }
}
