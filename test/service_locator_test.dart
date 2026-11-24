import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/service_locator.dart';
import 'package:hardware_shop/domain/import/csv_source.dart';
import 'package:hardware_shop/domain/import/product_importer.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/services.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/auth_viewmodels.dart';
import 'package:hardware_shop/presentation/settings_viewmodel.dart';
import 'package:hardware_shop/presentation/shop_name_viewmodel.dart';
import 'package:hardware_shop/domain/shop.dart';
import 'package:hardware_shop/presentation/sync_viewmodel.dart';
import 'package:hardware_shop/presentation/activity_viewmodel.dart';
import 'package:hardware_shop/domain/activity.dart';
import 'package:hardware_shop/data/replicated_repositories.dart';
import 'package:hardware_shop/data/sync/sync_engine.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/presentation/screen_factory.dart';
import 'package:hardware_shop/presentation/customer_viewmodels.dart';
import 'package:hardware_shop/presentation/dashboard_viewmodel.dart';
import 'package:hardware_shop/presentation/viewmodels.dart';

/// Guards the composition root: every registration must be resolvable.
/// (A wrong registration only fails at runtime, so unit tests of the pieces
/// can't catch it.)
void main() {
  setUp(() async {
    await sl.reset();
    setupServiceLocator();
  });

  test('every abstraction resolves', () {
    expect(sl<Clock>(), isNotNull);
    expect(sl<LocationCodeGenerator>(), isNotNull);
    expect(sl<ProductRepository>(), isNotNull);
    expect(sl<CategoryRepository>(), isNotNull);
    expect(sl<LocationRepository>(), isNotNull);
    expect(sl<StockRepository>(), isNotNull);
    expect(sl<SalesRepository>(), isNotNull);
    expect(sl<CustomerRepository>(), isNotNull);
    expect(sl<UserRepository>(), isNotNull);
    expect(sl<PinHasher>(), isNotNull);
    expect(sl<ActivityRepository>(), isNotNull);
    expect(sl<ActivityNotifier>(), isNotNull);
    expect(sl<SettingsStore>(), isNotNull);
    expect(sl<ReceiptSender>(), isNotNull);
    expect(sl<CsvSource>(), isNotNull);
    expect(sl<ProductImporter>(), isNotNull);
    expect(sl<ScreenFactory>(), isNotNull);
  });

  test('every view model resolves, as a new instance each time', () {
    expect(sl<ProductListViewModel>(), isNot(same(sl<ProductListViewModel>())));
    expect(sl<ProductFormViewModel>(), isNotNull);
    expect(sl<CategoriesViewModel>(), isNotNull);
    expect(sl<LocationsViewModel>(), isNotNull);
    expect(sl<ImportViewModel>(), isNotNull);
    expect(sl<SellViewModel>(), isNotNull);
    expect(sl<SalesSummaryViewModel>(), isNotNull);
    expect(sl<DashboardViewModel>(), isNotNull);
    expect(sl<CustomerListViewModel>(), isNotNull);
    expect(sl<CustomerDetailViewModel>(), isNotNull);
    expect(sl<AuthViewModel>(), isNotNull);
    expect(sl<UsersViewModel>(), isNotNull);
    expect(sl<ProfileViewModel>(), isNotNull);
    expect(sl<SyncViewModel>(), isNotNull);
    expect(sl<ActivityViewModel>(), isNotNull);
  });

  test('what the app uses for data changes goes through the sharing gateway', () {
    expect(sl<ProductRepository>(), isA<ReplicatedProductRepository>());
    expect(sl<StockRepository>(), isA<ReplicatedStockRepository>());
    expect(sl<SalesRepository>(), isA<ReplicatedSalesRepository>());
    expect(sl<CustomerRepository>(), isA<ReplicatedCustomerRepository>());
    expect(sl<UserRepository>(), isA<ReplicatedUserRepository>());
    expect(sl<CategoryRepository>(), isA<ReplicatedCategoryRepository>());
    expect(sl<ShopRepository>(), isA<ReplicatedShopRepository>());
    expect(sl<LocationRepository>(), isA<ReplicatedLocationRepository>());
  });

  test('one sharing engine serves as the gateway and as the service the screens use', () {
    expect(sl<WriteGateway>(), same(sl<SyncEngine>()));
    expect(sl<SyncService>(), same(sl<SyncEngine>()));
    expect(sl<SyncService>().enabled, isFalse, reason: 'a new install is not shared until the owner says so');
    expect(sl<SyncService>().defaultUrl, startsWith('https://'));
  });

  test('the signed-in user is one thing for the whole app, and the theme too', () {
    expect(sl<CurrentUser>(), same(sl<Session>()), reason: 'repositories see who the sign in screen signed in');
    expect(sl<ThemeViewModel>(), same(sl<ThemeViewModel>()), reason: 'one theme for every screen');
    expect(sl<ShopNameViewModel>(), same(sl<ShopNameViewModel>()), reason: 'one shop name for every screen');
  });
}
