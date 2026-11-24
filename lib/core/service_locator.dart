import 'package:get_it/get_it.dart';

import '../data/app_database.dart';
import '../data/replicated_repositories.dart';
import '../data/sync/http_sync_transport.dart';
import '../data/sync/sync_engine.dart';
import '../data/device_services.dart';
import '../data/package_info_version_source.dart';
import '../data/sqlite_activity_repository.dart';
import '../data/sqlite_shop_repository.dart';
import '../data/sqlite_user_repository.dart';
import '../data/sync/activity_recorder.dart';
import '../data/sqlite_dashboard_repository.dart';
import '../data/sqlite_repositories.dart';
import '../data/file_picker_csv_source.dart';
import '../data/platform_contact_picker.dart';
import '../data/platform_receipt_sender.dart';
import '../data/system_services.dart';
import '../domain/import/csv_source.dart';
import '../domain/import/product_importer.dart';
import '../domain/activity.dart';
import '../domain/app_info.dart';
import '../domain/repositories.dart';
import '../domain/shop.dart';
import '../domain/services.dart';
import '../domain/settings.dart';
import '../domain/sync.dart';
import '../domain/users.dart';
import '../presentation/activity/activity_viewmodel.dart';
import '../presentation/auth/auth_viewmodel.dart';
import '../presentation/users/users_viewmodel.dart';
import '../presentation/profile/profile_viewmodel.dart';
import '../presentation/settings/language_viewmodel.dart';
import '../presentation/settings/settings_viewmodel.dart';
import '../presentation/settings/shop_name_viewmodel.dart';
import '../presentation/sync/sync_viewmodel.dart';
import '../presentation/screen_factory.dart';
import '../presentation/customers/customers_viewmodel.dart';
import '../presentation/customer_detail/customer_detail_viewmodel.dart';
import '../presentation/dashboard/dashboard_viewmodel.dart';
import '../presentation/product_list/product_list_viewmodel.dart';
import '../presentation/product_form/product_form_viewmodel.dart';
import '../presentation/categories/categories_viewmodel.dart';
import '../presentation/location_types/location_types_viewmodel.dart';
import '../presentation/locations/locations_viewmodel.dart';
import '../presentation/import_products/import_viewmodel.dart';
import '../presentation/sell/sell_viewmodel.dart';
import '../presentation/daily_sales/daily_sales_viewmodel.dart';
import 'app_config.dart';
import 'get_it_screen_factory.dart';

final GetIt sl = GetIt.instance;

/// Composition root: the only place that knows concrete implementations.
/// Everything is registered against its abstraction.
void setupServiceLocator() {
  // Infrastructure
  sl.registerLazySingleton<Clock>(SystemClock.new);
  sl.registerLazySingleton<LocationCodeGenerator>(RandomLocationCodeGenerator.new);
  sl.registerLazySingleton<AppDatabase>(AppDatabase.new);
  sl.registerLazySingleton<DatabaseProvider>(() => sl<AppDatabase>());

  sl.registerLazySingleton<PinHasher>(Sha256PinHasher.new);
  sl.registerLazySingleton<SettingsStore>(PreferencesSettingsStore.new);
  sl.registerLazySingleton<AppVersionSource>(PackageInfoVersionSource.new);

  // Who is signed in. Repositories ask for CurrentUser (to record who did
  // what); only the sign-in screens know about the Session behind it.
  sl.registerLazySingleton<Session>(Session.new);
  sl.registerLazySingleton<CurrentUser>(() => sl<Session>());

  // Sharing the shop between phones. Every change goes through the
  // WriteGateway: when the shop is shared it is written to the shared log and
  // replayed on every phone; when it is not, the plain repository just does it.
  sl.registerLazySingleton<SyncEngine>(() => SyncEngine(
        database: sl(),
        settings: sl(),
        transportFactory: HttpSyncTransport.new,
        clock: sl(),
        actor: sl(),
        defaultUrl: defaultSyncUrl,
      ));
  sl.registerLazySingleton<SyncService>(() => sl<SyncEngine>());
  sl.registerLazySingleton<WriteGateway>(() => sl<SyncEngine>());
  sl.registerLazySingleton<DataEraser>(() => sl<SyncEngine>());

  // Repositories: the SQLite ones do the work on this phone's own copy; the
  // Replicated ones (what everything else asks for) send changes through the
  // gateway first.
  sl.registerLazySingleton<SqliteProductRepository>(() => SqliteProductRepository(sl(), sl(), actor: sl()));
  sl.registerLazySingleton<SqliteStockRepository>(() => SqliteStockRepository(sl(), sl(), actor: sl()));
  sl.registerLazySingleton<SqliteSalesRepository>(() => SqliteSalesRepository(sl(), sl(), actor: sl()));
  sl.registerLazySingleton<SqliteCustomerRepository>(() => SqliteCustomerRepository(sl(), sl(), actor: sl()));
  sl.registerLazySingleton<SqliteUserRepository>(() => SqliteUserRepository(sl(), sl(), sl()));
  sl.registerLazySingleton<SqliteCategoryRepository>(() => SqliteCategoryRepository(sl()));
  sl.registerLazySingleton<SqliteLocationRepository>(() => SqliteLocationRepository(sl(), sl()));
  sl.registerLazySingleton<SqliteShopRepository>(() => SqliteShopRepository(sl()));

  sl.registerLazySingleton<ProductRepository>(() => ReplicatedProductRepository(sl<SqliteProductRepository>(), sl()));
  sl.registerLazySingleton<StockRepository>(() => ReplicatedStockRepository(sl<SqliteStockRepository>(), sl()));
  sl.registerLazySingleton<SalesRepository>(() => ReplicatedSalesRepository(sl<SqliteSalesRepository>(), sl()));
  sl.registerLazySingleton<CustomerRepository>(() => ReplicatedCustomerRepository(sl<SqliteCustomerRepository>(), sl()));
  sl.registerLazySingleton<UserRepository>(() => ReplicatedUserRepository(sl<SqliteUserRepository>(), sl(), sl()));
  sl.registerLazySingleton<CategoryRepository>(() => ReplicatedCategoryRepository(sl<SqliteCategoryRepository>(), sl()));
  sl.registerLazySingleton<LocationRepository>(() => ReplicatedLocationRepository(sl<SqliteLocationRepository>(), sl(), sl()));
  sl.registerLazySingleton<ShopRepository>(() => ReplicatedShopRepository(sl<SqliteShopRepository>(), sl()));
  sl.registerLazySingleton<DashboardRepository>(() => SqliteDashboardRepository(sl()));
  sl.registerLazySingleton<ActivityRepository>(() => SqliteActivityRepository(sl()));
  sl.registerLazySingleton<ActivityNotifier>(
    () => GatewayActivityNotifier(sl(), ActivityRecorder(sl()), () => sl<Clock>().now().millisecondsSinceEpoch),
  );

  // Import
  sl.registerLazySingleton<ReceiptSender>(PlatformReceiptSender.new);
  sl.registerLazySingleton<ContactLauncher>(PlatformContactLauncher.new);
  sl.registerLazySingleton<ContactPicker>(PlatformContactPicker.new);
  sl.registerLazySingleton<CsvSource>(FilePickerCsvSource.new);
  sl.registerLazySingleton<ProductImporter>(() => ProductImporter(sl(), sl()));

  // Shared by the whole app: the theme applies everywhere at once.
  sl.registerLazySingleton<ThemeViewModel>(() => ThemeViewModel(sl()));
  sl.registerLazySingleton<LanguageViewModel>(() => LanguageViewModel(sl()));
  sl.registerLazySingleton<ShopNameViewModel>(() => ShopNameViewModel(sl(), sl()));

  // View models: new instance per screen.
  sl.registerFactory<SyncViewModel>(() => SyncViewModel(sl()));
  sl.registerFactory<AuthViewModel>(() => AuthViewModel(sl(), sl(), sl(), sl()));
  sl.registerFactory<ActivityViewModel>(() => ActivityViewModel(sl(), sl(), sl(), sl()));
  sl.registerFactory<ProfileViewModel>(() => ProfileViewModel(sl(), sl()));
  sl.registerFactory<UsersViewModel>(() => UsersViewModel(sl(), sl()));
  sl.registerFactory<ProductListViewModel>(() => ProductListViewModel(sl(), sl(), sl(), sl()));
  sl.registerFactory<ProductFormViewModel>(() => ProductFormViewModel(sl(), sl(), sl(), sl()));
  sl.registerFactory<CategoriesViewModel>(() => CategoriesViewModel(sl()));
  sl.registerFactory<LocationsViewModel>(() => LocationsViewModel(sl()));
  sl.registerFactory<LocationTypesViewModel>(() => LocationTypesViewModel(sl()));
  // One cart for the whole app, so what was added stays while moving between screens.
  sl.registerLazySingleton<SellViewModel>(() => SellViewModel(sl(), sl(), sl(), sl(), sync: sl<SyncService>()));
  sl.registerFactory<SalesSummaryViewModel>(() => SalesSummaryViewModel(sl(), sl(), customers: sl()));
  sl.registerFactory<CustomerListViewModel>(() => CustomerListViewModel(sl()));
  sl.registerFactory<CustomerDetailViewModel>(() => CustomerDetailViewModel(sl(), sl()));
  sl.registerFactory<DashboardViewModel>(() => DashboardViewModel(sl(), sl()));
  sl.registerFactory<ImportViewModel>(() => ImportViewModel(sl(), sl()));

  // Navigation
  sl.registerLazySingleton<ScreenFactory>(() => GetItScreenFactory(sl));
}
