import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/entities.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import '../domain/app_info.dart';
import '../domain/sync.dart';
import '../domain/users.dart';
import '../presentation/activity_page.dart';
import '../presentation/activity_viewmodel.dart';
import '../presentation/auth_pages.dart';
import '../presentation/auth_viewmodels.dart';
import '../presentation/categories_page.dart';
import '../presentation/cart_page.dart';
import '../presentation/checkout_page.dart';
import '../presentation/customer_detail_page.dart';
import '../presentation/customer_viewmodels.dart';
import '../presentation/customers_page.dart';
import '../presentation/daily_sales_page.dart';
import '../presentation/dashboard_page.dart';
import '../presentation/dashboard_viewmodel.dart';
import '../presentation/home_shell.dart';
import '../presentation/import_page.dart';
import '../presentation/product_form_page.dart';
import '../presentation/product_list_page.dart';
import '../presentation/profile_page.dart';
import '../presentation/receipt_page.dart';
import '../presentation/scan_page.dart';
import '../presentation/screen_factory.dart';
import '../presentation/settings_page.dart';
import '../presentation/language_viewmodel.dart';
import '../presentation/location_types_page.dart';
import '../presentation/settings_viewmodel.dart';
import '../presentation/shop_name_viewmodel.dart';
import '../presentation/sync_pages.dart';
import '../presentation/sync_viewmodel.dart';
import '../presentation/users_page.dart';
import '../presentation/sell_page.dart';
import '../presentation/locations_page.dart';
import '../presentation/viewmodels.dart';

/// Part of the composition root. This is the only place that resolves
/// view models from the container and hands them to pages.
class GetItScreenFactory implements ScreenFactory {
  final GetIt _container;
  GetItScreenFactory(this._container);

  @override
  Widget home() => AuthGate(viewModel: _container<AuthViewModel>(), screens: this);

  @override
  Widget shell({required VoidCallback onSignOut}) =>
      HomeShell(
        screens: this,
        currentUser: _container<CurrentUser>(),
        onSignOut: onSignOut,
        sync: _container<SyncService>(),
        version: _container<AppVersionSource>(),
        shopName: _container<ShopNameViewModel>(),
        cart: _container<SellViewModel>(),
      );

  @override
  Widget users() => UsersPage(viewModel: _container<UsersViewModel>(), canManage: _container<CurrentUser>().user?.isOwner ?? false);

  @override
  Widget activity() => ActivityPage(viewModel: _container<ActivityViewModel>());

  @override
  Widget profile() => ProfilePage(viewModel: _container<ProfileViewModel>());

  @override
  Widget syncSettings() => SyncSettingsPage(
        viewModel: _container<SyncViewModel>(),
        canShare: _container<CurrentUser>().user?.isOwner ?? false,
      );

  @override
  Widget joinShop() => JoinShopPage(viewModel: _container<SyncViewModel>());

  @override
  Widget settings() => SettingsPage(
        theme: _container<ThemeViewModel>(),
        shopName: _container<ShopNameViewModel>(),
        language: _container<LanguageViewModel>(),
        syncPanel: () => SyncPanel(
          viewModel: _container<SyncViewModel>(),
          canShare: _container<CurrentUser>().user?.isOwner ?? false,
        ),
        eraser: (_container<CurrentUser>().user?.isOwner ?? false) ? _container<DataEraser>() : null,
        isShared: () => _container<SyncService>().enabled,
        canEditShop: _container<CurrentUser>().user?.isOwner ?? false,
      );

  @override
  Widget dashboard() => DashboardPage(viewModel: _container<DashboardViewModel>());

  @override
  Widget customers() => CustomersPage(
        viewModel: _container<CustomerListViewModel>(),
        screens: this,
        contacts: _container<ContactLauncher>(),
        shopName: _container<ShopNameViewModel>().name,
      );

  @override
  Widget customerDetail(int customerId) =>
      CustomerDetailPage(
        viewModel: _container<CustomerDetailViewModel>(),
        customerId: customerId,
        screens: this,
        sender: _container<ReceiptSender>(),
        contacts: _container<ContactLauncher>(),
        shopName: _container<ShopNameViewModel>().name,
      );

  @override
  Widget sell() => SellPage(viewModel: _container<SellViewModel>(), screens: this);

  @override
  Widget dailySales() => DailySalesPage(
        viewModel: _container<SalesSummaryViewModel>(),
        screens: this,
        contacts: _container<ContactLauncher>(),
        shopName: _container<ShopNameViewModel>().name,
      );

  @override
  Widget checkout(SellViewModel cart) => CheckoutPage(viewModel: cart, screens: this);

  @override
  Widget cart(SellViewModel cart) => CartPage(viewModel: cart, screens: this);

  @override
  Widget receipt(Bill bill) =>
      ReceiptPage(bill: bill, sender: _container<ReceiptSender>(), shopName: _container<ShopNameViewModel>().name);

  @override
  Widget productList({StorageLocation? location}) => ProductListPage(
        viewModel: _container<ProductListViewModel>(),
        screens: this,
        location: location,
      );

  @override
  Widget productForm({Product? product, int? initialLocationId}) => ProductFormPage(
        viewModel: _container<ProductFormViewModel>(),
        screens: this,
        product: product,
        initialLocationId: initialLocationId,
      );

  @override
  Widget categories() => CategoriesPage(viewModel: _container<CategoriesViewModel>());

  @override
  Widget locations() => LocationsPage(viewModel: _container<LocationsViewModel>(), screens: this);

  @override
  Widget locationTypes() => LocationTypesPage(viewModel: _container<LocationTypesViewModel>());

  @override
  Widget locationQr(StorageLocation location) => LocationQrPage(location: location, screens: this);

  @override
  Widget scanner() => const ScanPage();

  @override
  Widget importProducts() => ImportPage(viewModel: _container<ImportViewModel>());
}
