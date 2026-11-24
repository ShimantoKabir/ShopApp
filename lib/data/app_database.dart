import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'starter_categories.dart';

/// What repositories need from the database layer (DIP).
abstract class DatabaseProvider {
  Future<Database> get db;
}

/// Owns the SQLite connection and schema (with migrations).
///
/// Schema history:
///  v1: categories, shelves, products
///  v2: shelves -> typed locations; products gain kind, brand, size, color
///  v3: products gain model; color -> finish; starter categories
///  v4: stock can be spread over many locations (stock_placements) with a
///      history log (stock_log). products.location_id is retired: fresh
///      installs do not have it, upgraded databases keep it unused.
///  v5: sales (one row per sale, with the price and cost at that moment)
///  v6: bills group sales into one customer purchase; customers; due payments
///  v7: customers and bills carry an address and a WhatsApp number
///  v8: payments (money received against dues) and which bills they paid
///  v9: users (login); bills, stock history and payments record who did them
///  v10: users keep their own mobile, phone and address
///  v11: sync_state (how far this phone has read the shared log; never shared)
///  v12: activity_log (who did what; shared like the rest of the shop)
///  v13: shop_settings (the shop's name; shared)
class AppDatabase implements DatabaseProvider {
  static const _version = 13;

  /// The database file name. Only tests use anything but the default, so that
  /// test files running in parallel never share (and clobber) one file.
  final String fileName;
  Database? _db;

  AppDatabase({this.fileName = 'hardware_shop.db'});

  @override
  Future<Database> get db async => _db ??= await _open();

  /// Deletes everything the shop has stored on this phone (every table, and the
  /// numbering of ids) and puts back the starting categories, as on a new
  /// install. The tables themselves stay.
  Future<void> erase() async {
    final d = await db;
    // Foreign keys off so tables can be emptied in any order.
    await d.execute('PRAGMA foreign_keys = OFF');
    try {
      await d.transaction((txn) async {
        final tables = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'");
        for (final t in tables) {
          await txn.delete(t['name'] as String);
        }
        await txn.execute('DELETE FROM sqlite_sequence');
        await _seedStarterCategories(txn);
      });
    } finally {
      await d.execute('PRAGMA foreign_keys = ON');
    }
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: _version,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )''');
        await d.execute('''
          CREATE TABLE locations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'shelf',
            code TEXT NOT NULL UNIQUE
          )''');
        await d.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'standard',
            category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
            brand TEXT NOT NULL DEFAULT '',
            size TEXT NOT NULL DEFAULT '',
            model TEXT NOT NULL DEFAULT '',
            finish TEXT NOT NULL DEFAULT '',
            purchase_price REAL NOT NULL,
            selling_price REAL NOT NULL,
            stock REAL NOT NULL,
            unit TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await d.execute('CREATE INDEX idx_products_name ON products(name)');
        await d.execute('CREATE INDEX idx_products_category ON products(category_id)');
        await _createStockTables(d);
        await _createBillingTables(d);
        await _createSalesTable(d);
        await _createPaymentTables(d);
        await _createUsersTable(d);
        await _createSyncStateTable(d);
        await _createActivityTable(d);
        await _createShopSettingsTable(d);
        await _seedStarterCategories(d);
      },
      onUpgrade: (d, oldVersion, _) async {
        if (oldVersion < 2) {
          await d.execute('ALTER TABLE shelves RENAME TO locations');
          await d.execute("ALTER TABLE locations ADD COLUMN type TEXT NOT NULL DEFAULT 'shelf'");
          await d.execute('ALTER TABLE products RENAME COLUMN shelf_id TO location_id');
          await d.execute("ALTER TABLE products ADD COLUMN kind TEXT NOT NULL DEFAULT 'standard'");
          await d.execute("ALTER TABLE products ADD COLUMN brand TEXT NOT NULL DEFAULT ''");
          await d.execute("ALTER TABLE products ADD COLUMN size TEXT NOT NULL DEFAULT ''");
          await d.execute("ALTER TABLE products ADD COLUMN color TEXT NOT NULL DEFAULT ''");
          await d.execute('DROP INDEX IF EXISTS idx_products_shelf');
          await d.execute('CREATE INDEX idx_products_location ON products(location_id)');
        }
        if (oldVersion < 3) {
          await d.execute("ALTER TABLE products ADD COLUMN model TEXT NOT NULL DEFAULT ''");
          await d.execute('ALTER TABLE products RENAME COLUMN color TO finish');
          // Only seed a database that has no categories at all, so we never
          // add back categories someone deliberately deleted.
          final count = Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM categories')) ?? 0;
          if (count == 0) await _seedStarterCategories(d);
        }
        if (oldVersion < 4) {
          await _createStockTables(d);
          // v3 allowed exactly one location per product; carry that over as a
          // placement of the whole stock. A product with no stock has nothing
          // to place, so it simply has no placement.
          await d.execute('''
            INSERT INTO stock_placements(product_id, location_id, quantity)
            SELECT id, location_id, stock FROM products
            WHERE location_id IS NOT NULL AND stock > 0''');
        }
        if (oldVersion < 5) {
          await _createBillingTables(d);
          await _createSalesTable(d);
        } else if (oldVersion < 6) {
          await _createBillingTables(d);
          await _addBillsToExistingSales(d);
        } else if (oldVersion < 7) {
          // Older bills and customers have no address or WhatsApp number; the
          // new rule applies to new sales only.
          await d.execute("ALTER TABLE customers ADD COLUMN address TEXT NOT NULL DEFAULT ''");
          await d.execute("ALTER TABLE customers ADD COLUMN whatsapp TEXT NOT NULL DEFAULT ''");
          await d.execute('CREATE INDEX idx_customers_whatsapp ON customers(whatsapp)');
          await d.execute("ALTER TABLE bills ADD COLUMN customer_address TEXT NOT NULL DEFAULT ''");
          await d.execute("ALTER TABLE bills ADD COLUMN customer_whatsapp TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 8) await _createPaymentTables(d);
        if (oldVersion < 9) {
          await _createUsersTable(d);
          // Older rows simply have no name against them.
          for (final table in ['bills', 'stock_log', 'payments']) {
            await _addColumnIfMissing(d, table, 'user_id', 'INTEGER');
            await _addColumnIfMissing(d, table, 'user_name', "TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 10) {
          for (final column in ['mobile', 'phone', 'address']) {
            await _addColumnIfMissing(d, 'users', column, "TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 11) await _createSyncStateTable(d);
        if (oldVersion < 12) await _createActivityTable(d);
        if (oldVersion < 13) await _createShopSettingsTable(d);
      },
    );
  }

  /// A payment is money received from a customer. Its allocations say which
  /// bills it paid off (bills.paid is raised by the same amounts), so that
  /// cancelling a bill can take back what was collected on it.
  Future<void> _createPaymentTables(Database d) async {
    await d.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
        amount REAL NOT NULL,
        user_id INTEGER,
        user_name TEXT NOT NULL DEFAULT '',
        at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_payments_customer ON payments(customer_id, at)');
    await d.execute('CREATE INDEX idx_payments_at ON payments(at)');
    await d.execute('''
      CREATE TABLE payment_allocations(
        payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
        bill_id INTEGER NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
        amount REAL NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_allocations_bill ON payment_allocations(bill_id)');
  }

  /// People who can sign in. user_id on bills/stock history/payments has no
  /// foreign key on purpose: what someone did must outlive them.
  Future<void> _createUsersTable(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        role TEXT NOT NULL DEFAULT 'staff',
        pin_salt TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        mobile TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
  }

  /// Facts about the shop itself (its name...). Shared like the rest of the shop.
  Future<void> _createShopSettingsTable(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS shop_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  /// Who did what and when. user_name is copied in, and there is no foreign key
  /// to users: the record must outlive anyone who leaves.
  Future<void> _createActivityTable(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS activity_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at INTEGER NOT NULL,
        user_id INTEGER,
        user_name TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT '{}'
      )''');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_activity_at ON activity_log(at)');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_activity_user ON activity_log(user_id, at)');
  }

  /// Notes this phone keeps about sharing (like how far it has read the log).
  /// Not part of the shop's data, so never uploaded or replaced.
  Future<void> _createSyncStateTable(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS sync_state(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  Future<void> _addColumnIfMissing(Database d, String table, String column, String definition) async {
    final columns = await d.rawQuery('PRAGMA table_info($table)');
    if (columns.any((c) => c['name'] == column)) return;
    await d.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _createStockTables(Database d) async {
    await d.execute('''
      CREATE TABLE stock_placements(
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        location_id INTEGER NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
        quantity REAL NOT NULL,
        PRIMARY KEY(product_id, location_id)
      )''');
    await d.execute('CREATE INDEX idx_placements_location ON stock_placements(location_id)');
    await d.execute('''
      CREATE TABLE stock_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
        delta REAL NOT NULL,
        reason TEXT NOT NULL,
        user_id INTEGER,
        user_name TEXT NOT NULL DEFAULT '',
        at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_stock_log_product ON stock_log(product_id, at)');
  }

  Future<void> _createBillingTables(Database d) async {
    await d.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT '',
        mobile TEXT NOT NULL DEFAULT '',
        nid TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        whatsapp TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_customers_mobile ON customers(mobile)');
    await d.execute('CREATE INDEX idx_customers_whatsapp ON customers(whatsapp)');
    // customer_name/mobile are copied so a receipt never changes after the fact.
    // The NID is only kept on the customer record, never on a bill.
    await d.execute('''
      CREATE TABLE bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
        customer_name TEXT NOT NULL DEFAULT '',
        customer_mobile TEXT NOT NULL DEFAULT '',
        customer_address TEXT NOT NULL DEFAULT '',
        customer_whatsapp TEXT NOT NULL DEFAULT '',
        user_id INTEGER,
        user_name TEXT NOT NULL DEFAULT '',
        paid REAL NOT NULL,
        at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_bills_at ON bills(at)');
  }

  Future<void> _createSalesTable(Database d) async {
    // product_name/unit are copied so history survives deleting the product.
    await d.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_id INTEGER REFERENCES bills(id) ON DELETE CASCADE,
        product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        location_id INTEGER REFERENCES locations(id) ON DELETE SET NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL,
        at INTEGER NOT NULL
      )''');
    await d.execute('CREATE INDEX idx_sales_at ON sales(at)');
    await d.execute('CREATE INDEX idx_sales_bill ON sales(bill_id)');
  }

  /// v5 had one row per sale with no bill. Give each existing sale its own
  /// bill (paid in full, no customer) so every sale belongs to a bill.
  Future<void> _addBillsToExistingSales(Database d) async {
    await d.execute('ALTER TABLE sales ADD COLUMN bill_id INTEGER REFERENCES bills(id) ON DELETE CASCADE');
    await d.execute('CREATE INDEX idx_sales_bill ON sales(bill_id)');
    final rows = await d.query('sales', columns: ['id', 'quantity', 'unit_price', 'at']);
    for (final r in rows) {
      final total = (r['quantity'] as num).toDouble() * (r['unit_price'] as num).toDouble();
      final billId = await d.insert('bills', {'paid': total, 'at': r['at']});
      await d.update('sales', {'bill_id': billId}, where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  Future<void> _seedStarterCategories(DatabaseExecutor d) async {
    final batch = d.batch();
    for (final name in starterCategories) {
      batch.insert('categories', {'name': name}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }
}
