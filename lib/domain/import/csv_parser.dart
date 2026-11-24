/// Minimal CSV parser (RFC 4180 style): quoted fields, escaped quotes (""),
/// newlines inside quotes, BOM, and comma or semicolon delimiters.
/// Pure Dart so it can be unit tested.
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final delimiter = _detectDelimiter(text);

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // Skip fully blank lines.
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == delimiter) {
      endField();
    } else if (c == '\n') {
      endRow();
    } else if (c == '\r') {
      // Handled by the following \n (or ignored if alone).
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Picks ';' only when the header line clearly uses it instead of ','.
String _detectDelimiter(String text) {
  final firstLine = text.split('\n').first;
  final commas = ','.allMatches(firstLine).length;
  final semicolons = ';'.allMatches(firstLine).length;
  return semicolons > commas ? ';' : ',';
}
