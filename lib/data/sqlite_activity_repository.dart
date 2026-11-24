import 'dart:convert';

import '../domain/activity.dart';
import '../domain/sync.dart';
import '../domain/users.dart';
import 'app_database.dart';
import 'sync/activity_recorder.dart';

/// Reads the activity log from this phone's own copy of the shop.
class SqliteActivityRepository implements ActivityRepository {
  final DatabaseProvider _database;
  SqliteActivityRepository(this._database);

  @override
  Future<List<ActivityEntry>> recent({int limit = 100, int? userId, ActivityGroup group = ActivityGroup.all}) async {
    final db = await _database.db;
    final where = <String>[];
    final args = <Object?>[];
    if (userId != null) {
      where.add('user_id = ?');
      args.add(userId);
    }
    final kinds = group.kinds;
    if (kinds.isNotEmpty) {
      where.add('kind IN (${List.filled(kinds.length, '?').join(',')})');
      args.addAll(kinds);
    }
    final rows = await db.query(
      'activity_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    return [
      for (final r in rows)
        ActivityEntry(
          id: r['id'] as int,
          at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int),
          userId: r['user_id'] as int?,
          userName: r['user_name'] as String? ?? '',
          kind: r['kind'] as String,
          detail: _detail(r['detail'] as String?),
        ),
    ];
  }

  Map<String, dynamic> _detail(String? text) {
    if (text == null || text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } on FormatException {
      return const {};
    }
  }
}

/// Notes sign-ins in the activity log. When the shop is shared the note is
/// sent like any other change (so everyone sees it); with no connection it is
/// simply not made. Signing in never waits for it.
class GatewayActivityNotifier implements ActivityNotifier {
  final WriteGateway _gateway;
  final ActivityRecorder _recorder;
  final int Function() _now;
  GatewayActivityNotifier(this._gateway, this._recorder, this._now);

  @override
  void signedIn(AppUser user) {
    // Deliberately not awaited, and every failure is swallowed.
    _gateway.write<void>(
      'activity.signedIn',
      const {},
      () => _recorder.add(at: _now(), actor: user, kind: ActivityKind.signIn),
    ).catchError((Object _) {});
  }
}
