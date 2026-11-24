import 'dart:convert';

import '../app_database.dart';
import 'op_envelope.dart';

/// The tables that make up the shop. (Not the note of sync progress: that
/// belongs to each phone.) Parents come before the tables that point at them.
const replicatedTables = [
  'categories',
  'locations',
  'products',
  'stock_placements',
  'stock_log',
  'customers',
  'bills',
  'sales',
  'payments',
  'payment_allocations',
  'users',
  'activity_log',
  'shop_settings',
];

/// A big entry is split so that none goes over the server's size limit.
const _chunkChars = 300000;

/// Everything this phone holds, as a series of log entries ("clear, then these
/// rows, then the id counters"). The first phone to share the shop sends them;
/// every other phone replays them to start from the same data.
Future<List<OpEnvelope>> buildSnapshot(AppDatabase database, int at) async {
  final db = await database.db;
  final entries = <OpEnvelope>[OpEnvelope(name: 'import.begin', args: const {}, at: at)];

  for (final table in replicatedTables) {
    final rows = await db.query(table, orderBy: 'rowid');
    var chunk = <Map<String, Object?>>[];
    var size = 0;
    void flush() {
      if (chunk.isEmpty) return;
      entries.add(OpEnvelope(name: 'import.rows', args: {'table': table, 'rows': chunk}, at: at));
      chunk = [];
      size = 0;
    }

    for (final row in rows) {
      chunk.add(Map.of(row));
      size += jsonEncode(row).length;
      if (size >= _chunkChars) flush();
    }
    flush();
  }

  // AUTOINCREMENT remembers the biggest id ever used, even after a delete. A
  // phone that did not live through the deletes must carry on from the same
  // number, or two phones would give different ids to the same new thing.
  final sequences = await db.rawQuery('SELECT name, seq FROM sqlite_sequence');
  entries.add(OpEnvelope(
    name: 'import.end',
    args: {
      'sequences': [
        for (final s in sequences) {'name': s['name'], 'seq': s['seq']},
      ],
    },
    at: at,
  ));
  return entries;
}
