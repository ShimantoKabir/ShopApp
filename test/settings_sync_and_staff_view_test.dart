import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/users/users_viewmodel.dart';
import 'package:hardware_shop/presentation/settings/settings_page.dart';
import 'package:hardware_shop/presentation/settings/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/users/users_page.dart';
import 'package:material_ui/material_ui.dart';

class _Memory implements SettingsStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Users implements UserRepository {
  @override
  Future<List<AppUser>> all() async => const [
        AppUser(id: 1, name: 'মালিক', role: UserRole.owner),
        AppUser(id: 2, name: 'করিম', role: UserRole.staff),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  testWidgets('settings shows the sync database right on its own page, no other page to open', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var made = 0;
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(theme: ThemeViewModel(_Memory()), syncPanel: () {
        made++;
        return const Text('SYNC-PANEL');
      }),
    ));
    expect(find.text('SYNC-PANEL'), findsOneWidget, reason: 'it is on the settings page itself');
    await tester.tap(find.text(Bn.themeLight));
    await tester.pumpAndSettle();
    expect(made, 1, reason: 'built once, not on every rebuild');
  });

  for (final owner in [true, false]) {
    testWidgets('the staff list: ${owner ? 'the owner can add people' : 'anyone else only sees it'}', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(AppUser(id: owner ? 1 : 2, name: 'x', role: owner ? UserRole.owner : UserRole.staff));
      await tester.pumpWidget(MaterialApp(home: UsersPage(viewModel: UsersViewModel(_Users(), session), canManage: owner)));
      await tester.pumpAndSettle();
      expect(find.text('করিম'), findsOneWidget, reason: 'the list is visible to everyone');
      expect(find.text(Bn.addUser), findsNWidgets(owner ? 1 : 0));
      await tester.tap(find.text('করিম'));
      await tester.pumpAndSettle();
      expect(find.text(Bn.resetPin), findsNWidgets(owner ? 1 : 0), reason: 'only the owner gets the options');
    });
  }
}
