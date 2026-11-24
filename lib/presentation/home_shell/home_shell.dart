import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../../domain/app_info.dart';
import '../../domain/sync.dart';
import '../../domain/users.dart';
import '../components/app_logo.dart';
import '../labels.dart';
import '../screen_factory.dart';
import '../settings/shop_name_viewmodel.dart';
import 'shell_scope.dart';
import '../sell/sell_viewmodel.dart';

/// The app's main frame. Navigation is a drawer (there are too many places for
/// a bottom bar): the five main screens, then staff (owner only), settings and
/// sign out. Each screen is created fresh when chosen, so it always shows
/// current data (a sale made on one is on the others). Owners start on the
/// dashboard, staff on the sell screen.
class HomeShell extends StatefulWidget {
  final ScreenFactory screens;
  final CurrentUser currentUser;
  final VoidCallback onSignOut;

  /// When given, the drawer shows whether the shop is connected to the others.
  final SyncService? sync;

  /// When given, the bottom of the drawer shows which version of the app this is.
  final AppVersionSource? version;

  /// When given, the top of the drawer shows the shop's own name.
  final ShopNameViewModel? shopName;

  /// The shared cart: while it holds something, a cart icon with the number of
  /// items shows at the top right of every screen.
  final SellViewModel? cart;

  const HomeShell({
    super.key,
    required this.screens,
    required this.currentUser,
    required this.onSignOut,
    this.sync,
    this.version,
    this.shopName,
    this.cart,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

enum _Tab { dashboard, inventory, sell, customers, account }

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Told when something changed on a page opened from the menu (a category or
  /// location was added...), so the screen underneath refreshes without being
  /// rebuilt (which would flash a loading bar).
  final _dataChanged = ValueNotifier<int>(0);
  late final Future<String>? _versionLabel = widget.version?.label();

  AppUser? get _user => widget.currentUser.user;
  bool get _isOwner => _user?.isOwner ?? false;

  /// Everyone sees every screen; staff just start on selling.
  List<_Tab> get _tabs => [_Tab.dashboard, _Tab.inventory, _Tab.sell, _Tab.customers, _Tab.account];

  late _Tab _current = _isOwner ? _Tab.dashboard : _Tab.sell;
  late Widget _page = _build(_current);

  Widget _build(_Tab tab) => KeyedSubtree(
        key: ValueKey(tab),
        child: switch (tab) {
          _Tab.dashboard => widget.screens.dashboard(),
          _Tab.inventory => widget.screens.productList(),
          _Tab.sell => widget.screens.sell(),
          _Tab.customers => widget.screens.customers(),
          _Tab.account => widget.screens.dailySales(),
        },
      );

  static Map<_Tab, String> get _labels => {
    _Tab.dashboard: Bn.navDashboard,
    _Tab.inventory: Bn.navInventory,
    _Tab.sell: Bn.navSell,
    _Tab.customers: Bn.navCustomers,
    _Tab.account: Bn.navAccount,
  };
  static const _icons = {
    _Tab.dashboard: (Icons.dashboard_outlined, Icons.dashboard),
    _Tab.inventory: (Icons.inventory_2_outlined, Icons.inventory_2),
    _Tab.sell: (Icons.point_of_sale_outlined, Icons.point_of_sale),
    _Tab.customers: (Icons.people_outline, Icons.people),
    _Tab.account: (Icons.receipt_long_outlined, Icons.receipt_long),
  };

  /// What the drawer lists after the screens: [staff], settings, sign out.
  List<(String, IconData, VoidCallback)> get _actions => [
        (Bn.locations, Icons.shelves, () => _push(widget.screens.locations(), refreshScreen: true)),
        (Bn.categories, Icons.category_outlined, () => _push(widget.screens.categories(), refreshScreen: true)),
        (Bn.navUsers, Icons.badge_outlined, () => _push(widget.screens.users())),
        (Bn.navActivity, Icons.history, () => _push(widget.screens.activity())),
        (Bn.navProfile, Icons.account_circle_outlined, () => _push(widget.screens.profile())),
        (Bn.navSettings, Icons.settings_outlined, () => _push(widget.screens.settings())),
        (Bn.navSignOut, Icons.logout, widget.onSignOut),
      ];

  /// Opens a page on top; when it closes the drawer header is refreshed (a
  /// changed name shows up at once). With [refreshScreen] the screen that was
  /// open is built again too, so it shows what the page changed (e.g. a new
  /// category in the inventory's filter).
  Future<void> _push(Widget page, {bool refreshScreen = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    if (refreshScreen) _dataChanged.value++;
    setState(() {});
  }

  void _selected(int index) {
    _scaffoldKey.currentState?.closeDrawer();
    final tabs = _tabs;
    if (index < tabs.length) {
      final tab = tabs[index];
      if (tab != _current) {
        setState(() {
          _current = tab;
          _page = _build(tab);
        });
      }
    } else {
      _actions[index - tabs.length].$3();
    }
  }

  @override
  void dispose() {
    _dataChanged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final theme = Theme.of(context);
    final user = _user;
    return ShellScope(
      openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      cart: widget.cart,
      openCart: widget.cart == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => widget.screens.cart(widget.cart!))),
      dataChanged: _dataChanged,
      child: Scaffold(
        key: _scaffoldKey,
        body: _page,
        drawer: NavigationDrawer(
          selectedIndex: tabs.indexOf(_current),
          onDestinationSelected: _selected,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.shopName == null
                            ? Text(Bn.appTitle, style: theme.textTheme.titleLarge)
                            : ListenableBuilder(
                                listenable: widget.shopName!,
                                builder: (context, _) => Text(
                                  widget.shopName!.name,
                                  style: theme.textTheme.titleLarge,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        if (user != null) ...[
                          const SizedBox(height: 4),
                          Text('${user.name} • ${roleLabel(user.role)}',
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                        if (widget.sync != null && widget.sync!.enabled) ...[
                          const SizedBox(height: 4),
                          Text(
                            syncStateLabel(widget.sync!.state),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: widget.sync!.state == SyncState.idle ? Colors.green.shade700 : theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            for (final tab in tabs)
              NavigationDrawerDestination(
                icon: Icon(_icons[tab]!.$1),
                selectedIcon: Icon(_icons[tab]!.$2),
                label: Text(_labels[tab]!),
              ),
            const Padding(padding: EdgeInsets.fromLTRB(28, 8, 28, 8), child: Divider()),
            for (final (label, icon, _) in _actions) NavigationDrawerDestination(icon: Icon(icon), label: Text(label)),
            if (_versionLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                child: FutureBuilder<String>(
                  future: _versionLabel,
                  builder: (context, snapshot) => Text(
                    snapshot.hasData ? Bn.appVersion(snapshot.data!) : '',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
