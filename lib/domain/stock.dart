/// Quantities below this are treated as zero (guards double rounding).
const stockEpsilon = 1e-9;

/// How much of a product sits at one location.
class StockPlacement {
  final int locationId;
  final double quantity;
  const StockPlacement({required this.locationId, required this.quantity});
}

/// Why a quantity changed. Shown in the history list.
enum StockReason {
  /// Product created with stock.
  initial,

  /// Total stock edited on the product form or list.
  edit,

  /// Part of the stock was assigned to / removed from a location.
  place,

  /// Stock moved from one location to another (two entries).
  move,

  /// A shelf was counted and the real quantity differed.
  count,

  /// New goods arrived (restock).
  restock,

  /// Units were sold.
  sale,

  /// A sale was cancelled and its units returned to stock.
  saleVoid,
}

class StockLogEntry {
  final int? id;
  final int productId;

  /// Null when the change was to the product total, not a specific location.
  final int? locationId;

  /// Positive = added, negative = removed (at that location, or in total).
  final double delta;
  final StockReason reason;
  final DateTime at;

  /// Who made the change. Empty on old entries.
  final String userName;

  const StockLogEntry({
    this.id,
    required this.productId,
    this.locationId,
    required this.delta,
    required this.reason,
    required this.at,
    this.userName = '',
  });
}

enum StockProblem {
  /// New total is less than what is already placed at locations.
  belowPlaced,

  /// Placing more than the product's total stock.
  exceedsStock,

  /// Moving more than the source location holds.
  notEnoughAtSource,

  /// Zero, negative or otherwise unusable quantity.
  invalidQuantity,

  /// Moving stock to the same location it is already in.
  sameLocation,

  /// Selling more than is in stock.
  insufficientStock,
}

/// A stock rule was broken. Carries a machine-readable [problem] so the UI can
/// show a message in the user's language.
class StockException implements Exception {
  final StockProblem problem;
  const StockException(this.problem);

  @override
  String toString() => 'StockException($problem)';
}

enum CategoryProblem {
  /// The name is empty (or only spaces).
  emptyName,

  /// There is no such category (e.g. it was deleted on another phone).
  unknownCategory,

  /// Another category already has that name.
  nameTaken,
}

/// A rule about a category was broken; nothing changed.
class CategoryException implements Exception {
  final CategoryProblem problem;
  const CategoryException(this.problem);

  @override
  String toString() => 'CategoryException($problem)';
}

enum LocationProblem {
  /// The name is empty (or only spaces).
  emptyName,

  /// There is no such location (e.g. it was deleted on another phone).
  unknownLocation,

  /// The four built-in types (shelf, floor, storeroom, yard) cannot be renamed or deleted.
  builtInType,
}

/// A rule about a location was broken; nothing changed.
class LocationException implements Exception {
  final LocationProblem problem;
  const LocationException(this.problem);

  @override
  String toString() => 'LocationException($problem)';
}

/// A location cannot be deleted while it still holds stock.
class LocationNotEmptyException implements Exception {
  final int productCount;
  const LocationNotEmptyException(this.productCount);

  @override
  String toString() => 'LocationNotEmptyException($productCount products)';
}
