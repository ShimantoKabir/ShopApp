import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/stock.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/widgets/product_tile.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('generic components', () {
    testWidgets('DeltaIndicator shows gain with Bangla digits', (tester) async {
      await tester.pumpWidget(host(const DeltaIndicator(baseText: '80', valueText: '১০০', gainLabel: 'লাভ', lossLabel: 'ক্ষতি')));
      expect(find.textContaining('লাভ'), findsOneWidget);
      expect(find.textContaining('২০'), findsOneWidget);
    });

    testWidgets('DeltaIndicator shows loss', (tester) async {
      await tester.pumpWidget(host(const DeltaIndicator(baseText: '100', valueText: '90', gainLabel: 'লাভ', lossLabel: 'ক্ষতি')));
      expect(find.textContaining('ক্ষতি'), findsOneWidget);
    });

    testWidgets('ChoiceChipBar with "all" clears selection', (tester) async {
      int? picked = 1;
      await tester.pumpWidget(host(ChoiceChipBar<int>(
        options: const [ChipOption(1, 'এক'), ChipOption(2, 'দুই')],
        selected: 1,
        allLabel: 'সব',
        onSelected: (v) => picked = v,
      )));
      await tester.tap(find.text('সব'));
      expect(picked, isNull);
      await tester.tap(find.text('দুই'));
      expect(picked, 2);
    });

    testWidgets('ChoiceChipBar shows nothing when there are no options, even with an "all" chip', (tester) async {
      await tester.pumpWidget(host(ChoiceChipBar<int>(
        options: const [],
        selected: null,
        allLabel: 'সব',
        onSelected: (_) {},
      )));
      expect(find.text('সব'), findsNothing);
    });

    testWidgets('ChoiceChipBar works for any value type', (tester) async {
      String? picked;
      await tester.pumpWidget(host(ChoiceChipBar<String>(
        options: const [ChipOption('a', 'পিস'), ChipOption('b', 'কেজি')],
        selected: 'a',
        scrollable: false,
        onSelected: (v) => picked = v,
      )));
      await tester.tap(find.text('কেজি'));
      expect(picked, 'b');
    });

    testWidgets('AsyncListView shows empty message, then items', (tester) async {
      await tester.pumpWidget(host(AsyncListView<String>(
        items: const [],
        loading: false,
        emptyMessage: 'খালি',
        itemBuilder: (_, s) => Text(s),
      )));
      expect(find.text('খালি'), findsOneWidget);

      await tester.pumpWidget(host(AsyncListView<String>(
        items: const ['ক', 'খ'],
        loading: false,
        emptyMessage: 'খালি',
        itemBuilder: (_, s) => Text(s),
      )));
      expect(find.text('ক'), findsOneWidget);
      expect(find.text('খালি'), findsNothing);
    });

    testWidgets('ItemCard shows title, subtitle, chips and trailing widget, and is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(ItemCard(
        title: 'শিরোনাম',
        subtitle: 'উপশিরোনাম',
        chips: const [InfoChip(label: 'চিপ এক'), InfoChip(label: 'চিপ দুই', icon: Icons.place_outlined)],
        trailing: const Text('৫'),
        onTap: () => tapped = true,
      )));
      expect(find.text('শিরোনাম'), findsOneWidget);
      expect(find.text('উপশিরোনাম'), findsOneWidget);
      expect(find.text('চিপ এক'), findsOneWidget);
      expect(find.text('চিপ দুই'), findsOneWidget);
      expect(find.text('৫'), findsOneWidget);
      await tester.tap(find.text('শিরোনাম'));
      expect(tapped, isTrue);
    });

    testWidgets('ItemCard hides an empty subtitle', (tester) async {
      await tester.pumpWidget(host(const ItemCard(title: 'শিরোনাম', subtitle: '')));
      expect(find.text('শিরোনাম'), findsOneWidget);
    });

    testWidgets('SectionCard shows its title and children', (tester) async {
      await tester.pumpWidget(host(const SectionCard(title: 'বিভাগ', icon: Icons.sell_outlined, children: [Text('ভেতরে')])));
      expect(find.text('বিভাগ'), findsOneWidget);
      expect(find.text('ভেতরে'), findsOneWidget);
    });

    testWidgets('EmptyState shows its message and icon', (tester) async {
      await tester.pumpWidget(host(const EmptyState(message: 'কিছু নেই')));
      expect(find.text('কিছু নেই'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('DropdownWithAction does not crash when its value has no item yet, and selects it once loaded', (tester) async {
      Widget build(List<DropdownMenuItem<int?>> items) => host(DropdownWithAction<int>(
            label: 'স্থান',
            value: 6,
            items: items,
            onChanged: (_) {},
            actionIcon: Icons.add,
            actionTooltip: 'যোগ',
            onAction: () {},
          ));

      // Items still loading: only the "none" entry exists, but the value is 6.
      await tester.pumpWidget(build(const [DropdownMenuItem(value: null, child: Text('স্থান নেই'))]));
      expect(tester.takeException(), isNull);

      // Items arrive.
      await tester.pumpWidget(build(const [
        DropdownMenuItem(value: null, child: Text('স্থান নেই')),
        DropdownMenuItem(value: 6, child: Text('গুদাম')),
      ]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('গুদাম'), findsOneWidget, reason: 'the pending value is selected now');
    });

    testWidgets('ActionButtonRow shows both buttons and fires callbacks', (tester) async {
      var primary = 0, secondary = 0;
      await tester.pumpWidget(host(ActionButtonRow(
        primaryLabel: 'মূল',
        onPrimary: () => primary++,
        secondaryLabel: 'গৌণ',
        onSecondary: () => secondary++,
      )));
      await tester.tap(find.text('মূল'));
      await tester.tap(find.text('গৌণ'));
      expect([primary, secondary], [1, 1]);
    });

    testWidgets('ManageListScaffold lists items and adds', (tester) async {
      final notifier = ValueNotifier(0);
      var added = false;
      await tester.pumpWidget(MaterialApp(
        home: ManageListScaffold<String>(
          title: 'শিরোনাম',
          addLabel: 'যোগ',
          listenable: notifier,
          items: () => const ['ক', 'খ'],
          titleOf: (s) => s,
          onAdd: () => added = true,
          onDelete: (_) {},
        ),
      ));
      expect(find.text('ক'), findsOneWidget);
      await tester.tap(find.text('যোগ'));
      expect(added, isTrue);
    });
  });

  group('ProductTile (composed)', () {
    const nails = Product(
      id: 1,
      name: 'পেরেক',
      purchasePrice: 80,
      sellingPrice: 100,
      stock: 10,
      unit: 'কেজি',
      placements: [StockPlacement(locationId: 1, quantity: 4)],
    );

    Widget tile(Product p, {List<PlacementLabel>? placements, double? stockShown, VoidCallback? onStockTap}) =>
        host(ProductTile(
          product: p,
          categoryName: 'হার্ডওয়্যার',
          placements: placements ?? const [(name: 'তাক ১', quantity: 4)],
          stockShown: stockShown,
          onTap: () {},
          onStockTap: onStockTap ?? () {},
        ));

    testWidgets('shows details, one chip per placement, and reports stock taps', (tester) async {
      var stockTapped = false;
      await tester.pumpWidget(tile(nails, onStockTap: () => stockTapped = true));
      expect(find.text('পেরেক'), findsOneWidget);
      expect(find.text('তাক ১ · ৪'), findsOneWidget);
      await tester.tap(find.byType(TappableValue));
      expect(stockTapped, isTrue);
    });

    testWidgets('flags stock that has not been placed anywhere yet', (tester) async {
      await tester.pumpWidget(tile(nails)); // 10 total, 4 placed -> 6 unplaced
      expect(find.text('স্থান ঠিক হয়নি: ৬'), findsOneWidget);
    });

    testWidgets('no "unplaced" flag when everything is placed, or when there is no stock', (tester) async {
      await tester.pumpWidget(tile(nails.copyWith(placements: const [StockPlacement(locationId: 1, quantity: 10)])));
      expect(find.textContaining('স্থান ঠিক হয়নি'), findsNothing);
      await tester.pumpWidget(tile(nails.copyWith(stock: 0, placements: const [])));
      expect(find.textContaining('স্থান ঠিক হয়নি'), findsNothing);
    });

    testWidgets('the stock pill shows the total by default and the location quantity when given', (tester) async {
      await tester.pumpWidget(tile(nails));
      expect(find.text('১০'), findsOneWidget);
      await tester.pumpWidget(tile(nails, stockShown: 4));
      expect(find.text('৪'), findsOneWidget);
      expect(find.text('১০'), findsNothing);
    });

    testWidgets('a product with no selling price is flagged', (tester) async {
      await tester.pumpWidget(tile(nails.copyWith(sellingPrice: 0)));
      expect(find.text('দাম বাকি'), findsOneWidget);
    });
  });
}
