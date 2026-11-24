import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/entities.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import '../domain/app_info.dart';
import '../domain/sync.dart';
import '../domain/users.dart';
import '../presentation/activity/activity_page.dart';
import '../presentation/activity/activity_viewmodel.dart';
import '../presentation/auth/auth_pages.dart';
import '../presentation/auth/auth_viewmodel.dart';
import '../presentation/users/users_viewmodel.dart';
import '../presentation/profile/profile_viewmodel.dart';
import '../presentation/categories/categories_page.dart';
import '../presentation/cart/cart_page.dart';
import '../presentation/checkout/checkout_page.dart';
import '../presentation/customer_detail/customer_detail_page.dart';
import '../presentation/customers/customers_viewmodel.dart';
import '../presentation/customer_detail/customer_detail_viewmodel.dart';
import '../presentation/customers/customers_page.dart';
import '../presentation/daily_sales/daily_sales_page.dart';
import '../presentation/dashboard/dashboard_page.dart';
import '../presentation/dashboard/dashboard_viewmodel.dart';
import '../presentation/home_shell/home_shell.dart';
import '../presentation/import_products/import_page.dart';
import '../presentation/product_form/product_form_page.dart';
import '../presentation/product_list/product_list_page.dart';
import '../presentation/profile/profile_page.dart';
import '../presentation/receipt/receipt_page.dart';
import '../presentation/scan/scan_page.dart';
import '../presentation/screen_factory.dart';
import '../presentation/settings/settings_page.dart';
import '../presentation/settings/language_viewmodel.dart';
import '../presentation/location_types/location_types_page.dart';
import '../presentation/settings/settings_viewmodel.dart';
import '../presentation/settings/shop_name_viewmodel.dart';
import '../presentation/sync/sync_pages.dart';
import '../presentation/sync/sync_viewmodel.dart';
import '../presentation/users/users_page.dart';
import '../presentation/sell/sell_page.dart';
import '../presentation/locations/locations_page.dart';
import '../presentation/product_list/product_list_viewmodel.dart';
import '../presentation/product_form/product_form_viewmodel.dart';
import '../presentation/categories/categories_viewmodel.dart';
import '../presentation/location_types/location_types_viewmodel.dart';
import '../presentation/locations/locations_viewmodel.dart';
import '../presentation/import_products/import_viewmodel.dart';
import '../presentation/sell/sell_viewmodel.dart';
import '../presentation/daily_sales/daily_sales_viewmodel.dart';
import '../presentation/receipt/receipt_viewmodel.dart';

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
        contactPicker: _container<ContactPicker>(),
        sender: _container<ReceiptSender>(),
      );

  @override
  Widget checkout(SellViewModel cart) =>
      CheckoutPage(viewModel: cart, screens: this, contactPicker: _container<ContactPicker>());

  @override
  Widget cart(SellViewModel cart) => CartPage(viewModel: cart, screens: this);

  @override
  Widget receipt(Bill bill) => ReceiptPage(
        bill: bill,
        sender: _container<ReceiptSender>(),
        shopName: _container<ShopNameViewModel>().name,
        viewModel: ReceiptViewModel(_container<SalesRepository>(), _container<CustomerRepository>(), bill),
        // Anyone can add a customer to a sale that has none; changing one is for the owner.
        canChangeCustomer: _container<CurrentUser>().user?.isOwner ?? false,
        contactPicker: _container<ContactPicker>(),
      );

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
