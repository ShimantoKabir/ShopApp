import '../domain/customers.dart';
import '../domain/entities.dart';
import '../domain/payments.dart';
import '../domain/repositories.dart';
import '../domain/sales.dart';
import '../domain/services.dart';
import '../domain/settings.dart';
import '../domain/shop.dart';
import '../domain/stock.dart';
import '../domain/sync.dart';
import '../domain/users.dart';
import 'sync/op_envelope.dart';

// Each repository here wraps the normal one. Reading goes straight to this
// phone's own copy. Every CHANGE goes through the [WriteGateway]: when the
// shop is shared it becomes an entry in the shared log (and is replayed on
// every phone, this one included); when it is not, the normal repository just
// does it. Screens never know the difference.

class ReplicatedProductRepository implements ProductRepository {
  final ProductRepository _local;
  final WriteGateway _gateway;
  ReplicatedProductRepository(this._local, this._gateway);

  @override
  Future<bool> existsSimilar({required String name, String brand = '', String size = '', int? excludeId}) =>
      _local.existsSimilar(name: name, brand: brand, size: size, excludeId: excludeId);

  @override
  Future<List<Product>> search({String query = '', int? categoryId, int? locationId, ProductKind? kind}) =>
      _local.search(query: query, categoryId: categoryId, locationId: locationId, kind: kind);

  @override
  Future<Product?> byId(int id) => _local.byId(id);

  @override
  Future<Product> save(Product product) =>
      _gateway.write('product.save', {'product': productToJson(product)}, () => _local.save(product));

  @override
  Future<void> delete(int id) => _gateway.write('product.delete', {'id': id}, () => _local.delete(id));

  @override
  Future<void> adjustStock(int id, double newTotal) =>
      _gateway.write('product.adjustStock', {'id': id, 'newTotal': newTotal}, () => _local.adjustStock(id, newTotal));
}

class ReplicatedStockRepository implements StockRepository {
  final StockRepository _local;
  final WriteGateway _gateway;
  ReplicatedStockRepository(this._local, this._gateway);

  @override
  Future<List<StockPlacement>> placements(int productId) => _local.placements(productId);

  @override
  Future<List<StockLogEntry>> history(int productId, {int limit = 30}) => _local.history(productId, limit: limit);

  @override
  Future<void> place(int productId, int locationId, double quantity) => _gateway.write(
      'stock.place',
      {'productId': productId, 'locationId': locationId, 'quantity': quantity},
      () => _local.place(productId, locationId, quantity));

  @override
  Future<void> recount(int productId, int locationId, double quantity) => _gateway.write(
      'stock.recount',
      {'productId': productId, 'locationId': locationId, 'quantity': quantity},
      () => _local.recount(productId, locationId, quantity));

  @override
  Future<void> move(int productId, int fromLocationId, int toLocationId, double quantity) => _gateway.write(
      'stock.move',
      {'productId': productId, 'from': fromLocationId, 'to': toLocationId, 'quantity': quantity},
      () => _local.move(productId, fromLocationId, toLocationId, quantity));

  @override
  Future<void> restock(int productId, double quantity, {int? locationId, double? purchasePrice}) => _gateway.write(
      'stock.restock',
      {'productId': productId, 'quantity': quantity, 'locationId': locationId, 'purchasePrice': purchasePrice},
      () => _local.restock(productId, quantity, locationId: locationId, purchasePrice: purchasePrice));
}

class ReplicatedSalesRepository implements SalesRepository {
  final SalesRepository _local;
  final WriteGateway _gateway;
  ReplicatedSalesRepository(this._local, this._gateway);

  @override
  Future<Bill> checkout(List<SaleLine> lines, {CustomerInfo? customer, double? paid}) => _gateway.write(
      'sale.checkout',
      {
        'lines': [for (final l in lines) saleLineToJson(l)],
        'customer': customerToJson(customer),
        'paid': paid,
      },
      () => _local.checkout(lines, customer: customer, paid: paid));

  @override
  Future<void> voidBill(int billId) => _gateway.write('sale.void', {'billId': billId}, () => _local.voidBill(billId));

  @override
  Future<List<Bill>> billsOn(DateTime day) => _local.billsOn(day);

  @override
  Future<Bill?> billById(int id) => _local.billById(id);

  @override
  Future<List<Bill>> billsOfCustomer(int customerId) => _local.billsOfCustomer(customerId);

  @override
  Future<double> collectedOn(DateTime day) => _local.collectedOn(day);
}

class ReplicatedCustomerRepository implements CustomerRepository {
  final CustomerRepository _local;
  final WriteGateway _gateway;
  ReplicatedCustomerRepository(this._local, this._gateway);

  @override
  Future<CustomerInfo?> findByPhone(String number) => _local.findByPhone(number);

  @override
  Future<List<CustomerSummary>> all() => _local.all();

  @override
  Future<CustomerSummary?> byId(int id) => _local.byId(id);

  @override
  Future<List<Payment>> paymentsOf(int customerId) => _local.paymentsOf(customerId);

  @override
  Future<Payment> collectPayment(int customerId, double amount) => _gateway.write(
      'payment.collect', {'customerId': customerId, 'amount': amount}, () => _local.collectPayment(customerId, amount));
}

class ReplicatedCategoryRepository implements CategoryRepository {
  final CategoryRepository _local;
  final WriteGateway _gateway;
  ReplicatedCategoryRepository(this._local, this._gateway);

  @override
  Future<List<Category>> all() => _local.all();

  @override
  Future<Category> add(String name) => _gateway.write('category.add', {'name': name}, () => _local.add(name));

  /// An empty name is refused here, before anything is sent to the shared log.
  @override
  Future<Category> update(int id, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const CategoryException(CategoryProblem.emptyName);
    return _gateway.write('category.edit', {'id': id, 'name': clean}, () => _local.update(id, clean));
  }

  @override
  Future<void> delete(int id) => _gateway.write('category.delete', {'id': id}, () => _local.delete(id));
}

class ReplicatedLocationRepository implements LocationRepository {
  final LocationRepository _local;
  final WriteGateway _gateway;
  final LocationCodeGenerator _codes;
  ReplicatedLocationRepository(this._local, this._gateway, this._codes);

  @override
  Future<List<StorageLocation>> all() => _local.all();

  @override
  Future<StorageLocation?> findByCode(String code) => _local.findByCode(code);

  @override
  Future<Map<int, int>> stockedProductCounts() => _local.stockedProductCounts();

  /// The QR code is chosen here, once, and written in the entry, so that every
  /// phone gives the location the same code.
  @override
  Future<StorageLocation> add(String name, LocationType type) => _gateway.write(
      'location.add', {'name': name, 'type': type.name, 'code': _codes.generate()}, () => _local.add(name, type));

  /// An empty name is refused here, before anything is sent to the shared log.
  @override
  Future<StorageLocation> update(int id, {required String name, required LocationType type}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const LocationException(LocationProblem.emptyName);
    return _gateway.write(
      'location.edit',
      {'id': id, 'name': clean, 'type': type.name},
      () => _local.update(id, name: clean, type: type),
    );
  }

  /// A built-in type or an empty name is refused here, before anything is sent.
  @override
  Future<int> renameType(LocationType type, String newName) async {
    if (type.isBuiltIn) throw const LocationException(LocationProblem.builtInType);
    final clean = newName.trim();
    if (clean.isEmpty) throw const LocationException(LocationProblem.emptyName);
    return _gateway.write('locationType.rename', {'from': type.name, 'to': clean}, () => _local.renameType(type, clean));
  }

  @override
  Future<int> deleteType(LocationType type) async {
    if (type.isBuiltIn) throw const LocationException(LocationProblem.builtInType);
    return _gateway.write('locationType.delete', {'name': type.name}, () => _local.deleteType(type));
  }

  @override
  Future<void> delete(int id) => _gateway.write('location.delete', {'id': id}, () => _local.delete(id));
}

class ReplicatedUserRepository implements UserRepository {
  final UserRepository _local;
  final WriteGateway _gateway;
  final PinHasher _hasher;
  ReplicatedUserRepository(this._local, this._gateway, this._hasher);

  @override
  Future<bool> hasUsers() => _local.hasUsers();

  @override
  Future<List<AppUser>> all() => _local.all();

  @override
  Future<AppUser> signIn(int userId, String pin) => _local.signIn(userId, pin);

  /// A PIN is turned into a salt and hash here, where it was typed. Only
  /// those go in the log: the PIN itself never leaves this phone.
  Map<String, Object?> _credentials(String pin) {
    final salt = _hasher.newSalt();
    return {'salt': salt, 'hash': _hasher.hash(normalizePin(pin), salt)};
  }

  @override
  Future<AppUser> create({required String name, required String pin, required UserRole role}) async {
    if (name.trim().isEmpty) throw const AuthException(AuthProblem.invalidName);
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    return _gateway.write(
      'user.create',
      {'name': name, 'role': role.name, ..._credentials(pin)},
      () => _local.create(name: name, pin: pin, role: role),
    );
  }

  @override
  Future<void> setPin(int userId, String pin) async {
    if (!isValidPin(pin)) throw const AuthException(AuthProblem.invalidPin);
    return _gateway.write('user.setPin', {'userId': userId, ..._credentials(pin)}, () => _local.setPin(userId, pin));
  }

  /// Checks the current PIN here (it is not in the log), then records the new one.
  @override
  Future<void> changePin(int userId, {required String currentPin, required String newPin}) async {
    await _local.signIn(userId, currentPin); // wrongPin, unknownUser, inactive
    if (!isValidPin(newPin)) throw const AuthException(AuthProblem.invalidPin);
    return _gateway.write(
      'user.setPin',
      {'userId': userId, ..._credentials(newPin)},
      () => _local.changePin(userId, currentPin: currentPin, newPin: newPin),
    );
  }

  @override
  Future<AppUser> updateProfile(int userId,
          {required String name, String mobile = '', String phone = '', String address = ''}) =>
      _gateway.write(
        'user.updateProfile',
        {'userId': userId, 'name': name, 'mobile': mobile, 'phone': phone, 'address': address},
        () => _local.updateProfile(userId, name: name, mobile: mobile, phone: phone, address: address),
      );

  @override
  Future<void> setActive(int userId, bool active) =>
      _gateway.write('user.setActive', {'userId': userId, 'active': active}, () => _local.setActive(userId, active));
}

class ReplicatedShopRepository implements ShopRepository {
  final ShopRepository _local;
  final WriteGateway _gateway;
  ReplicatedShopRepository(this._local, this._gateway);

  @override
  Future<String?> name() => _local.name();

  /// A name that breaks the rules is refused here, before anything is sent: it
  /// should never take up a place in the shared log.
  @override
  Future<void> rename(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const ShopException(ShopProblem.emptyName);
    if (clean.length > maxShopNameLength) throw const ShopException(ShopProblem.nameTooLong);
    return _gateway.write('shop.rename', {'name': clean}, () => _local.rename(clean));
  }
}
