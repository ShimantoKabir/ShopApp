import 'package:material_ui/material_ui.dart';

import '../domain/entities.dart';
import '../domain/sales.dart';
import 'viewmodels.dart';

/// Pages ask this abstraction for other screens instead of constructing
/// concrete pages (and their dependencies) themselves.
abstract class ScreenFactory {
  /// The first screen: sets the shop up, asks who you are, then shows the app.
  Widget home();

  /// The app itself (drawer and screens), for whoever is signed in.
  Widget shell({required VoidCallback onSignOut});
  Widget users();

  /// Who did what, for everyone to see.
  Widget activity();
  Widget profile();

  /// Share the shop with other phones (owner), and see how it is going.
  Widget syncSettings();

  /// A new phone joins a shop that is already shared.
  Widget joinShop();
  Widget settings();

  /// Rename or delete the location types the shop made up.
  Widget locationTypes();
  Widget dashboard();
  Widget customers();

  /// One customer's details and purchase history.
  Widget customerDetail(int customerId);
  Widget sell();
  Widget dailySales();

  /// Review the cart and take customer / payment details. Uses the sell
  /// screen's [cart] view model (it owns the cart).
  Widget checkout(SellViewModel cart);

  /// What is in the cart: change it, sell it, or cancel it.
  Widget cart(SellViewModel cart);

  /// A bill's receipt (to look at, send on WhatsApp, or share).
  Widget receipt(Bill bill);
  Widget productList({StorageLocation? location});
  Widget productForm({Product? product, int? initialLocationId});
  Widget categories();
  Widget locations();
  Widget locationQr(StorageLocation location);
  Widget scanner();
  Widget importProducts();
}
