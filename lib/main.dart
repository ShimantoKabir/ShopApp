import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';

import 'core/bangla.dart';
import 'core/language.dart';
import 'core/service_locator.dart';
import 'data/sync/sync_engine.dart';
import 'domain/settings.dart';
import 'presentation/app_errors.dart';
import 'presentation/language_viewmodel.dart';
import 'presentation/screen_factory.dart';
import 'presentation/settings_viewmodel.dart';
import 'presentation/shop_name_viewmodel.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  final theme = sl<ThemeViewModel>();
  await theme.load(); // so the first frame already has the chosen theme
  final language = sl<LanguageViewModel>();
  await language.load(); // ...and the chosen language

  // If this phone shares the shop, catch up when the app starts and whenever it
  // is opened again. There is no timer asking the server every few seconds:
  // the selling screens catch up at the moments that matter (see SellViewModel).
  final sync = sl<SyncEngine>();
  await sync.load();
  await sl<ShopNameViewModel>().load(); // so the menu already has the shop's name
  AppLifecycleListener(onResume: () => sync.syncNow()); // registers itself with the app
  unawaited(sync.syncNow());

  // A screen that did not catch "no connection" or "not enough stock" itself
  // still shows it as a message instead of failing silently.
  final messenger = GlobalKey<ScaffoldMessengerState>();
  PlatformDispatcher.instance.onError = (error, stack) => showRuleError(messenger, error);

  runApp(HardwareShopApp(screens: sl<ScreenFactory>(), theme: theme, language: language, messengerKey: messenger));
}

class HardwareShopApp extends StatefulWidget {
  final ScreenFactory screens;
  final ThemeViewModel theme;
  final LanguageViewModel? language;
  final GlobalKey<ScaffoldMessengerState>? messengerKey;
  const HardwareShopApp({super.key, required this.screens, required this.theme, this.language, this.messengerKey});

  @override
  State<HardwareShopApp> createState() => _HardwareShopAppState();
}

class _HardwareShopAppState extends State<HardwareShopApp> {
  // Made once: switching theme or language must not start the app over.
  late final Widget _home = widget.screens.home();

  @override
  void initState() {
    super.initState();
    widget.language?.addListener(_languageChanged);
  }

  @override
  void dispose() {
    widget.language?.removeListener(_languageChanged);
    super.dispose();
  }

  /// All the app's text is read when a screen is built, so after a language
  /// change every screen that is open (not just the one on top) must be built
  /// again. Nothing is lost: each one keeps its place and what was typed.
  void _languageChanged() {
    setState(() {});
    (context as Element).visitChildren(_rebuild);
  }

  static void _rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(_rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) => MaterialApp(
        title: Bn.appTitle,
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: widget.messengerKey,
        locale: Locale(Language.current == AppLanguage.english ? 'en' : 'bn'),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: widget.theme.mode,
        home: _home,
      ),
    );
  }
}
