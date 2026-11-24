import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../domain/import/csv_source.dart';
import '../../domain/import/product_importer.dart';

enum ImportStatus { idle, running, done, cancelled }

class ImportViewModel extends ChangeNotifier {
  final CsvSource _source;
  final ProductImporter _importer;
  ImportViewModel(this._source, this._importer);

  ImportStatus status = ImportStatus.idle;
  ImportResult? result;

  /// Off by default: file prices/stock are often unverified estimates.
  bool withPricesAndStock = false;

  void setWithPricesAndStock(bool value) {
    withPricesAndStock = value;
    notifyListeners();
  }

  Future<void> pickAndImport() async {
    status = ImportStatus.running;
    result = null;
    notifyListeners();
    try {
      final text = await _source.pick();
      if (text == null) {
        status = ImportStatus.cancelled;
      } else {
        result = await _importer.import(text, withPricesAndStock: withPricesAndStock);
        status = ImportStatus.done;
      }
    } catch (_) {
      result = const ImportResult(fatalError: 'ফাইলটি পড়া যায়নি');
      status = ImportStatus.done;
    }
    notifyListeners();
  }
}
