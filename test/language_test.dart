import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/core/language.dart';
import 'package:hardware_shop/data/starter_categories.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/main.dart';
import 'package:hardware_shop/presentation/language_viewmodel.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/settings_page.dart';
import 'package:hardware_shop/presentation/settings_viewmodel.dart';

class _Memory implements SettingsStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Screens implements ScreenFactory {
  final Widget homeWidget;
  _Screens(this.homeWidget);
  @override
  Widget home() => homeWidget;
  @override
  dynamic noSuchMethod(Invocation invocation) => const SizedBox();
}

void main() {
  tearDown(() => Language.current = AppLanguage.bangla);

  group('texts', () {
    test('every text has an English version (none is left as Bangla)', () {
      final source = File('lib/core/bangla.dart').readAsStringSync();
      final bangla = RegExp(r'[ঀ-৿]');
      // English halves of `_t('bn', 'en')` pairs.
      final pairs = RegExp(r"_t\(\s*'((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'\s*\)").allMatches(source);
      expect(pairs.length, greaterThan(300));
      for (final m in pairs) {
        expect(bangla.hasMatch(m.group(2)!), isFalse, reason: 'English text for "${m.group(1)}" contains Bangla');
        expect(m.group(2)!.trim(), isNotEmpty);
      }
    });

    test('the same name reads differently in each language, and the language is put back after runAs', () {
      expect(Bn.products, 'পণ্য');
      Language.current = AppLanguage.english;
      expect(Bn.products, 'Products');
      Language.current = AppLanguage.bangla;
      expect(Language.runAs(AppLanguage.english, () => Bn.products), 'Products');
      expect(Language.current, AppLanguage.bangla);
      expect(() => Language.runAs(AppLanguage.english, () => throw StateError('x')), throwsStateError);
      expect(Language.current, AppLanguage.bangla, reason: 'restored even when the action fails');
    });

    test('digits and units follow the language', () {
      expect(toBanglaDigits('12'), '১২');
      expect(Bn.unitName('কেজি'), 'কেজি');
      Language.current = AppLanguage.english;
      expect(toBanglaDigits('12'), '12');
      expect(Bn.unitName('কেজি'), 'kg');
      expect(Bn.unitName('অজানা'), 'অজানা', reason: 'a unit that is not on the list is shown as typed');
    });

    test('the default category list no longer has the rat trap', () {
      expect(starterCategories, isNot(contains('ইঁদুরের ফাঁদ')));
      expect(starterCategories, isNotEmpty);
    });
  });

  group('LanguageViewModel', () {
    test('starts in Bangla, remembers a choice, and loads it next time', () async {
      final store = _Memory();
      final vm = LanguageViewModel(store);
      await vm.load();
      expect(vm.language, AppLanguage.bangla);
      await vm.choose(AppLanguage.english);
      expect((Language.current, store.values['language']), (AppLanguage.english, 'english'));

      Language.current = AppLanguage.bangla;
      final again = LanguageViewModel(store);
      await again.load();
      expect(again.language, AppLanguage.english);
    });

    test('an unknown saved value falls back to Bangla', () async {
      final vm = LanguageViewModel(_Memory()..values['language'] = 'klingon');
      await vm.load();
      expect(vm.language, AppLanguage.bangla);
    });
  });

  group('screens', () {
    testWidgets('settings switches the language, and the whole screen follows', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final language = LanguageViewModel(_Memory());
      final theme = ThemeViewModel(_Memory());
      await tester.pumpWidget(HardwareShopApp(
        screens: _Screens(SettingsPage(theme: theme, language: language)),
        theme: theme,
        language: language,
      ));
      await tester.pumpAndSettle();
      expect(find.text(Bn.languageSection), findsOneWidget);
      expect(find.text(Bn.languageHelp), findsOneWidget);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(Language.current, AppLanguage.english);
      expect(find.text('Settings'), findsWidgets, reason: 'the title is now English');
      expect(find.textContaining('Receipts sent to customers'), findsOneWidget);

      await tester.tap(find.text('বাংলা'));
      await tester.pumpAndSettle();
      expect(Language.current, AppLanguage.bangla);
      expect(find.textContaining('Receipts sent'), findsNothing);
    });

    testWidgets('a page that is already open, with something typed in it, is switched without losing it', (tester) async {
      final language = LanguageViewModel(_Memory());
      final theme = ThemeViewModel(_Memory());
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(HardwareShopApp(
        screens: _Screens(Builder(
          builder: (context) => Scaffold(
            body: Column(children: [
              Text(Bn.products),
              TextField(controller: controller),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => Scaffold(body: Text(Bn.customersTitle))),
                ),
                child: const Text('open'),
              ),
            ]),
          ),
        )),
        theme: theme,
        language: language,
      ));
      await tester.enterText(find.byType(TextField), 'পেরেক');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text("গ্রাহক"), findsOneWidget);

      await language.choose(AppLanguage.english);
      await tester.pumpAndSettle();
      expect(find.text('Customers'), findsOneWidget, reason: 'the open page on top changed');
      Navigator.of(tester.element(find.text('Customers'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Products'), findsOneWidget, reason: 'the page underneath changed too');
      expect(controller.text, 'পেরেক', reason: 'what was typed is kept');
    });
  });
}
