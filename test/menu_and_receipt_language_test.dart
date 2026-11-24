import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/core/language.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/home_shell/home_shell.dart';
import 'package:hardware_shop/presentation/receipt/receipt_page.dart';
import 'package:hardware_shop/presentation/receipt/receipt_text.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:material_ui/material_ui.dart';

class _Screens implements ScreenFactory {
  @override
  Widget locations() => const Scaffold(body: Text('LOCATIONS-PAGE'));
  @override
  Widget categories() => const Scaffold(body: Text('CATEGORIES-PAGE'));
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  tearDown(() => Language.current = AppLanguage.bangla);

  final at = DateTime(2026, 11, 22, 15, 35);
  final bill = Bill(
    id: 12,
    customerName: 'রহিম',
    customerMobile: '01712345678',
    customerAddress: 'কাজিপুর',
    customerWhatsApp: '01812345678',
    paid: 100,
    at: at,
    lines: [Sale(productName: 'পেরেক', unit: 'কেজি', quantity: 2, unitPrice: 110, unitCost: 0, at: at)],
  );

  group('receipts stay in Bangla', () {
    test('the text sent to the customer is the same whatever language the app is in', () {
      final inBangla = buildReceiptText(bill, shopName: 'আমার দোকান');
      Language.current = AppLanguage.english;
      expect(buildReceiptText(bill, shopName: 'আমার দোকান'), inBangla);
      expect(inBangla, contains('২ কেজি × ৳১১০ = ৳২২০'));
      expect(Language.current, AppLanguage.english, reason: 'the app language is not changed by it');
    });

    testWidgets('the receipt card on screen is Bangla too', (tester) async {
      Language.current = AppLanguage.english;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceiptCard(bill: bill, shopName: 'আমার দোকান')))));
      expect(find.textContaining('২ কেজি'), findsWidgets);
      expect(find.textContaining('kg'), findsNothing);
    });
  });

  group('inventory and the menu', () {
    Future<void> openMenu(WidgetTester tester, UserRole role) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(AppUser(id: 1, name: 'ব্যবহারকারী', role: role));
      await tester.pumpWidget(MaterialApp(home: HomeShell(screens: _Screens(), currentUser: session, onSignOut: () {})));
      await tester.pumpAndSettle();
    }

    Future<void> menu(WidgetTester tester) async {
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
    }

    for (final role in UserRole.values) {
      testWidgets('shelves and categories are in the menu for ${role.name}, and open', (tester) async {
        await openMenu(tester, role);
        await menu(tester);
        expect(find.text(Bn.locations), findsOneWidget);
        expect(find.text(Bn.categories), findsOneWidget);
        await tester.tap(find.text(Bn.locations));
        await tester.pumpAndSettle();
        expect(find.text('LOCATIONS-PAGE'), findsOneWidget);
        Navigator.of(tester.element(find.text('LOCATIONS-PAGE'))).pop();
        await tester.pumpAndSettle();
        await menu(tester);
        await tester.tap(find.text(Bn.categories));
        await tester.pumpAndSettle();
        expect(find.text('CATEGORIES-PAGE'), findsOneWidget);
      });
    }
  });
}
