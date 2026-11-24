import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/presentation/categories_page.dart';
import 'package:hardware_shop/presentation/locations_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

class _Screens implements ScreenFactory {
  @override
  Widget scanner() => Builder(
        builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(onPressed: () => Navigator.pop(context, scanned), child: const Text('SCAN-NOW'))),
        ),
      );
  @override
  Widget productList({StorageLocation? location}) => Scaffold(body: Text('PRODUCTS-OF-${location?.name}'));
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

String scanned = 'X';

void main() {
  Future<FakeLocationRepository> open(WidgetTester tester, {Map<int, int> counts = const {}}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeLocationRepository(counts: counts);
    final vm = LocationsViewModel(repo);
    await vm.load();
    await tester.pumpWidget(MaterialApp(home: LocationsPage(viewModel: vm, screens: _Screens())));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('the scan icon opens the scanner; a shelf code opens that shelf, an unknown one says so', (tester) async {
    await open(tester);
    scanned = 'X';
    await tester.tap(find.byTooltip(Bn.scanQr));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SCAN-NOW'));
    await tester.pumpAndSettle();
    expect(find.text('PRODUCTS-OF-তাক ১'), findsOneWidget);
    Navigator.of(tester.element(find.text('PRODUCTS-OF-তাক ১'))).pop();
    await tester.pumpAndSettle();
    scanned = 'nope';
    await tester.tap(find.byTooltip(Bn.scanQr));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SCAN-NOW'));
    await tester.pumpAndSettle();
    expect(find.text(Bn.unknownQr), findsOneWidget);
  });

  testWidgets('the pencil opens the dialog with the current name, and saving sends the new one', (tester) async {
    final repo = await open(tester);
    await tester.tap(find.byTooltip(Bn.edit));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'তাক ১'), findsOneWidget, reason: 'pre-filled');
    await tester.enterText(find.byType(TextField), 'ডান দিকের তাক');
    await tester.tap(find.text(Bn.save));
    await tester.pumpAndSettle();
    expect(repo.edits.single.$1, 5);
    expect(repo.edits.single.$2, 'ডান দিকের তাক');
  });

  testWidgets('a shelf that holds stock can still be edited, while delete stays locked', (tester) async {
    final repo = await open(tester, counts: {5: 3});
    final edit = tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.edit_outlined), matching: find.byType(IconButton)));
    expect(edit.onPressed, isNotNull);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget, reason: 'delete stays locked');
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.byTooltip(Bn.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'নতুন নাম');
    await tester.tap(find.text(Bn.save));
    await tester.pumpAndSettle();
    expect(repo.edits.single.$2, 'নতুন নাম');
  });

  testWidgets('a new shelf type can be made up in the dialog and is used', (tester) async {
    final repo = await open(tester);
    await tester.tap(find.byTooltip(Bn.edit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Bn.newLocationType));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'আলমারি');
    await tester.tap(find.text(Bn.add));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'আলমারি'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'আলমারি')).selected, isTrue);
    await tester.tap(find.text(Bn.save));
    await tester.pumpAndSettle();
    expect(repo.edits.single.$3, LocationType.custom('আলমারি'));
  });

  group('category rename', () {
    Future<FakeCategoryRepository> openCategories(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FakeCategoryRepository([const Category(id: 1, name: 'পাইপ'), const Category(id: 2, name: 'রং')]);
      await tester.pumpWidget(MaterialApp(home: CategoriesPage(viewModel: CategoriesViewModel(repo))));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('the pencil opens the name pre-filled; saving renames it', (tester) async {
      final repo = await openCategories(tester);
      await tester.tap(find.byTooltip(Bn.edit).first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'পাইপ'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'পিভিসি পাইপ');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(repo.edits.single, (1, 'পিভিসি পাইপ'));
      expect(find.text('পিভিসি পাইপ'), findsOneWidget);
    });
  });
}
