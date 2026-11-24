import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/app_errors.dart';
import 'package:hardware_shop/presentation/auth/auth_pages.dart';
import 'package:hardware_shop/presentation/auth/auth_viewmodel.dart';
import 'package:hardware_shop/presentation/home_shell/home_shell.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/settings/settings_page.dart';
import 'package:hardware_shop/presentation/settings/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/sync/sync_pages.dart';
import 'package:hardware_shop/presentation/sync/sync_viewmodel.dart';
import 'package:hardware_shop/presentation/sell/sell_viewmodel.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

/// A sharing service that does what it is told and remembers what it was asked.
class _FakeSync implements SyncService {
  final calls = <String>[];
  final _changes = StreamController<void>.broadcast();

  @override
  SyncState state = SyncState.off;
  @override
  String? detail;
  @override
  DateTime? lastSynced;
  @override
  bool enabled = false;
  @override
  String get defaultUrl => 'https://shop.example';
  @override
  Stream<void> get changes => _changes.stream;

  SyncException? connectFails;
  SyncException? shareFails;
  SyncException? joinFails;

  void change({SyncState? state, bool? enabled}) {
    this.state = state ?? this.state;
    this.enabled = enabled ?? this.enabled;
    _changes.add(null);
  }

  @override
  Future<void> connect({required String url, required String key}) async {
    calls.add('connect $url $key');
    if (connectFails != null) throw connectFails!;
    enabled = true;
    state = SyncState.idle;
  }

  @override
  Future<void> shareThisPhone() async {
    calls.add('share');
    if (shareFails != null) throw shareFails!;
    lastSynced = DateTime(2026, 11, 22, 10, 30);
    _changes.add(null);
  }

  @override
  Future<void> join() async {
    calls.add('join');
    if (joinFails != null) throw joinFails!;
  }

  @override
  Future<void> syncNow() async {
    calls.add('syncNow');
    lastSynced = DateTime(2026, 11, 22, 11, 0);
    _changes.add(null);
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    enabled = false;
    state = SyncState.off;
  }
}

class _Screens implements ScreenFactory {
  final _FakeSync sync;
  _Screens(this.sync);

  @override
  Widget joinShop() => JoinShopPage(viewModel: SyncViewModel(sync));

  @override
  Widget syncSettings() => SyncSettingsPage(viewModel: SyncViewModel(sync));

  @override
  Widget shell({required VoidCallback onSignOut}) => const Scaffold(body: Center(child: Text('APP-SHELL')));

  @override
  Widget activity() => const Scaffold(body: Center(child: Text('ACTIVITY-PAGE')));

  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

/// Counts how often the sign in screen asked who exists.
class _Users implements UserRepository {
  int checks = 0;
  bool anyone = false;

  @override
  Future<bool> hasUsers() async {
    checks++;
    return anyone;
  }

  @override
  Future<List<AppUser>> all() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _offline = SyncException(SyncProblem.offline);

void main() {
  late _FakeSync sync;

  setUp(() => sync = _FakeSync());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> open(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  group('sync database inside the settings page', () {
    testWidgets('the owner can share the shop without leaving settings', (tester) async {
      await open(tester, SettingsPage(theme: ThemeViewModel(_NoSettings()), syncPanel: () => SyncPanel(viewModel: SyncViewModel(sync))));
      expect(find.text(Bn.syncIntro), findsOneWidget);
      expect(find.text(Bn.syncShareButton), findsOneWidget);
      expect(find.text(Bn.themeSection), findsOneWidget, reason: 'the rest of settings is on the same page');
    });

    testWidgets('it is called "Sync database"', (tester) async {
      expect(Bn.navSync, 'সিঙ্ক ডাটাবেস');
      expect(Bn.syncTitle, 'সিঙ্ক ডাটাবেস');
    });
  });

  group('sharing screen (owner)', () {
    testWidgets('before sharing: explains, has the address filled in, and asks for the key', (tester) async {
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      expect(find.text(Bn.syncIntro), findsOneWidget);
      expect(tester.widget<TextFormField>(field(Bn.syncUrlLabel)).controller!.text, 'https://shop.example');
      expect(tester.widget<EditableText>(find.descendant(of: field(Bn.syncKeyLabel), matching: find.byType(EditableText))).obscureText, isTrue,
          reason: 'the key is a secret');
      expect(find.text(Bn.syncShareWarning), findsOneWidget);
    });

    testWidgets('sharing connects with what was typed, then uploads, and the screen then shows the shop as shared', (tester) async {
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      await tester.enterText(field(Bn.syncKeyLabel), 'abc123');
      await tester.tap(find.text(Bn.syncShareButton));
      await tester.pumpAndSettle();

      expect(sync.calls, ['connect https://shop.example abc123', 'share']);
      expect(find.text(Bn.syncShared), findsOneWidget);
      expect(find.text(Bn.syncConnected), findsOneWidget);
      expect(find.text(Bn.syncStateIdle), findsOneWidget);
      expect(find.text(Bn.syncShareButton), findsNothing, reason: 'it cannot be shared twice');
      expect(find.text(Bn.syncLastTime(formatDateTime(DateTime(2026, 11, 22, 10, 30)))), findsOneWidget);
    });

    testWidgets('a wrong key or no signal is explained, and nothing stays connected', (tester) async {
      sync.connectFails = const SyncException(SyncProblem.unauthorized);
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      await tester.enterText(field(Bn.syncKeyLabel), 'wrong');
      await tester.tap(find.text(Bn.syncShareButton));
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncUnauthorized), findsOneWidget);
      expect(sync.enabled, isFalse);
      expect(sync.calls, ['connect https://shop.example wrong']);
    });

    testWidgets('if the upload is refused, the phone is put back on its own', (tester) async {
      sync.shareFails = const SyncException(SyncProblem.alreadyShared);
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      await tester.enterText(field(Bn.syncKeyLabel), 'k');
      await tester.tap(find.text(Bn.syncShareButton));
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncAlreadyShared), findsOneWidget);
      expect(sync.calls, ['connect https://shop.example k', 'share', 'disconnect']);
      expect(sync.enabled, isFalse);
      expect(find.text(Bn.syncShareButton), findsOneWidget, reason: 'it can be tried again');
    });

    testWidgets('once shared it shows how it is going and can sync on demand', (tester) async {
      sync
        ..enabled = true
        ..state = SyncState.offline
        ..lastSynced = DateTime(2026, 11, 21, 9, 5);
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      expect(find.text(Bn.syncStateOffline), findsOneWidget);
      expect(find.text(Bn.syncLastTime(formatDateTime(DateTime(2026, 11, 21, 9, 5)))), findsOneWidget);
      expect(find.text(Bn.syncNeedsInternet), findsOneWidget);

      await tester.tap(find.text(Bn.syncNow));
      await tester.pumpAndSettle();
      expect(sync.calls, ['syncNow']);
      expect(find.text(Bn.syncLastTime(formatDateTime(DateTime(2026, 11, 22, 11, 0)))), findsOneWidget);
    });

    testWidgets('it follows the connection as it changes', (tester) async {
      sync
        ..enabled = true
        ..state = SyncState.idle;
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      expect(find.text(Bn.syncStateIdle), findsOneWidget);
      sync.change(state: SyncState.rejected);
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncStateRejected), findsOneWidget);
      sync.change(state: SyncState.needsUpdate);
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncStateNeedsUpdate), findsOneWidget);
    });
  });

  group('sharing screen (staff)', () {
    testWidgets('on a connected phone: the state, when it last synced, and sync now; never the upload form', (tester) async {
      sync
        ..enabled = true
        ..state = SyncState.idle
        ..lastSynced = DateTime(2026, 11, 22, 9, 5);
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync), canShare: false));
      expect(find.text(Bn.syncStateIdle), findsOneWidget);
      expect(find.text(Bn.syncLastTime(formatDateTime(DateTime(2026, 11, 22, 9, 5)))), findsOneWidget);
      expect(find.text(Bn.syncAutomatic), findsOneWidget, reason: 'told that new data arrives by itself');
      expect(find.text(Bn.syncShareButton), findsNothing);
      await tester.tap(find.text(Bn.syncNow));
      await tester.pumpAndSettle();
      expect(sync.calls, ['syncNow']);
    });

    testWidgets('on a phone that is not connected: an explanation, and no way to upload this phone as the shop', (tester) async {
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync), canShare: false));
      expect(find.text(Bn.syncNotConnectedStaff), findsOneWidget);
      expect(find.text(Bn.syncShareButton), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(sync.calls, isEmpty);
    });

    testWidgets('the owner still gets the upload form on a phone that is not connected', (tester) async {
      await open(tester, SyncSettingsPage(viewModel: SyncViewModel(sync)));
      expect(find.text(Bn.syncShareButton), findsOneWidget);
      expect(find.text(Bn.syncNotConnectedStaff), findsNothing);
    });
  });

  group('joining a shop (new phone)', () {
    testWidgets('connects, downloads, and closes when done', (tester) async {
      var closedWith = 'still open';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => closedWith = '${await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => JoinShopPage(viewModel: SyncViewModel(sync))))}',
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(field(Bn.syncKeyLabel), 'abc');
      await tester.tap(find.text(Bn.joinShopButton));
      await tester.pumpAndSettle();

      expect(sync.calls, ['connect https://shop.example abc', 'join']);
      expect(closedWith, 'true');
      expect(find.byType(JoinShopPage), findsNothing);
    });

    testWidgets('a phone that has a shop already, or no shop to join: explained, and nothing stays connected', (tester) async {
      sync.joinFails = const SyncException(SyncProblem.notFresh);
      await open(tester, JoinShopPage(viewModel: SyncViewModel(sync)));
      await tester.enterText(field(Bn.syncKeyLabel), 'k');
      await tester.tap(find.text(Bn.joinShopButton));
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncNotFresh), findsOneWidget);
      expect(sync.calls.last, 'disconnect');
      expect(find.byType(JoinShopPage), findsOneWidget);

      sync.joinFails = const SyncException(SyncProblem.nothingToJoin);
      sync.calls.clear();
      await tester.tap(find.text(Bn.joinShopButton));
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncNothingToJoin), findsOneWidget);
      expect(sync.calls.last, 'disconnect');
    });

    testWidgets('losing the signal part-way keeps the connection, so trying again carries on', (tester) async {
      sync.joinFails = _offline;
      await open(tester, JoinShopPage(viewModel: SyncViewModel(sync)));
      await tester.enterText(field(Bn.syncKeyLabel), 'k');
      await tester.tap(find.text(Bn.joinShopButton));
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncOffline), findsOneWidget);
      expect(sync.calls, ['connect https://shop.example k', 'join'], reason: 'not disconnected');
      expect(find.byType(JoinShopPage), findsOneWidget);
    });

    testWidgets('a new phone offers to join from the first screen, and then asks who you are', (tester) async {
      final users = _Users();
      final vm = AuthViewModel(users, Session());
      final screens = _Screens(sync);
      await tester.pumpWidget(MaterialApp(home: AuthGate(viewModel: vm, screens: screens)));
      await tester.pumpAndSettle();
      expect(find.text(Bn.joinShopLink), findsOneWidget);
      final checksBefore = users.checks;

      await tester.ensureVisible(find.text(Bn.joinShopLink));
      await tester.tap(find.text(Bn.joinShopLink));
      await tester.pumpAndSettle();
      expect(find.byType(JoinShopPage), findsOneWidget);

      users.anyone = true; // the shop arrives
      await tester.enterText(field(Bn.syncKeyLabel), 'abc');
      await tester.tap(find.text(Bn.joinShopButton));
      await tester.pumpAndSettle();
      expect(find.byType(JoinShopPage), findsNothing);
      expect(users.checks, greaterThan(checksBefore), reason: 'the first screen looked again');
      expect(find.text(Bn.setupTitle), findsNothing, reason: 'it now knows the shop, so it asks who you are');
    });
  });

  group('the menu', () {
    const owner = AppUser(id: 1, name: 'মালিক', role: UserRole.owner);
    const staff = AppUser(id: 2, name: 'করিম', role: UserRole.staff);

    Future<void> openMenu(WidgetTester tester, AppUser who) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(who);
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _Screens(sync), currentUser: session, onSignOut: () {}, sync: sync),
      ));
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
    }

    Finder inDrawer(String text) => find.descendant(of: find.byType(NavigationDrawer), matching: find.text(text));

    testWidgets('everyone, staff included, can open the activity log from the menu', (tester) async {
      for (final who in [owner, staff]) {
        await openMenu(tester, who);
        expect(inDrawer(Bn.navActivity), findsOneWidget, reason: who.name);
        await tester.tap(inDrawer(Bn.navActivity));
        await tester.pumpAndSettle();
        expect(find.text('ACTIVITY-PAGE'), findsOneWidget, reason: who.name);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the shared database is in the settings now, not in the menu, for everyone', (tester) async {
      for (final who in [owner, staff]) {
        await openMenu(tester, who);
        expect(inDrawer(Bn.navSync), findsNothing, reason: who.name);
        expect(inDrawer(Bn.navSettings), findsOneWidget, reason: who.name);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the menu says whether this phone is connected to the shop', (tester) async {
      await openMenu(tester, owner);
      expect(inDrawer(Bn.syncStateIdle), findsNothing, reason: 'nothing to say when the shop is not shared');
      expect(inDrawer(Bn.syncStateOff), findsNothing);
    });

    testWidgets('connected: shows the state; with no signal it says so', (tester) async {
      sync
        ..enabled = true
        ..state = SyncState.idle;
      await openMenu(tester, owner);
      expect(inDrawer(Bn.syncStateIdle), findsOneWidget);
    });

    testWidgets('connected but offline', (tester) async {
      sync
        ..enabled = true
        ..state = SyncState.offline;
      await openMenu(tester, owner);
      expect(inDrawer(Bn.syncStateOffline), findsOneWidget);
    });
  });

  group('messages from anywhere', () {
    testWidgets('a rule that was not caught on its own screen still shows as a message', (tester) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: key, home: const Scaffold(body: SizedBox())));
      expect(showRuleError(key, _offline), isTrue);
      await tester.pump();
      expect(find.text(Bn.syncOffline), findsOneWidget);

      expect(showRuleError(key, const SyncException(SyncProblem.delayed)), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(Bn.syncDelayed), findsOneWidget);
    });

    testWidgets('a real fault is NOT hidden', (tester) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: key, home: const Scaffold(body: SizedBox())));
      expect(showRuleError(key, StateError('a bug')), isFalse);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('a sale that is recorded but not seen back yet', () {
    late FakeProductRepository products;
    late FakeSalesRepository sales;
    late SellViewModel vm;

    setUp(() async {
      final clock = FakeClock(DateTime(2026, 11, 22, 10));
      products = FakeProductRepository([
        const Product(id: 1, name: 'পেরেক', purchasePrice: 80, sellingPrice: 100, stock: 10, unit: 'কেজি'),
      ]);
      sales = FakeSalesRepository(products, clock);
      vm = SellViewModel(products, sales, FakeLocationRepository(), FakeCustomerRepository());
      await vm.load();
      vm.addToCart(vm.products.first, quantity: 2);
    });

    const customer = CustomerInfo(whatsapp: '01911111111');

    test('delayed: the cart is emptied (selling again would sell twice) and the problem is passed on', () async {
      sales.failWith = const SyncException(SyncProblem.delayed);
      await expectLater(
        vm.checkout(customer: customer),
        throwsA(isA<SyncException>().having((e) => e.problem, 'problem', SyncProblem.delayed)),
      );
      expect(vm.cartCount, 0);
    });

    test('no signal: the sale did not happen, so the cart is kept to try again', () async {
      sales.failWith = _offline;
      await expectLater(vm.checkout(customer: customer), throwsA(isA<SyncException>()));
      expect(vm.cartCount, 1);
    });
  });
}

class _NoSettings implements SettingsStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}
