import 'dart:convert';

import '../../domain/activity.dart';
import '../../domain/entities.dart';
import '../../domain/sales.dart';
import '../../domain/users.dart';
import '../app_database.dart';

/// Writes the activity log: who did what, and when.
///
/// It is called right around a change to the shop's data, inside the same
/// database transaction, so an entry exists exactly when the change does, and
/// a refused change leaves nothing behind. Replaying the shared log on another
/// phone writes the same entries there, with the same person and time.
class ActivityRecorder {
  final DatabaseProvider _database;
  ActivityRecorder(this._database);

  Future<String?> _name(String table, Object? id, [String column = 'name']) async {
    if (id == null) return null;
    final db = await _database.db;
    final rows = await db.query(table, columns: [column], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first[column] as String?;
  }

  /// What must be looked up BEFORE the change (because the change removes or
  /// renames it).
  Future<Map<String, Object?>> before(String op, Map<String, dynamic> a) async {
    switch (op) {
      case 'product.delete':
      case 'product.adjustStock':
        return {'product': await _name('products', a['id'])};
      case 'stock.place':
      case 'stock.recount':
      case 'stock.restock':
        return {
          'product': await _name('products', a['productId']),
          'location': await _name('locations', a['locationId']),
        };
      case 'stock.move':
        return {
          'product': await _name('products', a['productId']),
          'from': await _name('locations', a['from']),
          'to': await _name('locations', a['to']),
        };
      case 'sale.void':
        final db = await _database.db;
        final rows = await db.rawQuery(
          'SELECT b.customer_name AS customer, COALESCE(SUM(s.quantity * s.unit_price), 0) AS total '
          'FROM bills b LEFT JOIN sales s ON s.bill_id = b.id WHERE b.id = ? GROUP BY b.id',
          [a['billId']],
        );
        return rows.isEmpty ? const {} : {'customer': rows.first['customer'], 'total': rows.first['total']};
      case 'payment.collect':
        return {'customer': await _name('customers', a['customerId'])};      case 'category.delete':
        return {'name': await _name('categories', a['id'])};
      case 'category.edit':
        return {'previous': await _name('categories', a['id'])};
      case 'location.delete':
        return {'name': await _name('locations', a['id'])};
      case 'location.edit':
        return {'previous': await _name('locations', a['id'])};
      case 'user.setPin':
      case 'user.updateProfile':
      case 'user.setActive':
        return {'name': await _name('users', a['userId'])};
      case 'shop.rename':
        final db = await _database.db;
        final rows = await db.query('shop_settings', where: 'key = ?', whereArgs: ['name'], limit: 1);
        return {'previous': rows.isEmpty ? null : rows.first['value']};
      default:
        return const {};
    }
  }

  /// Writes the entry for a change that has just succeeded. [result] is what
  /// the change returned.
  Future<void> after(
    String op,
    Map<String, dynamic> a,
    Map<String, Object?> before,
    Object? result, {
    required int at,
    required AppUser? actor,
  }) async {
    final String kind;
    final Map<String, Object?> detail;
    switch (op) {
      case 'product.save':
        final saved = result as Product;
        final isNew = (a['product'] as Map)['id'] == null;
        kind = isNew ? ActivityKind.productAdded : ActivityKind.productEdited;
        detail = {'product': saved.name, 'stock': saved.stock, 'unit': saved.unit};
      case 'product.delete':
        kind = ActivityKind.productDeleted;
        detail = {'product': before['product']};
      case 'product.adjustStock':
        kind = ActivityKind.stockAdjusted;
        detail = {'product': before['product'], 'total': a['newTotal']};
      case 'stock.place':
        kind = ActivityKind.stockPlaced;
        detail = {'product': before['product'], 'location': before['location'], 'quantity': a['quantity']};
      case 'stock.recount':
        kind = ActivityKind.stockCounted;
        detail = {'product': before['product'], 'location': before['location'], 'quantity': a['quantity']};
      case 'stock.move':
        kind = ActivityKind.stockMoved;
        detail = {'product': before['product'], 'from': before['from'], 'to': before['to'], 'quantity': a['quantity']};
      case 'stock.restock':
        kind = ActivityKind.restocked;
        detail = {'product': before['product'], 'location': before['location'], 'quantity': a['quantity']};
      case 'sale.checkout':
        final bill = result as Bill;
        kind = ActivityKind.sale;
        detail = {
          'billId': bill.id,
          'total': bill.total,
          'items': bill.lines.length,
          'customer': bill.customerName,
          'due': bill.due,
        };
      case 'sale.attachCustomer':
        final bill = result as Bill;
        kind = ActivityKind.customerAdded;
        detail = {
          'billId': bill.id,
          // The name if there is one, otherwise the number.
          'customer': bill.customerName.isNotEmpty
              ? bill.customerName
              : (bill.customerWhatsApp.isNotEmpty ? bill.customerWhatsApp : bill.customerMobile),
        };
      case 'sale.void':
        kind = ActivityKind.saleVoided;
        detail = {'billId': a['billId'], 'total': before['total'], 'customer': before['customer']};
      case 'payment.collect':
        kind = ActivityKind.paymentCollected;
        detail = {'amount': a['amount'], 'customer': before['customer']};
      case 'category.add':
        kind = ActivityKind.categoryAdded;
        detail = {'name': (result as Category).name};
      case 'category.edit':
        kind = ActivityKind.categoryEdited;
        detail = {'name': (result as Category).name, 'previous': before['previous']};
      case 'category.delete':
        kind = ActivityKind.categoryDeleted;
        detail = {'name': before['name']};
      case 'location.add':
        kind = ActivityKind.locationAdded;
        detail = {'name': (result as StorageLocation).name};
      case 'location.edit':
        kind = ActivityKind.locationEdited;
        detail = {'name': (result as StorageLocation).name, 'previous': before['previous']};
      case 'locationType.rename':
        kind = ActivityKind.locationTypeRenamed;
        detail = {'previous': a['from'], 'name': a['to'], 'count': result};
      case 'locationType.delete':
        kind = ActivityKind.locationTypeDeleted;
        detail = {'name': a['name'], 'count': result};
      case 'location.delete':
        kind = ActivityKind.locationDeleted;
        detail = {'name': before['name']};
      case 'user.create':
        final user = result as AppUser;
        kind = ActivityKind.userAdded;
        detail = {'name': user.name, 'role': user.role.name};
      case 'user.setPin':
        kind = ActivityKind.pinChanged;
        detail = {'name': before['name']};
      case 'user.updateProfile':
        kind = ActivityKind.profileUpdated;
        detail = {'name': (result as AppUser).name};
      case 'user.setActive':
        kind = ActivityKind.userSwitched;
        detail = {'name': before['name'], 'active': a['active']};
      case 'shop.rename':
        kind = ActivityKind.shopRenamed;
        detail = {'name': (a['name'] as String).trim(), 'previous': before['previous']};
      default:
        return; // not something people need to see (e.g. a shop upload)
    }
    await add(at: at, actor: actor, kind: kind, detail: detail);
  }

  /// Writes one entry.
  Future<void> add({
    required int at,
    required AppUser? actor,
    required String kind,
    Map<String, Object?> detail = const {},
  }) async {
    final db = await _database.db;
    await db.insert('activity_log', {
      'at': at,
      'user_id': actor?.id,
      'user_name': actor?.name ?? '',
      'kind': kind,
      'detail': jsonEncode(detail),
    });
  }
}
