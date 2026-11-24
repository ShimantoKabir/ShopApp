import '../../core/bangla.dart';
import '../entities.dart';
import '../repositories.dart';
import 'csv_parser.dart';

class ImportResult {
  final int added;
  final int skippedDuplicates;

  /// One human-readable line per row that could not be imported.
  final List<String> failures;

  /// Set when the whole file is unusable (e.g. no name column).
  final String? fatalError;

  const ImportResult({this.added = 0, this.skippedDuplicates = 0, this.failures = const [], this.fatalError});
}

/// Turns CSV text into products. Understands the app's own column names
/// (English or Bangla) and common spreadsheet exports.
///
/// By default prices and stock are NOT imported: files from unverified sources
/// carry estimates, and a wrong price in a stock system is worse than none.
/// Imported products without a price show as "price missing" in the app.
class ProductImporter {
  final ProductRepository _products;
  final CategoryRepository _categories;
  ProductImporter(this._products, this._categories);

  /// Normalised header text -> field. Normalising drops case, spaces and punctuation.
  static const _aliases = <String, Set<String>>{
    'name': {'name', 'item', 'itemdescription', 'itemname', 'product', 'productname', 'description', 'পণ্য', 'পণ্যেরনাম', 'নাম'},
    'category': {'category', 'ক্যাটাগরি'},
    'unit': {'unit', 'একক'},
    'stock': {'stock', 'quantity', 'qty', 'initialquantity', 'মজুদ'},
    'purchase': {'purchaseprice', 'estunitcostbdt', 'unitcost', 'cost', 'costprice', 'কেনাদাম'},
    'selling': {'sellingprice', 'saleprice', 'price', 'বিক্রিদাম'},
    'brand': {'brand', 'ব্র্যান্ড'},
    'size': {'size', 'সাইজ'},
    'model': {'model', 'partnumber', 'partno', 'মডেল'},
    'finish': {'finish', 'color', 'colour', 'material', 'রং', 'ফিনিশ'},
    'kind': {'kind', 'type', 'ধরন'},
  };

  static const _unitMap = <String, String>{
    'piece': 'পিস', 'pieces': 'পিস', 'pcs': 'পিস', 'pc': 'পিস', 'mixed': 'পিস',
    'kg': 'কেজি', 'kilogram': 'কেজি',
    'ton': 'টন', 'tonne': 'টন',
    'feet': 'ফুট', 'foot': 'ফুট', 'ft': 'ফুট',
    'meter': 'মিটার', 'metre': 'মিটার', 'm': 'মিটার',
    'litre': 'লিটার', 'liter': 'লিটার', 'l': 'লিটার',
    'tin': 'টিন', 'can': 'ক্যান', 'box': 'বক্স', 'coil': 'কয়েল', 'roll': 'রোল',
    'jar': 'জার', 'pack': 'প্যাক', 'packet': 'প্যাক', 'set': 'সেট',
    'dozen': 'ডজন', 'doz': 'ডজন', 'hundred': 'শত',
  };

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true), '');

  static String mapUnit(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'পিস';
    return _unitMap[_normalise(trimmed)] ?? trimmed;
  }

  static ProductKind _kindFor(String rawKind, String unit) {
    final n = _normalise(rawKind);
    for (final k in ProductKind.values) {
      if (k.name == n) return k;
    }
    return (unit == 'কেজি' || unit == 'টন') ? ProductKind.loose : ProductKind.standard;
  }

  Future<ImportResult> import(String csvText, {bool withPricesAndStock = false}) async {
    final rows = parseCsv(csvText);
    if (rows.length < 2) {
      return const ImportResult(fatalError: 'ফাইলে কোনো পণ্যের সারি পাওয়া যায়নি');
    }

    // Map each field to its column index.
    final columns = <String, int>{};
    final header = rows.first.map(_normalise).toList();
    for (final entry in _aliases.entries) {
      final index = header.indexWhere(entry.value.contains);
      if (index != -1) columns[entry.key] = index;
    }
    if (!columns.containsKey('name')) {
      return const ImportResult(fatalError: 'ফাইলে পণ্যের নামের কলাম (Name / Item) পাওয়া যায়নি');
    }

    String cell(List<String> row, String field) {
      final i = columns[field];
      return (i == null || i >= row.length) ? '' : row[i].trim();
    }

    var added = 0;
    var skipped = 0;
    final failures = <String>[];

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      final lineNo = r + 1; // 1-based, counting the header
      try {
        final name = cell(row, 'name');
        if (name.isEmpty) {
          failures.add('সারি ${toBanglaDigits('$lineNo')}: নাম নেই');
          continue;
        }
        final brand = cell(row, 'brand');
        final size = cell(row, 'size');
        if (await _products.existsSimilar(name: name, brand: brand, size: size)) {
          skipped++;
          continue;
        }

        final unit = mapUnit(cell(row, 'unit'));
        int? categoryId;
        final categoryName = cell(row, 'category');
        if (categoryName.isNotEmpty) categoryId = (await _categories.add(categoryName)).id;

        await _products.save(Product(
          name: name,
          kind: _kindFor(cell(row, 'kind'), unit),
          categoryId: categoryId,
          brand: brand,
          size: size,
          model: cell(row, 'model'),
          finish: cell(row, 'finish'),
          unit: unit,
          purchasePrice: withPricesAndStock ? (parseNumber(cell(row, 'purchase')) ?? 0) : 0,
          sellingPrice: withPricesAndStock ? (parseNumber(cell(row, 'selling')) ?? 0) : 0,
          stock: withPricesAndStock ? (parseNumber(cell(row, 'stock')) ?? 0) : 0,
        ));
        added++;
      } catch (e) {
        failures.add('সারি ${toBanglaDigits('$lineNo')}: সংরক্ষণ করা যায়নি');
      }
    }
    return ImportResult(added: added, skippedDuplicates: skipped, failures: failures);
  }
}
