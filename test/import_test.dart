import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/import/csv_parser.dart';
import 'package:hardware_shop/domain/import/csv_source.dart';
import 'package:hardware_shop/domain/import/product_importer.dart';
import 'package:hardware_shop/presentation/import_products/import_viewmodel.dart';

import 'fakes.dart';

/// A few real rows from the Gemini-generated sample file.
const geminiCsv = '''Category,Item Description,Unit,Initial Quantity,Est Unit Cost (BDT),Total Cost (BDT),Typical Gross Margin
Roofing & Structural,Corrugated Iron (CI) Sheets,Ton,1.5,115000,172500,5% - 8%
Roofing & Structural,Wire Nails (Mixed Sizes),kg,50,90,4500,8% - 10%
Water Supply & Irrigation,No. 6 Hand Pump Heads,Piece,15,1200,18000,12% - 15%
Water Supply & Irrigation,uPVC Pipes (Mixed 1-2 inch),Feet,1000,18,18000,15% - 18%
Carpentry & Masonry,Wooden Pegs (Mixed Sizes),Mixed,100,60,6000,20% - 25%
''';

class FakeCsvSource implements CsvSource {
  final String? text;
  FakeCsvSource(this.text);
  @override
  Future<String?> pick() async => text;
}

void main() {
  group('parseCsv', () {
    test('parses plain rows', () {
      expect(parseCsv('a,b,c\n1,2,3\n'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('handles quotes, commas inside quotes, escaped quotes and newlines in fields', () {
      final rows = parseCsv('name,note\n"Nail, 2 inch","say ""hi"""\n"two\nlines",x\n');
      expect(rows[1], ['Nail, 2 inch', 'say "hi"']);
      expect(rows[2], ['two\nlines', 'x']);
    });

    test('handles BOM, Windows line endings and blank lines', () {
      expect(parseCsv('﻿a,b\r\n\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('detects semicolon delimiter', () {
      expect(parseCsv('a;b\n1;2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('keeps Bangla text intact', () {
      expect(parseCsv('নাম,একক\nপেরেক,কেজি')[1], ['পেরেক', 'কেজি']);
    });
  });

  group('ProductImporter', () {
    late FakeProductRepository products;
    late FakeCategoryRepository categories;
    late ProductImporter importer;

    setUp(() {
      products = FakeProductRepository();
      categories = FakeCategoryRepository([]);
      importer = ProductImporter(products, categories);
    });

    test('imports the Gemini file with prices and stock OFF by default', () async {
      final result = await importer.import(geminiCsv);
      expect(result.added, 5);
      expect(result.failures, isEmpty);
      expect(products.items.every((p) => p.purchasePrice == 0 && p.sellingPrice == 0 && p.stock == 0), isTrue);
    });

    test('imports prices and stock only when asked', () async {
      await importer.import(geminiCsv, withPricesAndStock: true);
      final nails = products.items.firstWhere((p) => p.name.startsWith('Wire Nails'));
      expect(nails.purchasePrice, 90);
      expect(nails.stock, 50);
      expect(nails.sellingPrice, 0, reason: 'file has margins, not selling prices; we must not invent one');
    });

    test('maps English units to Bangla and infers loose kind for weight units', () async {
      await importer.import(geminiCsv);
      final byName = {for (final p in products.items) p.name: p};
      expect(byName['Wire Nails (Mixed Sizes)']!.unit, 'কেজি');
      expect(byName['Wire Nails (Mixed Sizes)']!.kind, ProductKind.loose);
      expect(byName['Corrugated Iron (CI) Sheets']!.unit, 'টন');
      expect(byName['No. 6 Hand Pump Heads']!.unit, 'পিস');
      expect(byName['No. 6 Hand Pump Heads']!.kind, ProductKind.standard);
      expect(byName['uPVC Pipes (Mixed 1-2 inch)']!.unit, 'ফুট');
      expect(byName['Wooden Pegs (Mixed Sizes)']!.unit, 'পিস', reason: '"Mixed" falls back to piece');
    });

    test('creates categories once and links products', () async {
      await importer.import(geminiCsv);
      expect(categories.items.map((c) => c.name).toSet(), {
        'Roofing & Structural',
        'Water Supply & Irrigation',
        'Carpentry & Masonry',
      });
      expect(products.items.every((p) => p.categoryId != null), isTrue);
    });

    test('skips duplicates, including when the file is imported twice', () async {
      await importer.import(geminiCsv);
      final second = await importer.import(geminiCsv);
      expect(second.added, 0);
      expect(second.skippedDuplicates, 5);
      expect(products.items, hasLength(5));
    });

    test('understands the app\'s own Bangla column names and extra fields', () async {
      final result = await importer.import(
        'পণ্যের নাম,ক্যাটাগরি,একক,ব্র্যান্ড,সাইজ,মডেল,রং\nওয়েদারকোট,রং,ক্যান,বার্জার,৪ লিটার,W-12,লাল',
      );
      expect(result.added, 1);
      final p = products.items.single;
      expect([p.name, p.unit, p.brand, p.size, p.model, p.finish], ['ওয়েদারকোট', 'ক্যান', 'বার্জার', '৪ লিটার', 'W-12', 'লাল']);
    });

    test('reports rows with no name and keeps going', () async {
      final result = await importer.import('Name,Unit\nHammer,Piece\n,Piece\nSaw,Piece');
      expect(result.added, 2);
      expect(result.failures, hasLength(1));
    });

    test('fails clearly when there is no name column', () async {
      final result = await importer.import('Foo,Bar\n1,2');
      expect(result.fatalError, isNotNull);
      expect(result.added, 0);
    });

    test('fails clearly on an empty file', () async {
      expect((await importer.import('')).fatalError, isNotNull);
      expect((await importer.import('Name\n')).fatalError, isNotNull);
    });
  });

  group('ImportViewModel', () {
    test('picking nothing is a cancel, not an error', () async {
      final vm = ImportViewModel(FakeCsvSource(null), ProductImporter(FakeProductRepository(), FakeCategoryRepository([])));
      await vm.pickAndImport();
      expect(vm.status, ImportStatus.cancelled);
      expect(vm.result, isNull);
    });

    test('runs the import and exposes the result', () async {
      final vm = ImportViewModel(FakeCsvSource(geminiCsv), ProductImporter(FakeProductRepository(), FakeCategoryRepository([])));
      await vm.pickAndImport();
      expect(vm.status, ImportStatus.done);
      expect(vm.result!.added, 5);
    });

    test('prices and stock default to off', () {
      final vm = ImportViewModel(FakeCsvSource(null), ProductImporter(FakeProductRepository(), FakeCategoryRepository([])));
      expect(vm.withPricesAndStock, isFalse);
    });
  });
}
