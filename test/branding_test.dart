import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show CachingAssetBundle, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/core/service_locator.dart';
import 'package:hardware_shop/data/package_info_version_source.dart';
import 'package:hardware_shop/domain/app_info.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/auth/auth_pages.dart';
import 'package:hardware_shop/presentation/auth/auth_viewmodel.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/home_shell/home_shell.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Version implements AppVersionSource {
  final String text;
  _Version(this.text);
  @override
  Future<String> label() async => text;
}

class _Screens implements ScreenFactory {
  @override
  Widget shell({required VoidCallback onSignOut}) => const SizedBox();
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

/// An app with no pictures in it: every asset fails to load.
class _NoAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('no such asset: $key'));
}

void main() {
  group('the logo', () {
    testWidgets('is a real picture that ships with the app', (tester) async {
      final data = await rootBundle.load('assets/branding/logo.png');
      expect(data.lengthInBytes, greaterThan(1000));
      // a PNG file starts with these eight bytes
      expect(data.buffer.asUint8List(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    });

    testWidgets('shows at the size asked for', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: AppLogo(size: 80)))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppLogo)), const Size(80, 80));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('if the picture cannot be loaded a plain shop icon takes its place (nothing breaks)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DefaultAssetBundle(
          bundle: _NoAssets(),
          child: const Scaffold(body: Center(child: AppLogo(size: 64))),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
    });

  });

  group('the app icon', () {
    test('the launcher icons were generated for every screen density', () {
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        final file = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
        expect(file.existsSync(), isTrue, reason: density);
        expect(file.lengthSync(), greaterThan(300), reason: density);
      }
    });

    test('there is an adaptive icon (the shape the phone chooses) with its picture and background', () {
      final adaptive = File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
      expect(adaptive.existsSync(), isTrue);
      final xml = adaptive.readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('foreground'));
      expect(xml, contains('background'));
    });

    test('the app is launched with that icon, and shows the right name', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest, contains('android:label="দোকান খাতা"'));
    });

    test('the web icons were made too', () {
      for (final name in ['Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png']) {
        expect(File('web/icons/$name').existsSync(), isTrue, reason: name);
      }
      expect(File('web/favicon.png').existsSync(), isTrue);
    });

    test('the pictures the icons come from are all there', () {
      for (final name in ['icon.png', 'foreground.png', 'background.png', 'logo.png']) {
        expect(File('assets/branding/$name').existsSync(), isTrue, reason: name);
      }
    });
  });

  group('the version', () {
    test('is read from the installed app: version, then build number', () async {
      PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '1.2.3',
        buildNumber: '45',
        buildSignature: '',
      );
      expect(await PackageInfoVersionSource().label(), '1.2.3 (45)');
    });

    test('with no build number it is just the version', () async {
      PackageInfo.setMockInitialValues(
        appName: 'x',
        packageName: 'x',
        version: '2.0.0',
        buildNumber: '',
        buildSignature: '',
      );
      expect(await PackageInfoVersionSource().label(), '2.0.0');
    });

    test('is written in Bangla digits', () {
      expect(Bn.appVersion('1.2.3 (45)'), 'সংস্করণ ১.২.৩ (৪৫)');
    });

    test('the app can ask for it', () {
      setupServiceLocator();
      addTearDown(sl.reset);
      expect(sl<AppVersionSource>(), isA<PackageInfoVersionSource>());
    });

    Future<void> openMenu(WidgetTester tester, {AppVersionSource? version}) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = Session()..signIn(const AppUser(id: 1, name: 'মালিক', role: UserRole.owner));
      await tester.pumpWidget(MaterialApp(
        home: HomeShell(screens: _Screens(), currentUser: session, onSignOut: () {}, version: version),
      ));
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
    }

    testWidgets('shows at the bottom of the menu, after everything else', (tester) async {
      await openMenu(tester, version: _Version('1.2.3 (45)'));
      final version = find.text('সংস্করণ ১.২.৩ (৪৫)');
      expect(version, findsOneWidget);
      final signOut = find.descendant(of: find.byType(NavigationDrawer), matching: find.text(Bn.navSignOut));
      expect(tester.getTopLeft(version).dy, greaterThan(tester.getBottomLeft(signOut).dy), reason: 'below "sign out"');
    });

    testWidgets('is not shown when it is not known', (tester) async {
      await openMenu(tester);
      expect(find.textContaining('সংস্করণ'), findsNothing);
    });

    testWidgets('the menu header shows the logo', (tester) async {
      await openMenu(tester, version: _Version('1.0.0 (1)'));
      expect(find.descendant(of: find.byType(NavigationDrawer), matching: find.byType(AppLogo)), findsOneWidget);
    });
  });

  group('first screens', () {
    testWidgets('sign-in and set-up show the logo instead of a plain icon', (tester) async {
      final vm = AuthViewModel(FakeUserRepositoryForLogo(), Session());
      await tester.pumpWidget(MaterialApp(home: AuthGate(viewModel: vm, screens: _Screens())));
      await tester.pumpAndSettle();
      expect(find.byType(AppLogo), findsOneWidget, reason: 'set-up (no users yet)');
      expect(find.byIcon(Icons.storefront), findsNothing);
    });
  });
}

/// A shop with nobody in it, so the set-up screen shows.
class FakeUserRepositoryForLogo implements UserRepository {
  @override
  Future<bool> hasUsers() async => false;
  @override
  Future<List<AppUser>> all() async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
