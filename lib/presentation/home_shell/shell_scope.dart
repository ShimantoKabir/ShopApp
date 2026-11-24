import 'package:material_ui/material_ui.dart';

import '../../core/bangla.dart';
import '../sell/sell_viewmodel.dart';

/// What a page inside the home shell can ask of the shell: open the drawer,
/// see the shared cart (and open it), and hear when data changed elsewhere
/// (e.g. a category was added) so it can refresh quietly. Pages opened on
/// their own (not inside the shell) find no scope and simply get the normal
/// back arrow and no cart icon.
class ShellScope extends InheritedWidget {
  final VoidCallback openDrawer;

  /// The cart being filled on the selling screen. Shared, so it survives
  /// moving between screens.
  final SellViewModel? cart;
  final VoidCallback? openCart;

  /// Counts up whenever data changed on a page opened from the menu.
  final Listenable? dataChanged;

  const ShellScope({super.key, required this.openDrawer, this.cart, this.openCart, this.dataChanged, required super.child});

  static ShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

/// The menu (hamburger) button for an AppBar's `leading`, or null when the
/// page is not inside the home shell.
Widget? menuButton(BuildContext context) {
  final scope = ShellScope.maybeOf(context);
  if (scope == null) return null;
  return IconButton(icon: const Icon(Icons.menu), tooltip: Bn.menu, onPressed: scope.openDrawer);
}

/// For an AppBar's `actions`: the cart icon with the number of items on it,
/// shown only while something is in the cart (and only inside the home shell).
List<Widget> cartActions(BuildContext context) {
  final scope = ShellScope.maybeOf(context);
  final cart = scope?.cart;
  final open = scope?.openCart;
  if (cart == null || open == null) return const [];
  return [
    ListenableBuilder(
      listenable: cart,
      builder: (context, _) => cart.cartCount == 0
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: Bn.cartIconTooltip,
                onPressed: open,
                icon: Badge(label: Text('${cart.cartCount}'), child: const Icon(Icons.shopping_cart_outlined)),
              ),
            ),
    ),
  ];
}
