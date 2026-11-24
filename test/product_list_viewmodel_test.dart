import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/presentation/product_list/product_list_viewmodel.dart';
import 'package:hardware_shop/presentation/product_form/product_form_viewmodel.dart';
import 'package:hardware_shop/presentation/locations/locations_viewmodel.dart';

import 'fakes.dart';

void main() {
  late FakeProductRepository products;
  late FakeStockRepository stock;
  late ProductListViewModel vm;

  setUp(() {
    products = FakeProductRepository([
      const Product(
        id: 1,
        name: 'পেরেক',
        categoryId: 1,
        purchasePrice: 80,
        sellingPrice: 100,
        stock: 10,
        unit: 'কেজি',
        placements: [StockPlacement(locationId: 5, quantity: 10)],
      ),
      const Product(id: 2, name: 'তার', categoryId: 2, purchasePrice: 50, sellingPrice: 70, stock: 4, unit: 'মিটার'),
    ]);
    stock = FakeStockRepository();
    vm = ProductListViewModel(products, FakeCategoryRepository(), FakeLocationRepository(), stock);
  });

  test('loads products, categories and locations', () async {
    await vm.load();
    expect(vm.products, hasLength(2));
    expect(vm.categoryName(1), 'পাইপ');
    expect(vm.locationName(5), 'তাক ১');
    expect(vm.totalStockValue, 80 * 10 + 50 * 4);
  });

  test('filters by location: only products with stock placed there', () async {
    await vm.setLocationFilter(5);
    expect(vm.products.map((p) => p.name), ['পেরেক']);
  });

  test('updateStock persists and reloads', () async {
    await vm.load();
    await vm.updateStock(vm.products.first, 25);
    expect(vm.products.first.stock, 25);
  });

  test('updateStock below the placed quantity is rejected, and nothing changes', () async {
    await vm.load();
    final nails = vm.products.firstWhere((p) => p.name == 'পেরেক');
    await expectLater(
      vm.updateStock(nails, 4),
      throwsA(isA<StockException>().having((e) => e.problem, 'problem', StockProblem.belowPlaced)),
    );
    expect(products.items.firstWhere((p) => p.id == 1).stock, 10);
  });

  test('recount delegates to the stock repository and reloads', () async {
    await vm.load();
    await vm.recount(vm.products.first, 5, 7);
    expect(stock.calls, ['recount 1 5 7.0']);
  });

  test('recount surfaces stock rule violations to the caller', () async {
    await vm.load();
    stock.failWith = const StockException(StockProblem.invalidQuantity);
    await expectLater(vm.recount(vm.products.first, 5, -1), throwsA(isA<StockException>()));
  });

  group('ProductFormViewModel', () {
    late ProductFormViewModel form;
    setUp(() => form = ProductFormViewModel(products, FakeCategoryRepository(), FakeLocationRepository(), stock));

    Product p({int? id, String name = 'পেরেক', String brand = '', String size = ''}) =>
        Product(id: id, name: name, brand: brand, size: size, purchasePrice: 1, sellingPrice: 2, stock: 1, unit: 'কেজি');

    test('same name, brand and size is a duplicate', () async {
      expect(await form.isDuplicate(p()), isTrue);
    });

    test('a different size is not a duplicate', () async {
      expect(await form.isDuplicate(p(size: '২ ইঞ্চি')), isFalse);
    });

    test('editing a product does not collide with itself', () async {
      expect(await form.isDuplicate(p(id: 1)), isFalse);
    });

    test('reload returns the latest saved product with its placements, or null', () async {
      expect((await form.reload(1))!.quantityAt(5), 10);
      expect(await form.reload(404), isNull);
    });

    test('place, recount and move are passed through to the stock repository', () async {
      await form.place(1, 5, 3);
      await form.recount(1, 5, 9);
      await form.move(1, 5, 6, 2);
      expect(stock.calls, ['place 1 5 3.0', 'recount 1 5 9.0', 'move 1 5 6 2.0']);
    });

    test('history comes from the stock repository', () async {
      final log = await form.history(1);
      expect(log.single.reason, StockReason.initial);
    });
  });

  group('LocationsViewModel', () {
    test('loads locations with how many products are stocked at each', () async {
      final locations = FakeLocationRepository(counts: {5: 3});
      final lvm = LocationsViewModel(locations);
      await lvm.load();
      expect(lvm.stockedProducts(lvm.items.single), 3);
    });

    test('deleting an empty location succeeds (returns 0)', () async {
      final locations = FakeLocationRepository();
      final lvm = LocationsViewModel(locations);
      await lvm.load();
      expect(await lvm.delete(lvm.items.single), 0);
      expect(locations.deleted, [5]);
    });

    test('deleting a location that holds stock is refused and reports how many products', () async {
      final locations = FakeLocationRepository(counts: {5: 2});
      final lvm = LocationsViewModel(locations);
      await lvm.load();
      expect(await lvm.delete(lvm.items.single), 2);
      expect(locations.deleted, isEmpty);
    });
  });
}
