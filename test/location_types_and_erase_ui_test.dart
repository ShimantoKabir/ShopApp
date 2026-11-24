import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/entities.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/auth_pages.dart';
import 'package:hardware_shop/presentation/auth_viewmodels.dart';
import 'package:hardware_shop/presentation/erase_dialog.dart';
import 'package:hardware_shop/presentation/location_types_page.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/settings_page.dart';
import 'package:hardware_shop/presentation/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

class _Memory implements SettingsStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Locations extends FakeLocationRepository {
  final List<StorageLocation> items;
  final List<String> calls = [];
  _Locations(this.items);

  @override
  Future<List<StorageLocation>> all() async => List.of(items);
  @override
  Future<int> renameType(LocationType type, String newName) async {
    calls.add('rename ${type.name} -> $newName');
    for (var i = 0; i < items.length; i++) {
      if (items[i].type == type) {
        items[i] = StorageLocation(id: items[i].id, name: items[i].name, type: LocationType.custom(newName), code: items[i].code);
      }
    }
    return 1;
  }

  @override
  Future<int> deleteType(LocationType type) async {
    calls.add('delete ${type.name}');
    for (var i = 0; i < items.length; i++) {
      if (items[i].type == type) items[i] = StorageLocation(id: items[i].id, name: items[i].name, code: items[i].code);
    }
    return 1;
  }
}

class _Eraser implements DataEraser {
  final _controller = StreamController<void>.broadcast();
  int erasures = 0;
  Object? failWith;
  @override
  Stream<void> get erased => _controller.stream;
  @override
  Future<void> eraseEverything() async {
    if (failWith != null) throw failWith!;
    erasures++;
    _controller.add(null);
  }
}

class _Users implements UserRepository {
  bool has = true;
  @override
  Future<bool> hasUsers() async => has;
  @override
  Future<List<AppUser>> all() async => has ? const [AppUser(id: 1, name: 'মালিক', role: UserRole.owner)] : const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Screens implements ScreenFactory {
  @override
  Widget shell({required VoidCallback onSignOut}) => const Scaffold(body: Text('SHELL'));
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('location types page', () {
    late _Locations repo;

    Future<void> open(WidgetTester tester, List<StorageLocation> items) async {
      bigScreen(tester);
      repo = _Locations(items);
      await tester.pumpWidget(MaterialApp(home: LocationTypesPage(viewModel: LocationTypesViewModel(repo))));
      await tester.pumpAndSettle();
    }

    StorageLocation loc(int id, LocationType type) => StorageLocation(id: id, name: 'স্থান $id', type: type, code: 'C$id');

    testWidgets('lists only the types the shop made up, with how many locations use each', (tester) async {
      await open(tester, [
        loc(1, LocationType.custom('আলমারি')),
        loc(2, LocationType.custom('আলমারি')),
        loc(3, LocationType.shelf),
        loc(4, LocationType.custom('র‍্যাক')),
      ]);
      expect(find.text('আলমারি'), findsOneWidget);
      expect(find.text('র‍্যাক'), findsOneWidget);
      expect(find.text('তাক'), findsNothing);
      expect(find.text(Bn.locationTypeUsage(2)), findsOneWidget);
    });

    testWidgets('says so when there are none', (tester) async {
      await open(tester, [loc(1, LocationType.shelf)]);
      expect(find.text(Bn.locationTypesEmpty), findsOneWidget);
    });

    testWidgets('the pencil renames it (pre-filled), and the list follows', (tester) async {
      await open(tester, [loc(1, LocationType.custom('আলমারি'))]);
      await tester.tap(find.byTooltip(Bn.edit));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'আলমারি'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'র‍্যাক');
      await tester.tap(find.text(Bn.save));
      await tester.pumpAndSettle();
      expect(repo.calls, ['rename আলমারি -> র‍্যাক']);
      expect(find.text('র‍্যাক'), findsOneWidget);
    });

    testWidgets('delete asks first; then the type is gone from the list', (tester) async {
      await open(tester, [loc(1, LocationType.custom('আলমারি'))]);
      await tester.tap(find.byTooltip(Bn.delete));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty, reason: 'not yet: it asked');
      await tester.tap(find.text(Bn.delete).last);
      await tester.pumpAndSettle();
      expect(repo.calls, ['delete আলমারি']);
      expect(find.text(Bn.locationTypesEmpty), findsOneWidget);
    });
  });

  group('erase dialog', () {
    Future<void> ask(WidgetTester tester, {bool shared = false, void Function(bool?)? onAnswer}) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final answer = await askConfirmErase(context, shared: shared);
                onAnswer?.call(answer);
              },
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    Finder button() => find.widgetWithText(FilledButton, Bn.eraseConfirm);

    testWidgets('warns, and the button stays off until the box is ticked AND the word is typed', (tester) async {
      await ask(tester);
      expect(find.text(Bn.eraseWarning), findsOneWidget);
      expect(find.text(Bn.eraseSharedWarning), findsNothing, reason: 'not shared');
      expect(tester.widget<FilledButton>(button()).onPressed, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(button()).onPressed, isNull, reason: 'ticked only');
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pump();
      expect(tester.widget<FilledButton>(button()).onPressed, isNull, reason: 'wrong word');
      await tester.enterText(find.byType(TextField), 'erase');
      await tester.pump();
      expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);
    });

    testWidgets('the word alone is not enough either', (tester) async {
      await ask(tester);
      await tester.enterText(find.byType(TextField), Bn.eraseWord);
      await tester.pump();
      expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    });

    testWidgets('a shared shop gets the extra warning about the live database', (tester) async {
      await ask(tester, shared: true);
      expect(find.text(Bn.eraseSharedWarning), findsOneWidget);
    });

    testWidgets('cancel says no, confirming says yes', (tester) async {
      bool? answer;
      await ask(tester, onAnswer: (a) => answer = a);
      await tester.tap(find.text(Bn.cancel));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.enterText(find.byType(TextField), Bn.eraseWord);
      await tester.pump();
      await tester.tap(button());
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });
  });

  group('erasing from settings', () {
    Future<void> openSettings(WidgetTester tester, {DataEraser? eraser, bool shared = false}) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: SettingsPage(theme: ThemeViewModel(_Memory()), eraser: eraser, isShared: () => shared),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.text(Bn.eraseButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.enterText(find.byType(TextField), Bn.eraseWord);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, Bn.eraseConfirm));
      await tester.pumpAndSettle();
    }

    testWidgets('no erase section without an eraser (anyone but the owner)', (tester) async {
      await openSettings(tester);
      expect(find.text(Bn.eraseSection), findsNothing);
    });

    testWidgets('the owner confirms and the data is erased; backing out erases nothing', (tester) async {
      final eraser = _Eraser();
      await openSettings(tester, eraser: eraser);
      await tester.tap(find.text(Bn.eraseButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(Bn.cancel));
      await tester.pumpAndSettle();
      expect(eraser.erasures, 0);
      await confirm(tester);
      expect(eraser.erasures, 1);
      expect(find.text(Bn.eraseDone), findsOneWidget);
    });

    testWidgets('no connection: the reason is shown and nothing is reported as erased', (tester) async {
      final eraser = _Eraser()..failWith = const SyncException(SyncProblem.offline);
      await openSettings(tester, eraser: eraser, shared: true);
      await confirm(tester);
      expect(find.text(Bn.syncOffline), findsOneWidget);
      expect(find.text(Bn.eraseDone), findsNothing);
    });
  });

  group('after an erase the app starts again', () {
    testWidgets('signed out, pages on top closed, and the first-run screen shows', (tester) async {
      bigScreen(tester);
      final users = _Users();
      final eraser = _Eraser();
      final session = Session()..signIn(const AppUser(id: 1, name: 'মালিক', role: UserRole.owner));
      final vm = AuthViewModel(users, session, null, eraser);
      await tester.pumpWidget(MaterialApp(home: AuthGate(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      expect(find.text('SHELL'), findsOneWidget);

      Navigator.of(tester.element(find.text('SHELL'))).push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('ON-TOP'))));
      await tester.pumpAndSettle();
      expect(find.text('ON-TOP'), findsOneWidget);

      users.has = false;
      await eraser.eraseEverything();
      await tester.pumpAndSettle();
      expect(find.text('ON-TOP'), findsNothing);
      expect(find.text('SHELL'), findsNothing);
      expect(session.user, isNull);
      expect(vm.hasUsers, isFalse);
    });
  });
}
