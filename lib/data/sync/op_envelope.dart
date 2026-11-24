import 'dart:convert';

import '../../domain/entities.dart';
import '../../domain/sales.dart';
import '../../domain/stock.dart';

/// The newest kind of entry this version of the app understands. An entry
/// from a newer version is refused (the app must be updated) rather than
/// guessed at.
const opVersion = 1;

/// One change to the shop's data, as written in the shared log.
///
/// It carries everything that could differ between phones (the time, who did
/// it, any random values) so that every phone, replaying it, gets the same
/// result.
class OpEnvelope {
  final int v;
  final String name;
  final Map<String, dynamic> args;

  /// When it happened, in milliseconds.
  final int at;

  /// Who did it (null before anyone is signed in, e.g. creating the owner).
  final ({int id, String name})? actor;

  const OpEnvelope({this.v = opVersion, required this.name, required this.args, required this.at, this.actor});

  String encode() => jsonEncode({
        'v': v,
        'op': name,
        'args': args,
        'at': at,
        if (actor != null) 'actor': {'id': actor!.id, 'name': actor!.name},
      });

  /// Throws [FormatException] for anything that is not a well-formed entry.
  static OpEnvelope decode(String text) {
    final map = jsonDecode(text);
    if (map is! Map<String, dynamic>) throw const FormatException('not an object');
    final actor = map['actor'];
    return OpEnvelope(
      v: map['v'] as int,
      name: map['op'] as String,
      args: (map['args'] as Map).cast<String, dynamic>(),
      at: map['at'] as int,
      actor: actor is Map ? (id: actor['id'] as int, name: actor['name'] as String) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// How the shop's own types are written into an entry and read back.
// ---------------------------------------------------------------------------

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

double _d(Object? v) => (v as num).toDouble();

Map<String, Object?> productToJson(Product p) => {
      'id': p.id,
      'name': p.name,
      'kind': p.kind.name,
      'categoryId': p.categoryId,
      'brand': p.brand,
      'size': p.size,
      'model': p.model,
      'finish': p.finish,
      'purchasePrice': p.purchasePrice,
      'sellingPrice': p.sellingPrice,
      'stock': p.stock,
      'unit': p.unit,
      'placements': [
        for (final x in p.placements) {'locationId': x.locationId, 'quantity': x.quantity},
      ],
    };

Product productFromJson(Map<String, dynamic> j) => Product(
      id: j['id'] as int?,
      name: j['name'] as String,
      kind: _enum(ProductKind.values, j['kind'], ProductKind.standard),
      categoryId: j['categoryId'] as int?,
      brand: j['brand'] as String? ?? '',
      size: j['size'] as String? ?? '',
      model: j['model'] as String? ?? '',
      finish: j['finish'] as String? ?? '',
      purchasePrice: _d(j['purchasePrice']),
      sellingPrice: _d(j['sellingPrice']),
      stock: _d(j['stock']),
      unit: j['unit'] as String,
      placements: [
        for (final x in (j['placements'] as List? ?? const []))
          StockPlacement(locationId: (x as Map)['locationId'] as int, quantity: _d(x['quantity'])),
      ],
    );

Map<String, Object?> saleLineToJson(SaleLine l) => {
      'productId': l.productId,
      'quantity': l.quantity,
      'unitPrice': l.unitPrice,
      'fromLocationId': l.fromLocationId,
    };

SaleLine saleLineFromJson(Map<String, dynamic> j) => SaleLine(
      productId: j['productId'] as int,
      quantity: _d(j['quantity']),
      unitPrice: _d(j['unitPrice']),
      fromLocationId: j['fromLocationId'] as int?,
    );

Map<String, Object?>? customerToJson(CustomerInfo? c) => c == null
    ? null
    : {'name': c.name, 'mobile': c.mobile, 'nid': c.nid, 'address': c.address, 'whatsapp': c.whatsapp};

CustomerInfo? customerFromJson(Map<String, dynamic>? j) => j == null
    ? null
    : CustomerInfo(
        name: j['name'] as String? ?? '',
        mobile: j['mobile'] as String? ?? '',
        nid: j['nid'] as String? ?? '',
        address: j['address'] as String? ?? '',
        whatsapp: j['whatsapp'] as String? ?? '',
      );
