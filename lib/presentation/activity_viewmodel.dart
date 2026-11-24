import 'package:flutter/foundation.dart';

import '../core/bangla.dart';
import '../domain/activity.dart';
import '../domain/repositories.dart';
import '../domain/services.dart';
import '../domain/sync.dart';
import '../domain/users.dart';

/// The activity log: who did what, newest first. Anyone signed in can look.
class ActivityViewModel extends ChangeNotifier {
  static const pageSize = 100;

  final ActivityRepository _activity;
  final UserRepository _users;
  final Clock _clock;
  final SyncService? _sync;

  ActivityViewModel(this._activity, this._users, this._clock, [this._sync]);

  List<ActivityEntry> entries = [];

  /// Everyone who can be picked (including people who have left: what they did
  /// is still on record).
  List<AppUser> people = [];

  int? userId;
  ActivityGroup group = ActivityGroup.all;
  bool loading = true;
  int _limit = pageSize;

  /// There may be older entries than the ones shown.
  bool get hasMore => entries.length >= _limit;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    people = await _users.all();
    entries = await _activity.recent(limit: _limit, userId: userId, group: group);
    loading = false;
    notifyListeners();
  }

  /// Pull to refresh: first fetch what other phones did, then show it.
  Future<void> refresh() async {
    await _sync?.syncNow();
    await load();
  }

  Future<void> setPerson(int? id) {
    userId = id;
    _limit = pageSize;
    return load();
  }

  Future<void> setGroup(ActivityGroup chosen) {
    group = chosen;
    _limit = pageSize;
    return load();
  }

  Future<void> showMore() {
    _limit += pageSize;
    return load();
  }

  /// "আজ", "গতকাল" or the date: the heading above a day's entries.
  String dayHeading(DateTime at) => dayLabel(at, _clock.now());

  /// Whether [a] and [b] are on the same calendar day.
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}
