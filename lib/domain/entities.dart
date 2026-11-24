import 'stock.dart';

/// Pure domain entities. No framework or database imports here.
class Category {
  final int? id;
  final String name;

  const Category({this.id, required this.name});
}

/// How a product is physically handled.
enum ProductKind {
  /// Sold by weight/length/piece from a bin: nails, screws, wire.
  loose,

  /// Counted pieces: hammer, screwdriver, paint cans, fittings.
  standard,

  /// Few units, high value, not shelf-sized: water pump, tank, machine.
  bulky,
}

/// What kind of place a location is. Four are built in; the shop can make up
/// more (e.g. "Cabinet", "Rack"). Stored and shared as its [name]; a custom
/// type is simply its own name, so no other phone needs setting up for it.
class LocationType {
  final String name;
  const LocationType._(this.name);

  static const shelf = LocationType._('shelf');
  static const floorArea = LocationType._('floorArea');
  static const storeroom = LocationType._('storeroom');
  static const yard = LocationType._('yard');
  static const builtIn = [shelf, floorArea, storeroom, yard];

  /// The type stored under [stored]: a built-in one, or else a custom one.
  /// Empty or missing means shelf.
  static LocationType parse(String? stored) {
    final clean = stored?.trim() ?? '';
    if (clean.isEmpty) return shelf;
    for (final t in builtIn) {
      if (t.name == clean) return t;
    }
    return LocationType._(clean);
  }

  /// A type made up by the shop. Its name must not be empty; one that spells a
  /// built-in name is that built-in type.
  factory LocationType.custom(String name) => parse(name);

  bool get isBuiltIn => builtIn.contains(this);

  /// All the types to offer: the built-in ones, then every custom one in use.
  static List<LocationType> offered(Iterable<StorageLocation> locations) {
    final custom = <LocationType>{for (final l in locations) if (!l.type.isBuiltIn) l.type};
    return [...builtIn, ...custom.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))];
  }

  @override
  bool operator ==(Object other) => other is LocationType && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => 'LocationType($name)';
}

class StorageLocation {
  final int? id;
  final String name;
  final LocationType type;

  /// Value encoded in the QR code. Stable and unique per location.
  final String code;

  const StorageLocation({this.id, required this.name, this.type = LocationType.shelf, required this.code});
}

class Product {
  final int? id;
  final String name;
  final ProductKind kind;
  final int? categoryId;

  /// Optional variant details (e.g. paint: brand + shade + pack size;
  /// machine part: model / part number; screw: size + material).
  final String brand;
  final String size;
  final String model;

  /// Colour, finish or material (e.g. red, brass, stainless steel).
  final String finish;

  final double purchasePrice;
  final double sellingPrice;

  /// Total stock across everywhere. [placements] say where part of it is kept.
  final double stock;
  final String unit;

  /// How the stock is spread over locations. May add up to less than [stock]
  /// (the rest is "not yet placed"), but never more.
  final List<StockPlacement> placements;

  const Product({
    this.id,
    required this.name,
    this.kind = ProductKind.standard,
    this.categoryId,
    this.brand = '',
    this.size = '',
    this.model = '',
    this.finish = '',
    required this.purchasePrice,
    required this.sellingPrice,
    required this.stock,
    required this.unit,
    this.placements = const [],
  });

  double get profitPerUnit => sellingPrice - purchasePrice;
  double get stockValueAtCost => purchasePrice * stock;

  /// Total quantity assigned to locations.
  double get placedQuantity => placements.fold(0.0, (sum, p) => sum + p.quantity);

  /// Stock that exists but has not been assigned to any location.
  double get unplacedQuantity {
    final rest = stock - placedQuantity;
    return rest < stockEpsilon ? 0 : rest;
  }

  /// Quantity kept at [locationId] (0 if none).
  double quantityAt(int? locationId) =>
      placements.where((p) => p.locationId == locationId).fold(0.0, (sum, p) => sum + p.quantity);

  /// Variant details that are filled in, in display order.
  List<String> get variantParts => [brand, size, model, finish].where((s) => s.isNotEmpty).toList();

  Product copyWith({
    int? id,
    String? name,
    ProductKind? kind,
    int? categoryId,
    String? brand,
    String? size,
    String? model,
    String? finish,
    double? purchasePrice,
    double? sellingPrice,
    double? stock,
    String? unit,
    List<StockPlacement>? placements,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      categoryId: categoryId ?? this.categoryId,
      brand: brand ?? this.brand,
      size: size ?? this.size,
      model: model ?? this.model,
      finish: finish ?? this.finish,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      placements: placements ?? this.placements,
    );
  }
}
