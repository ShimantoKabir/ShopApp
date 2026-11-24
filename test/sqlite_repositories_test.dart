import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_repositories.dart';
import 'package:hardware_shop/data/starter_categories.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/import/product_importer.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Exercises the REAL SQL (via sqflite's FFI build on the host). In-memory
/// fakes can't catch SQL mistakes: an earlier category bug passed every fake
/// test and only failed on a device.

class FixedClock implements Clock {
  int _ms = 1000;
  @override
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(_ms++);
}

class CountingCodes implements LocationCodeGenerator {
  int _n = 0;
  @override
  String generate() => 'CODE-${_n++}';
}

Future<String> dbPath() async => p.join(await getDatabasesPath(), 'repositories_test.db');

Product product(
  String name, {
  String brand = '',
  String size = '',
  String model = '',
  String finish = '',
  ProductKind kind = ProductKind.standard,
  double stock = 3,
  List<StockPlacement> placements = const [],
}) =>
    Product(
      name: name,
      brand: brand,
      size: size,
      model: model,
      finish: finish,
      kind: kind,
      purchasePrice: 10,
      sellingPrice: 15,
      stock: stock,
      unit: 'পিস',
      placements: placements,
    );

Matcher throwsStock(StockProblem problem) =>
    throwsA(isA<StockException>().having((e) => e.problem, 'problem', problem));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDb;
  late SqliteProductRepository products;
  late SqliteStockRepository stock;
  late SqliteCategoryRepository categories;
  late SqliteLocationRepository locations;

  setUp(() async {
    await deleteDatabase(await dbPath());
    appDb = AppDatabase(fileName: 'repositories_test.db');
    final clock = FixedClock();
    products = SqliteProductRepository(appDb, clock);
    stock = SqliteStockRepository(appDb, clock);
    categories = SqliteCategoryRepository(appDb);
    locations = SqliteLocationRepository(appDb, CountingCodes());
  });

  tearDown(() async => (await appDb.db).close());

  group('fresh database', () {
    test('seeds the starter categories (names only, no products)', () async {
      expect((await categories.all()).length, starterCategories.length);
      expect(await products.search(), isEmpty);
    });
  });

  group('categories', () {
    test('adding an existing category returns it instead of failing or duplicating', () async {
      final first = await categories.add('নতুন ক্যাটাগরি');
      final again = await categories.add('নতুন ক্যাটাগরি');
      final differentCase = await categories.add('  নতুন ক্যাটাগরি ');
      expect(again.id, first.id);
      expect(differentCase.id, first.id);
      expect((await categories.all()).where((c) => c.name == 'নতুন ক্যাটাগরি'), hasLength(1));
    });

    test('adding an existing STARTER category returns the starter one', () async {
      final before = (await categories.all()).length;
      final c = await categories.add(starterCategories.first);
      expect(c.id, isNotNull);
      expect((await categories.all()).length, before);
    });
  });

  group('products', () {
    test('saves and reads back every field', () async {
      final saved = await products.save(Product(
        name: 'ওয়েদারকোট',
        kind: ProductKind.standard,
        brand: 'বার্জার',
        size: '৪ লিটার',
        model: 'W-12',
        finish: 'লাল',
        purchasePrice: 3000,
        sellingPrice: 3400,
        stock: 6,
        unit: 'ক্যান',
      ));
      final read = (await products.search()).single;
      expect(read.id, saved.id);
      expect([read.name, read.brand, read.size, read.model, read.finish, read.unit],
          ['ওয়েদারকোট', 'বার্জার', '৪ লিটার', 'W-12', 'লাল', 'ক্যান']);
      expect([read.purchasePrice, read.sellingPrice, read.stock], [3000, 3400, 6]);
    });

    test('search matches name, brand, size, model and finish', () async {
      await products.save(product('পেইন্ট', brand: 'বার্জার', size: '৪ লিটার', model: 'ZX-9', finish: 'লাল'));
      await products.save(product('পেরেক'));
      for (final q in ['পেইন্ট', 'বার্জার', '৪ লিটার', 'ZX-9', 'লাল']) {
        expect((await products.search(query: q)).map((x) => x.name), ['পেইন্ট'], reason: 'query "$q"');
      }
      expect(await products.search(query: 'কিছুনা'), isEmpty);
    });

    test('filters by kind', () async {
      await products.save(product('পেরেক', kind: ProductKind.loose));
      await products.save(product('পাম্প', kind: ProductKind.bulky));
      expect((await products.search(kind: ProductKind.bulky)).map((x) => x.name), ['পাম্প']);
    });

    test('existsSimilar is case-insensitive and can exclude the product being edited', () async {
      final saved = await products.save(product('Hammer', brand: 'Total', size: '1kg'));
      expect(await products.existsSimilar(name: 'hammer', brand: 'TOTAL', size: '1KG'), isTrue);
      expect(await products.existsSimilar(name: 'Hammer', brand: 'Total', size: '2kg'), isFalse);
      expect(await products.existsSimilar(name: 'Hammer', brand: 'Total', size: '1kg', excludeId: saved.id), isFalse);
    });

    test('byId returns the product, or null', () async {
      final saved = await products.save(product('পেরেক'));
      expect((await products.byId(saved.id!))!.name, 'পেরেক');
      expect(await products.byId(99999), isNull);
    });

    test('adjustStock updates only the stock', () async {
      final saved = await products.save(product('পেরেক'));
      await products.adjustStock(saved.id!, 99);
      final read = (await products.search()).single;
      expect(read.stock, 99);
      expect(read.name, 'পেরেক');
    });

    test('deleting a product removes its placements and history too', () async {
      final shelf = await locations.add('তাক ১', LocationType.shelf);
      final saved = await products.save(product('পেরেক', stock: 5, placements: [StockPlacement(locationId: shelf.id!, quantity: 5)]));
      await products.delete(saved.id!);
      expect(await locations.stockedProductCounts(), isEmpty);
      expect(await stock.history(saved.id!), isEmpty);
    });
  });

  group('locations', () {
    test('stores type and generated code, and finds by code', () async {
      final yard = await locations.add('বাইরের উঠান', LocationType.yard);
      expect(yard.code, 'CODE-0');
      final found = await locations.findByCode('CODE-0');
      expect(found!.name, 'বাইরের উঠান');
      expect(found.type, LocationType.yard);
      expect(await locations.findByCode('NOPE'), isNull);
    });

    test('an empty location can be deleted', () async {
      final shelf = await locations.add('তাক ১', LocationType.shelf);
      await locations.delete(shelf.id!);
      expect(await locations.all(), isEmpty);
    });

    test('a location that still holds stock CANNOT be deleted, and nothing is lost', () async {
      final shelf = await locations.add('তাক ১', LocationType.shelf);
      final saved = await products.save(product('পেরেক', stock: 5, placements: [StockPlacement(locationId: shelf.id!, quantity: 5)]));

      await expectLater(
        locations.delete(shelf.id!),
        throwsA(isA<LocationNotEmptyException>().having((e) => e.productCount, 'productCount', 1)),
      );
      expect((await locations.all()), hasLength(1));
      expect((await products.byId(saved.id!))!.quantityAt(shelf.id), 5);
    });

    test('after the stock is moved away, the location can be deleted', () async {
      final a = await locations.add('তাক ১', LocationType.shelf);
      final b = await locations.add('তাক ২', LocationType.shelf);
      final saved = await products.save(product('পেরেক', stock: 5, placements: [StockPlacement(locationId: a.id!, quantity: 5)]));
      await stock.move(saved.id!, a.id!, b.id!, 5);
      await locations.delete(a.id!);
      expect((await locations.all()).map((l) => l.name), ['তাক ২']);
    });

    test('stockedProductCounts counts distinct products with stock per location', () async {
      final a = await locations.add('তাক ১', LocationType.shelf);
      final b = await locations.add('তাক ২', LocationType.shelf);
      await products.save(product('এক', stock: 5, placements: [StockPlacement(locationId: a.id!, quantity: 5)]));
      await products.save(product('দুই', stock: 4, placements: [
        StockPlacement(locationId: a.id!, quantity: 1),
        StockPlacement(locationId: b.id!, quantity: 3),
      ]));
      expect(await locations.stockedProductCounts(), {a.id!: 2, b.id!: 1});
    });
  });

  group('placements (stock spread over locations)', () {
    late StorageLocation shelf1;
    late StorageLocation shelf2;
    late StorageLocation yard;

    setUp(() async {
      shelf1 = await locations.add('তাক ১', LocationType.shelf);
      shelf2 = await locations.add('তাক ২', LocationType.shelf);
      yard = await locations.add('উঠান', LocationType.yard);
    });

    Future<Product> nails({double total = 20, List<StockPlacement> placed = const []}) =>
        products.save(product('পেরেক', kind: ProductKind.loose, stock: total, placements: placed));

    test('a new product can be saved with placements, read back with search and byId', () async {
      final saved = await nails(placed: [
        StockPlacement(locationId: shelf1.id!, quantity: 5),
        StockPlacement(locationId: yard.id!, quantity: 12),
      ]);
      final read = (await products.search()).single;
      expect(read.stock, 20);
      expect(read.quantityAt(shelf1.id), 5);
      expect(read.quantityAt(yard.id), 12);
      expect(read.placedQuantity, 17);
      expect(read.unplacedQuantity, 3, reason: '20 total - 17 placed');
      expect((await products.byId(saved.id!))!.placements, hasLength(2));
    });

    test('a new product cannot place more than it has', () async {
      await expectLater(
        nails(total: 10, placed: [StockPlacement(locationId: shelf1.id!, quantity: 11)]),
        throwsStock(StockProblem.exceedsStock),
      );
      expect(await products.search(), isEmpty, reason: 'nothing half-saved');
    });

    test('searching by location finds only products with stock there', () async {
      await nails(placed: [StockPlacement(locationId: shelf1.id!, quantity: 5)]);
      await products.save(product('তার', stock: 4, placements: [StockPlacement(locationId: shelf2.id!, quantity: 4)]));
      expect((await products.search(locationId: shelf1.id)).map((x) => x.name), ['পেরেক']);
      expect((await products.search(locationId: shelf2.id)).map((x) => x.name), ['তার']);
      expect(await products.search(locationId: yard.id), isEmpty);
    });

    test('place assigns part of the existing stock; it never changes the total', () async {
      final saved = await nails();
      await stock.place(saved.id!, shelf1.id!, 8);
      final read = (await products.byId(saved.id!))!;
      expect(read.stock, 20);
      expect(read.quantityAt(shelf1.id), 8);
      expect(read.unplacedQuantity, 12);
    });

    test('place can raise, lower and remove a placement', () async {
      final saved = await nails();
      await stock.place(saved.id!, shelf1.id!, 8);
      await stock.place(saved.id!, shelf1.id!, 15);
      expect((await products.byId(saved.id!))!.quantityAt(shelf1.id), 15);
      await stock.place(saved.id!, shelf1.id!, 0);
      final read = (await products.byId(saved.id!))!;
      expect(read.placements, isEmpty);
      expect(read.unplacedQuantity, 20);
    });

    test('place cannot exceed the total across all locations', () async {
      final saved = await nails(total: 10, placed: [StockPlacement(locationId: shelf1.id!, quantity: 7)]);
      await expectLater(stock.place(saved.id!, shelf2.id!, 4), throwsStock(StockProblem.exceedsStock));
      await stock.place(saved.id!, shelf2.id!, 3); // exactly fits
      expect((await products.byId(saved.id!))!.unplacedQuantity, 0);
    });

    test('place rejects negative quantities', () async {
      final saved = await nails();
      await expectLater(stock.place(saved.id!, shelf1.id!, -1), throwsStock(StockProblem.invalidQuantity));
    });

    test('move shifts stock between two locations and keeps the total', () async {
      final saved = await nails(placed: [StockPlacement(locationId: shelf1.id!, quantity: 10)]);
      await stock.move(saved.id!, shelf1.id!, shelf2.id!, 4);
      final read = (await products.byId(saved.id!))!;
      expect(read.quantityAt(shelf1.id), 6);
      expect(read.quantityAt(shelf2.id), 4);
      expect(read.stock, 20);
    });

    test('moving everything empties the source row and adds to existing stock at the target', () async {
      final saved = await nails(placed: [
        StockPlacement(locationId: shelf1.id!, quantity: 6),
        StockPlacement(locationId: shelf2.id!, quantity: 2),
      ]);
      await stock.move(saved.id!, shelf1.id!, shelf2.id!, 6);
      final read = (await products.byId(saved.id!))!;
      expect(read.placements.map((p) => p.locationId), [shelf2.id], reason: 'source row is gone');
      expect(read.quantityAt(shelf2.id), 8);
    });

    test('move rejects: more than the source holds, same location, zero quantity', () async {
      final saved = await nails(placed: [StockPlacement(locationId: shelf1.id!, quantity: 5)]);
      await expectLater(stock.move(saved.id!, shelf1.id!, shelf2.id!, 6), throwsStock(StockProblem.notEnoughAtSource));
      await expectLater(stock.move(saved.id!, shelf1.id!, shelf1.id!, 1), throwsStock(StockProblem.sameLocation));
      await expectLater(stock.move(saved.id!, shelf1.id!, shelf2.id!, 0), throwsStock(StockProblem.invalidQuantity));
      expect((await products.byId(saved.id!))!.quantityAt(shelf1.id), 5, reason: 'failed moves change nothing');
    });

    test('recount sets the real quantity at a location and adjusts the total by the difference', () async {
      final saved = await nails(placed: [StockPlacement(locationId: shelf1.id!, quantity: 10)]);
      await stock.recount(saved.id!, shelf1.id!, 7); // found 3 fewer than expected
      var read = (await products.byId(saved.id!))!;
      expect(read.quantityAt(shelf1.id), 7);
      expect(read.stock, 17);
      expect(read.unplacedQuantity, 10, reason: '10 unplaced stays 10');

      await stock.recount(saved.id!, shelf1.id!, 9); // found more
      read = (await products.byId(saved.id!))!;
      expect(read.stock, 19);
    });

    test('recount to a location the product was not at yet adds it', () async {
      final saved = await nails();
      await stock.recount(saved.id!, yard.id!, 5);
      final read = (await products.byId(saved.id!))!;
      expect(read.quantityAt(yard.id), 5);
      expect(read.stock, 25);
    });

    test('total stock cannot be set below what is already placed', () async {
      final saved = await nails(total: 20, placed: [StockPlacement(locationId: shelf1.id!, quantity: 15)]);
      await expectLater(products.adjustStock(saved.id!, 14), throwsStock(StockProblem.belowPlaced));
      await expectLater(products.save(saved.copyWith(stock: 10)), throwsStock(StockProblem.belowPlaced));
      expect((await products.byId(saved.id!))!.stock, 20, reason: 'rejected edits change nothing');
      await products.adjustStock(saved.id!, 15); // exactly the placed amount is fine
      expect((await products.byId(saved.id!))!.stock, 15);
    });

    test('saving an existing product ignores placements in the object (StockRepository owns them)', () async {
      final saved = await nails(placed: [StockPlacement(locationId: shelf1.id!, quantity: 10)]);
      await products.save(saved.copyWith(name: 'নতুন নাম', placements: const []));
      final read = (await products.byId(saved.id!))!;
      expect(read.name, 'নতুন নাম');
      expect(read.quantityAt(shelf1.id), 10);
    });
  });

  group('history log', () {
    late StorageLocation shelf1;
    late StorageLocation shelf2;

    setUp(() async {
      shelf1 = await locations.add('তাক ১', LocationType.shelf);
      shelf2 = await locations.add('তাক ২', LocationType.shelf);
    });

    test('records initial stock, edits, placing, moving and counting - newest first', () async {
      final saved = await products.save(product('পেরেক', stock: 20)); //             initial +20
      await stock.place(saved.id!, shelf1.id!, 10); //                               place   +10 @shelf1
      await stock.move(saved.id!, shelf1.id!, shelf2.id!, 4); //                     move    -4 @1, +4 @2
      await stock.recount(saved.id!, shelf2.id!, 3); //                              count   -1 @2
      await products.adjustStock(saved.id!, 30); //                                  edit    +8 (19 -> 30? see below)

      final log = await stock.history(saved.id!);
      expect(log.map((e) => e.reason), [
        StockReason.edit,
        StockReason.count,
        StockReason.move,
        StockReason.move,
        StockReason.place,
        StockReason.initial,
      ]);
      expect(log.last.delta, 20);
      expect(log.last.locationId, isNull, reason: 'initial stock is not tied to a location');
      final place = log.firstWhere((e) => e.reason == StockReason.place);
      expect([place.locationId, place.delta], [shelf1.id, 10]);
      final moves = log.where((e) => e.reason == StockReason.move).toList();
      expect(moves.map((e) => e.delta).toSet(), {-4.0, 4.0});
      final count = log.firstWhere((e) => e.reason == StockReason.count);
      expect([count.locationId, count.delta], [shelf2.id, -1]);
      final edit = log.first;
      expect(edit.delta, 30 - 19, reason: 'total was 20 - 1 (recount) = 19');
    });

    test('rejected operations leave no log entries', () async {
      final saved = await products.save(product('পেরেক', stock: 5));
      final before = (await stock.history(saved.id!)).length;
      await expectLater(stock.place(saved.id!, shelf1.id!, 99), throwsStock(StockProblem.exceedsStock));
      await expectLater(stock.move(saved.id!, shelf1.id!, shelf2.id!, 1), throwsStock(StockProblem.notEnoughAtSource));
      expect((await stock.history(saved.id!)).length, before);
    });

    test('a zero-change operation is not logged', () async {
      final saved = await products.save(product('পেরেক', stock: 5));
      final before = (await stock.history(saved.id!)).length;
      await products.adjustStock(saved.id!, 5);
      expect((await stock.history(saved.id!)).length, before);
    });

    test('limit is respected', () async {
      final saved = await products.save(product('পেরেক', stock: 1));
      for (var i = 2; i <= 6; i++) {
        await products.adjustStock(saved.id!, i.toDouble());
      }
      expect(await stock.history(saved.id!, limit: 3), hasLength(3));
    });
  });

  group('importer on the real database', () {
    const csv = '''Category,Item Description,Unit,Initial Quantity,Est Unit Cost (BDT)
Roofing & Structural,Corrugated Iron (CI) Sheets,Ton,1.5,115000
Roofing & Structural,Wire Nails (Mixed Sizes),kg,50,90
Water Supply & Irrigation,No. 6 Hand Pump Heads,Piece,15,1200
Water Supply & Irrigation,uPVC Pipes (Mixed 1-2 inch),Feet,1000,18
''';

    test('rows that share a category all import (regression for the on-device failure)', () async {
      final result = await ProductImporter(products, categories).import(csv);
      expect(result.failures, isEmpty);
      expect(result.added, 4);
      expect(await products.search(), hasLength(4));
    });

    test('re-importing skips everything as duplicates', () async {
      final importer = ProductImporter(products, categories);
      await importer.import(csv);
      final again = await importer.import(csv);
      expect(again.added, 0);
      expect(again.skippedDuplicates, 4);
    });
  });

  group('migrations', () {
    Future<void> createV1({required bool withCategory}) async {
      final db = await databaseFactory.openDatabase(
        await dbPath(),
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
            await d.execute('CREATE TABLE shelves(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, code TEXT NOT NULL UNIQUE)');
            await d.execute('''CREATE TABLE products(
              id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
              category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
              shelf_id INTEGER REFERENCES shelves(id) ON DELETE SET NULL,
              purchase_price REAL NOT NULL, selling_price REAL NOT NULL, stock REAL NOT NULL,
              unit TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
            await d.execute('CREATE INDEX idx_products_shelf ON products(shelf_id)');
            if (withCategory) await d.insert('categories', {'name': 'আমার ক্যাটাগরি'});
            await d.insert('shelves', {'name': 'পুরনো তাক', 'code': 'HSHELF-OLD1'});
            await d.insert('products', {
              'name': 'পুরনো পেরেক', 'shelf_id': 1, 'purchase_price': 80.0,
              'selling_price': 100.0, 'stock': 10.0, 'unit': 'কেজি', 'updated_at': 1,
            });
            // Out of stock but assigned to the shelf, and one with no shelf.
            await d.insert('products', {
              'name': 'শেষ হয়ে গেছে', 'shelf_id': 1, 'purchase_price': 5.0,
              'selling_price': 8.0, 'stock': 0.0, 'unit': 'পিস', 'updated_at': 2,
            });
            await d.insert('products', {
              'name': 'তাকহীন', 'purchase_price': 5.0,
              'selling_price': 8.0, 'stock': 7.0, 'unit': 'পিস', 'updated_at': 3,
            });
          },
        ),
      );
      await db.close();
    }

    Future<void> createV3() async {
      final db = await databaseFactory.openDatabase(
        await dbPath(),
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
            await d.execute('''CREATE TABLE locations(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'shelf', code TEXT NOT NULL UNIQUE)''');
            await d.execute('''CREATE TABLE products(
              id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'standard',
              category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
              location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
              brand TEXT NOT NULL DEFAULT '', size TEXT NOT NULL DEFAULT '', model TEXT NOT NULL DEFAULT '',
              finish TEXT NOT NULL DEFAULT '', purchase_price REAL NOT NULL, selling_price REAL NOT NULL,
              stock REAL NOT NULL, unit TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
            await d.insert('locations', {'name': 'বাইরের উঠান', 'type': 'yard', 'code': 'HLOC-V3'});
            await d.insert('products', {
              'name': 'ট্যাংক', 'kind': 'bulky', 'location_id': 1, 'purchase_price': 9800.0,
              'selling_price': 11200.0, 'stock': 3.0, 'unit': 'পিস', 'updated_at': 1,
            });
          },
        ),
      );
      await db.close();
    }

    test('v1 -> latest: keeps data, shelves become locations, one-shelf products become placements', () async {
      await createV1(withCategory: false);
      final all = await products.search();
      final byName = {for (final x in all) x.name: x};

      final nail = byName['পুরনো পেরেক']!;
      expect(nail.purchasePrice, 80);
      expect(nail.kind, ProductKind.standard);
      expect(nail.placements.single.locationId, 1, reason: 'shelf_id became a placement');
      expect(nail.quantityAt(1), 10, reason: 'the whole stock was on that shelf');
      expect(byName['তাকহীন']!.placements, isEmpty);
      expect(byName['শেষ হয়ে গেছে']!.placements, isEmpty, reason: 'no stock, nothing to place');

      final location = (await locations.all()).single;
      expect(location.name, 'পুরনো তাক');
      expect(location.type, LocationType.shelf);
      expect((await locations.findByCode('HSHELF-OLD1'))!.id, 1, reason: 'already-printed QR codes keep working');
      expect((await categories.all()).length, starterCategories.length, reason: 'empty categories get the starter set');
    });

    test('v1 -> latest: a migrated location that holds stock is protected from deletion', () async {
      await createV1(withCategory: false);
      await expectLater(locations.delete(1), throwsA(isA<LocationNotEmptyException>()));
    });

    test('v1 -> latest: does not add starter categories to a database that already has its own', () async {
      await createV1(withCategory: true);
      expect((await categories.all()).map((c) => c.name), ['আমার ক্যাটাগরি']);
    });

    test('v3 -> v4: single-location stock is carried over as a placement', () async {
      await createV3();
      final tank = (await products.search()).single;
      expect(tank.name, 'ট্যাংক');
      expect(tank.kind, ProductKind.bulky);
      expect(tank.stock, 3);
      expect(tank.quantityAt(1), 3);
      expect(await locations.stockedProductCounts(), {1: 1});
    });

    test('a migrated database works for new operations (save, place, move, log)', () async {
      await createV3();
      final yard = (await locations.all()).single;
      final shelf = await locations.add('তাক ১', LocationType.shelf);
      final tank = (await products.search()).single;

      // Saving a NEW product must work even though the legacy location_id column still exists.
      final fresh = await products.save(product('নতুন', model: 'M-1', finish: 'ব্রাস', stock: 4));
      expect((await products.search(query: 'M-1')).single.finish, 'ব্রাস');

      await stock.move(tank.id!, yard.id!, shelf.id!, 1);
      expect((await products.byId(tank.id!))!.quantityAt(shelf.id), 1);
      expect((await stock.history(tank.id!)), isNotEmpty);
      expect((await stock.history(fresh.id!)).single.reason, StockReason.initial);
    });
  });
}
