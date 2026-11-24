import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../domain/settings.dart';
import 'components/components.dart';
import '../domain/sync.dart';
import 'erase_dialog.dart';
import 'labels.dart';
import 'language_viewmodel.dart';
import 'settings_viewmodel.dart';
import 'shop_name_viewmodel.dart';

/// Settings. Everyone can choose light, dark or follow the phone (for this phone
/// only). The owner can also rename the shop.
/// [theme] and [shopName] are shared by the whole app, so this page does not
/// dispose them.
class SettingsPage extends StatefulWidget {
  final ThemeViewModel theme;
  final ShopNameViewModel? shopName;
  final LanguageViewModel? language;

  /// Builds the sync database panel, shown right here on this page.
  final Widget Function()? syncPanel;

  /// Only given to the owner: erases all of the shop's data.
  final DataEraser? eraser;

  /// Whether the shop is shared (the warning then mentions the shared database).
  final bool Function()? isShared;

  /// Only owners may rename the shop.
  final bool canEditShop;

  const SettingsPage({super.key, required this.theme, this.shopName, this.language, this.syncPanel, this.eraser, this.isShared, this.canEditShop = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _name = TextEditingController(text: widget.shopName?.hasName == true ? widget.shopName!.name : '');
  bool _saving = false;
  late final Widget? _sync = widget.syncPanel?.call(); // made once: it owns its own state

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveName() async {
    final shop = widget.shopName;
    if (shop == null || _saving) return;
    setState(() => _saving = true);
    try {
      await shop.rename(_name.text);
      _name.text = shop.name;
      _say(Bn.shopNameSaved);
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      _say(message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      appBar: AppBar(title: Text(Bn.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canEditShop && widget.shopName != null) ...[
            SectionCard(
              title: Bn.shopNameSection,
              icon: Icons.storefront_outlined,
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: Bn.shopNameLabel, hintText: Bn.appTitle),
                  onFieldSubmitted: (_) => _saveName(),
                ),
                const SizedBox(height: 8),
                Text(
                  Bn.shopNameHelp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ActionButtonRow(primaryLabel: Bn.save, onPrimary: _saveName, busy: _saving),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_sync != null) ...[
            _sync,
            const SizedBox(height: 12),
          ],
          if (widget.language != null) ...[
            SectionCard(
              title: Bn.languageSection,
              icon: Icons.language,
              children: [
                ListenableBuilder(
                  listenable: widget.language!,
                  builder: (context, _) => SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AppLanguage>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: AppLanguage.bangla, label: Text(Bn.languageBangla)),
                        ButtonSegment(value: AppLanguage.english, label: Text(Bn.languageEnglish)),
                      ],
                      selected: {widget.language!.language},
                      onSelectionChanged: (s) => widget.language!.choose(s.first),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Bn.languageHelp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: Bn.themeSection,
            icon: Icons.brightness_6_outlined,
            children: [
              ListenableBuilder(
                listenable: theme,
                builder: (context, _) => SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemePreference>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: ThemePreference.system, icon: Icon(Icons.phone_android), label: Text(Bn.themeSystem)),
                      ButtonSegment(value: ThemePreference.light, icon: Icon(Icons.light_mode_outlined), label: Text(Bn.themeLight)),
                      ButtonSegment(value: ThemePreference.dark, icon: Icon(Icons.dark_mode_outlined), label: Text(Bn.themeDark)),
                    ],
                    selected: {theme.preference},
                    onSelectionChanged: (s) => theme.choose(s.first),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Bn.themeHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (widget.eraser != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: Bn.eraseSection,
              icon: Icons.delete_forever_outlined,
              children: [
                Text(
                  Bn.eraseHelp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _erase,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(Bn.eraseButton),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Warns, asks for consent, then erases. The app itself returns to its first
  /// screen when the data is gone (the eraser tells it).
  Future<void> _erase() async {
    final eraser = widget.eraser!;
    final sure = await askConfirmErase(context, shared: widget.isShared?.call() ?? false);
    if (!sure || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await eraser.eraseEverything();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Bn.eraseDone)));
    } catch (e) {
      final message = ruleMessage(e);
      if (message == null) rethrow;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
