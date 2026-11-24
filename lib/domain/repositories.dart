import 'customers.dart';
import 'dashboard.dart';
import 'payments.dart';
import 'users.dart';
import 'entities.dart';
import 'sales.dart';
import 'stock.dart';

/// Abstractions the presentation layer depends on (DIP).
/// Each interface is small and focused (ISP).
abstract class ProductRepository {
  /// Whether a product with the same name, brand and size already exists
  /// (case-insensitive). Pass [excludeId] to ignore the product being edited.
  Future<bool> existsSimilar({
    required String name,
    String brand = '',
    String size = '',
    int? excludeId,
  });

  /// [query] matches name, brand, size, model and finish. With [locationId],
  /// only products that have stock placed at that location are returned.
  /// Returned products include their [Product.placements].
  Future<List<Product>> search({
    String query = '',
    int? categoryId,
    int? locationId,
    ProductKind? kind,
  });

  Future<Product?> byId(int id);

  /// Saves product details and total stock.
  ///
  /// For a NEW product, [Product.placements] are stored too. For an existing
  /// product they are ignored: use [StockRepository] to change where stock is
  /// kept. Throws [StockException] if the stock would be less than what is
  /// already placed (or, for a new product, if placements exceed stock).
  Future<Product> save(Product product);

  Future<void> delete(int id);

  /// Sets the product's total stock. Throws [StockException] (belowPlaced) if
  /// [newTotal] is less than the quantity already placed at locations.
  Future<void> adjustStock(int id, double newTotal);
}

/// Where stock is kept, and how it moves between places. Every operation is
/// atomic and writes to the history log.
abstract class StockRepository {
  Future<List<StockPlacement>> placements(int productId);

  /// Sets how much of the product's EXISTING stock is kept at [locationId]
  /// (0 removes it from there). Does not change the total. Throws
  /// [StockException] (exceedsStock) if placed quantities would exceed total.
  Future<void> place(int productId, int locationId, double quantity);

  /// A physical count: sets the quantity at [locationId] to what was really
  /// found, and adjusts the product total by the difference.
  Future<void> recount(int productId, int locationId, double quantity);

  /// Moves [quantity] from one location to another. Throws [StockException]
  /// if the quantity is invalid, the locations are the same, or the source
  /// holds less than [quantity].
  Future<void> move(int productId, int fromLocationId, int toLocationId, double quantity);

  /// New goods arrived: adds [quantity] to the total (and to [locationId], if
  /// given). If [purchasePrice] is given it becomes the product's buying price.
  /// Throws [StockException] (invalidQuantity) for zero or negative quantities.
  Future<void> restock(int productId, double quantity, {int? locationId, double? purchasePrice});

  /// Newest first.
  Future<List<StockLogEntry>> history(int productId, {int limit = 30});
}

/// Selling. Every operation is atomic: the bill, its lines, the stock changes,
/// the customer record and the history entries are written together or not at all.
abstract class SalesRepository {
  /// Sells all [lines] as one bill and reduces stock to match.
  ///
  /// Each line's units come from its [SaleLine.fromLocationId] if set;
  /// otherwise from stock that is not placed anywhere first, then from
  /// locations (largest first), so placed quantities never exceed the total.
  ///
  /// Every sale needs [customer] with an address and a valid WhatsApp number
  /// (the receipt goes there). Name, mobile and NID are optional, but if given
  /// must be valid.
  ///
  /// [paid] defaults to the full total. If less is paid, the rest is due, and
  /// then the customer must also have a name, a valid mobile number and a
  /// valid NID. The customer is remembered (matched by WhatsApp number).
  ///
  /// Throws [StockException] (insufficientStock, notEnoughAtSource,
  /// invalidQuantity) or [SaleException] (emptyBill, contactRequired,
  /// invalidPayment, customerRequiredForDue, invalidCustomer). On any failure
  /// nothing is saved.
  Future<Bill> checkout(List<SaleLine> lines, {CustomerInfo? customer, double? paid});

  /// Cancels a whole bill and returns every line's units to stock (to the
  /// same location if that line came from exactly one). Does nothing if the
  /// bill no longer exists.
  Future<void> voidBill(int billId);

  /// Adds (or changes) the customer of a bill that was already sold, for a sale
  /// made without one. The customer needs a valid number (the receipt and
  /// reminders go there); the name, address and NID are optional unless the
  /// bill has a due, then all are required. Whoever matches the number keeps
  /// their record, as at checkout. Returns the bill as it is now.
  ///
  /// Throws [SaleException]: unknownBill, contactRequired, invalidCustomer,
  /// customerRequiredForDue. On failure nothing changes.
  Future<Bill> attachCustomer(int billId, CustomerInfo customer);

  /// All bills on the calendar day of [day] (local time), newest first.
  Future<List<Bill>> billsOn(DateTime day);

  Future<Bill?> billById(int id);

  /// Every bill made to one customer, newest first.
  Future<List<Bill>> billsOfCustomer(int customerId);

  /// Money received from customers paying off dues, from the start of [day]
  /// to its end.
  Future<double> collectedOn(DateTime day);

  /// The payments received on the calendar day of [day] (local time), newest
  /// first, each with who paid and what they still owed right after it.
  Future<List<PaymentReceipt>> paymentsOn(DateTime day);
}

abstract class CustomerRepository {
  /// A customer seen before, by their WhatsApp or mobile number (any usual
  /// format), or null.
  Future<CustomerInfo?> findByPhone(String number);

  /// Every customer with their totals, most recent buyer first.
  Future<List<CustomerSummary>> all();

  /// One customer with their totals, or null if there is no such customer.
  Future<CustomerSummary?> byId(int id);

  /// Records money received from a customer and takes it off what they owe,
  /// oldest unpaid bill first (so every bill's own due stays right).
  ///
  /// Throws [PaymentException]: invalidAmount (zero, negative, not a number),
  /// exceedsDue (more than they owe in all), unknownCustomer. On failure
  /// nothing is recorded.
  Future<Payment> collectPayment(int customerId, double amount);

  /// A customer's payments, newest first.
  Future<List<Payment>> paymentsOf(int customerId);
}

abstract class UserRepository {
  /// False on a brand-new install: the first screen then creates the owner.
  Future<bool> hasUsers();

  /// Everyone, active or not, by name.
  Future<List<AppUser>> all();

  /// Throws [AuthException]: invalidName, invalidPin, nameTaken.
  Future<AppUser> create({required String name, required String pin, required UserRole role});

  /// Checks the PIN. Throws [AuthException]: unknownUser, inactive, wrongPin.
  Future<AppUser> signIn(int userId, String pin);

  /// Throws [AuthException]: invalidPin, unknownUser.
  Future<void> setPin(int userId, String pin);

  /// Changes a person's own PIN: they must know the current one. Throws
  /// [AuthException]: wrongPin, invalidPin, unknownUser.
  Future<void> changePin(int userId, {required String currentPin, required String newPin});

  /// Saves what a person says about themselves and returns them as they are
  /// now. A blank mobile / phone / address is fine; a filled-in number must be
  /// real. Throws [AuthException]: invalidName, nameTaken, invalidPhone,
  /// unknownUser. On failure nothing changes.
  Future<AppUser> updateProfile(
    int userId, {
    required String name,
    String mobile = '',
    String phone = '',
    String address = '',
  });

  /// Switches someone on or off. Throws [AuthException]: unknownUser, lastOwner
  /// (the last active owner cannot be switched off).
  Future<void> setActive(int userId, bool active);
}

abstract class CategoryRepository {
  Future<List<Category>> all();
  Future<Category> add(String name);

  /// Renames a category. The products in it stay in it. Throws
  /// [CategoryException] for an empty name, an unknown id, or a name another
  /// category already has.
  Future<Category> update(int id, String name);
  Future<void> delete(int id);
}

abstract class LocationRepository {
  Future<List<StorageLocation>> all();
  Future<StorageLocation> add(String name, LocationType type);
  Future<StorageLocation?> findByCode(String code);

  /// Number of distinct products with stock at each location (id -> count).
  /// Locations with no stock are absent.
  Future<Map<int, int>> stockedProductCounts();

  /// Changes a location's name and type. Allowed whatever the location holds:
  /// its stock stays where it is, and its QR code does not change (so a label
  /// already stuck on the shelf stays right). Throws [LocationException]
  /// (emptyName, unknownLocation).
  Future<StorageLocation> update(int id, {required String name, required LocationType type});

  /// Throws [LocationNotEmptyException] if the location still holds stock.
  /// Gives a type the shop made up a new name, on every location that has it.
  /// (Renaming to a name another type has joins the two.) Returns how many
  /// locations changed. Throws [LocationException] (emptyName, builtInType).
  Future<int> renameType(LocationType type, String newName);

  /// Deletes a type the shop made up: its locations become shelves. Nothing
  /// else changes (stock, QR codes). Returns how many locations were changed.
  /// Throws [LocationException] (builtInType).
  Future<int> deleteType(LocationType type);

  Future<void> delete(int id);
}

/// Read-only figures for the dashboard. Kept apart from the repositories that
/// change data (ISP): nothing here can alter stock or sales.
abstract class DashboardRepository {
  /// Totals of all bills from [from] up to (not including) [to].
  Future<DaySummary> summary(DateTime from, DateTime to);

  /// One entry for each of [days] days starting at the day of [from], oldest
  /// first. Days with no sales are included, as zeros.
  Future<List<DailyTotal>> dailyTotals(DateTime from, int days);

  /// The best-selling products by revenue from [from] up to (not including) [to].
  Future<List<ProductSales>> topProducts(DateTime from, DateTime to, {int limit = 5});

  /// What customers owe, over all days.
  Future<Receivables> receivables({int limit = 5});

  Future<InventoryHealth> inventoryHealth({int listLimit = 5});
}
