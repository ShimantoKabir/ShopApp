import '../domain/shop.dart';
import 'app_database.dart';

/// The shop's own facts, kept in one small table.
class SqliteShopRepository implements ShopRepository {
  static const _nameKey = 'name';
  final DatabaseProvider _database;
  SqliteShopRepository(this._database);

  @override
  Future<String?> name() async {
    final db = await _database.db;
    final rows = await db.query('shop_settings', where: 'key = ?', whereArgs: [_nameKey], limit: 1);
    final value = rows.isEmpty ? null : rows.first['value'] as String;
    return value == null || value.trim().isEmpty ? null : value;
  }

  @override
  Future<void> rename(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const ShopException(ShopProblem.emptyName);
    if (clean.length > maxShopNameLength) throw const ShopException(ShopProblem.nameTooLong);
    final db = await _database.db;
    final changed = await db.update('shop_settings', {'value': clean}, where: 'key = ?', whereArgs: [_nameKey]);
    if (changed == 0) await db.insert('shop_settings', {'key': _nameKey, 'value': clean});
  }
}
