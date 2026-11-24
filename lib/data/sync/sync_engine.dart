import 'dart:async';
import 'dart:math';

import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../domain/services.dart';
import '../../domain/settings.dart';
import '../../domain/sync.dart';
import '../../domain/users.dart';
import '../app_database.dart';
import 'activity_recorder.dart';
import 'op_envelope.dart';
import 'op_handlers.dart';
import 'snapshot.dart';

/// Shares the shop between phones.
///
/// While the shop is shared, every change is added to a log kept on the
/// server, then every phone (this one too) replays the log, in order, into its
/// own copy of the data. So all phones agree, and the shop's rules run the same
/// way everywhere: if two people sell the last item at the same moment, the
/// log puts one first, and the other sale is refused on every phone.
///
/// Reading uses this phone's own copy and works with no signal. Changing
/// needs a connection (so that everyone's stock is the same).
class SyncEngine implements SyncService, WriteGateway, DataEraser {
  static const _urlKey = 'sync.url';
  static const _keyKey = 'sync.key';
  static const _deviceKey = 'sync.device';
  static const _appliedKey = 'applied_seq';
  static const _pageSize = 100;
  static const _eraseOp = 'shop.erase';

  final AppDatabase _database;
  final SettingsStore _settings;
  final SyncTransportFactory _transportFactory;
  final Clock _clock;
  final CurrentUser _actor;
  final OpHandlers _handlers;
  final ActivityRecorder _activity;
  final Future<void> Function(Duration) _pause;
  final String Function() _newId;

  @override
  final String defaultUrl;

  SyncConfig? _config;
  SyncTransport? _transport;
  String _deviceId = '';
  int _applied = 0;
  SyncState _state = SyncState.off;
  String? _detail;
  DateTime? _lastSynced;
  Timer? _timer;
  final _changes = StreamController<void>.broadcast();
  final _erased = StreamController<void>.broadcast();
  final _pending = <String, Completer<Object?>>{};
  Future<void> _tail = Future.value();

  SyncEngine({
    required AppDatabase database,
    required this._settings,
    required this._transportFactory,
    required this._clock,
    required this._actor,
    this.defaultUrl = '',
    Future<void> Function(Duration)? pause,
    String Function()? newId,
  })  : _database = database,
        _handlers = OpHandlers(database),
        _activity = ActivityRecorder(database),
        _pause = pause ?? Future.delayed,
        _newId = newId ?? _randomId;

  static String _randomId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  // ---- what the screens see ---------------------------------------------

  @override
  SyncState get state => _state;
  @override
  String? get detail => _detail;
  @override
  DateTime? get lastSynced => _lastSynced;
  @override
  bool get enabled => _config != null;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Stream<void> get erased => _erased.stream;

  /// How far this phone has read the log (for tests and diagnostics).
  int get appliedSeq => _applied;

  /// Entries this phone read but skipped because a rule said no (every phone
  /// skips them the same way). Kept for diagnostics.
  final List<({int seq, String operation, Object error})> skipped = [];
  String get deviceId => _deviceId;

  void _set(SyncState state, [String? detail]) {
    _state = state;
    _detail = detail;
    if (!_changes.isClosed) _changes.add(null);
  }

  // ---- starting up -------------------------------------------------------

  /// Reads what this phone remembers: whether it is part of a shared shop, and
  /// how far it has read.
  Future<void> load() async {
    var device = await _settings.read(_deviceKey);
    if (device == null || device.isEmpty) {
      device = _newId();
      await _settings.write(_deviceKey, device);
    }
    _deviceId = device;
    _applied = int.tryParse(await _handlers.replay.getState(_appliedKey) ?? '') ?? 0;

    final url = await _settings.read(_urlKey);
    final key = await _settings.read(_keyKey);
    if (url != null && url.isNotEmpty && key != null && key.isNotEmpty) {
      _useConfig(SyncConfig(url: url, key: key));
      _set(SyncState.idle);
    } else {
      _config = null;
      _transport = null;
      _set(SyncState.off);
    }
  }

  void _useConfig(SyncConfig config) {
    _config = config;
    _transport = _transportFactory(config);
  }

  /// Syncs now and then, while the app is open.
  void startAutoSync({Duration every = const Duration(seconds: 20)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => syncNow());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _changes.close();
    await _erased.close();
  }

  // ---- connecting --------------------------------------------------------

  @override
  Future<void> connect({required String url, required String key}) async {
    var cleanUrl = url.trim();
    final cleanKey = key.trim();
    if (cleanUrl.endsWith('/')) cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty || cleanKey.isEmpty) {
      throw const SyncException(SyncProblem.badSettings);
    }
    final config = SyncConfig(url: cleanUrl, key: cleanKey);
    await _transportFactory(config).head(); // throws if it cannot be reached or the key is wrong
    await _settings.write(_urlKey, cleanUrl);
    await _settings.write(_keyKey, cleanKey);
    _useConfig(config);
    _set(SyncState.idle);
  }

  SyncTransport get _need => _transport ?? (throw const SyncException(SyncProblem.notConnected));

  // ---- joining and sharing ----------------------------------------------

  @override
  Future<void> join() => _exclusive(() async {
        final transport = _need;
        // Only a phone with no shop of its own may join one: replaying another
        // shop's log over existing data would mix the two.
        // (A phone that has already started joining may simply carry on, e.g.
        // after losing the signal part-way.)
        if (_applied == 0) {
          final db = await _database.db;
          final users = (await db.rawQuery('SELECT COUNT(*) AS n FROM users')).first['n'] as int;
          if (users > 0) throw const SyncException(SyncProblem.notFresh);
          if (await _guard(transport.head) == 0 || await _logHoldsOnlyErase(transport)) {
            throw const SyncException(SyncProblem.nothingToJoin);
          }
        }
        await _pullLocked();
      });

  @override
  Future<void> shareThisPhone() => _exclusive(() async {
        final transport = _need;
        // Allowed when nothing is shared yet, or when the only thing in the log
        // is an earlier upload from this very phone that did not finish (a new
        // full upload then simply replaces it on every phone).
        final before = await _guard(transport.head);
        if (before != 0 && !await _onlyMyUnfinishedUpload(transport)) {
          throw const SyncException(SyncProblem.alreadyShared);
        }
        final entries = await buildSnapshot(_database, _clock.now().millisecondsSinceEpoch);
        _set(SyncState.syncing);
        var last = before;
        for (var i = 0; i < entries.length; i++) {
          final seq = await _guard(() => transport.append(
                opId: _newId(),
                device: _deviceId,
                at: entries[i].at,
                payload: entries[i].encode(),
              ));
          // If someone else got in between, the numbers will not run on.
          if (seq != last + 1) {
            _set(SyncState.failed, 'The shop was changed from another phone while uploading.');
            throw const SyncException(SyncProblem.alreadyShared);
          }
          last = seq;
        }
        // This phone already holds this data, so it must not replay it.
        await _handlers.replay.setState(_appliedKey, '$last');
        _applied = last;
        _lastSynced = _clock.now();
        _set(SyncState.idle);
      });

  /// True if every entry in the log is part of an upload from this phone and
  /// that upload never reached its end.
  Future<bool> _onlyMyUnfinishedUpload(SyncTransport transport) async {
    var after = 0;
    while (true) {
      final page = await _guard(() => transport.fetch(after, limit: _pageSize));
      for (final op in page.ops) {
        final String name;
        try {
          name = OpEnvelope.decode(op.payload).name;
        } on Object {
          return false;
        }
        if (name == _eraseOp) {
          after = op.seq; // the shop was erased before; whoever did it
          continue;
        }
        if (op.device != _deviceId) return false;
        if (!name.startsWith('import.') || name == 'import.end') return false;
        after = op.seq;
      }
      if (page.ops.isEmpty || after >= page.head) return true;
    }
  }

  /// True if the log holds nothing but "the shop was erased" notices.
  Future<bool> _logHoldsOnlyErase(SyncTransport transport) async {
    var after = 0;
    while (true) {
      final page = await _guard(() => transport.fetch(after, limit: _pageSize));
      for (final op in page.ops) {
        try {
          if (OpEnvelope.decode(op.payload).name != _eraseOp) return false;
        } on Object {
          return false;
        }
        after = op.seq;
      }
      if (page.ops.isEmpty || after >= page.head) return true;
    }
  }

  @override
  Future<void> disconnect() async {
    await _settings.write(_urlKey, '');
    await _settings.write(_keyKey, '');
    _config = null;
    _transport = null;
    _set(SyncState.off);
  }

  // ---- reading the log ---------------------------------------------------

  @override
  Future<void> syncNow() async {
    if (!enabled) return;
    try {
      await _exclusive(_pullLocked);
    } catch (_) {
      // The state already says what went wrong.
    }
  }

  /// Runs [call] and turns what goes wrong into the state shown to people.
  Future<R> _guard<R>(Future<R> Function() call) async {
    try {
      return await call();
    } on SyncException catch (e) {
      switch (e.problem) {
        case SyncProblem.offline:
          _set(SyncState.offline);
        case SyncProblem.unauthorized:
          _set(SyncState.rejected);
        case SyncProblem.unsupported:
          _set(SyncState.needsUpdate);
        default:
          _set(SyncState.failed, e.problem.name);
      }
      rethrow;
    }
  }

  Future<void> _pullLocked() async {
    final transport = _need;
    _set(SyncState.syncing);
    try {
      while (true) {
        final page = await _guard(() => transport.fetch(_applied, limit: _pageSize));
        for (final op in page.ops) {
          await _apply(op);
          if (!enabled) return; // erased: this phone is on its own again
        }
        if (page.ops.isEmpty || _applied >= page.head) break;
      }
    } on SyncException {
      rethrow; // _guard has set the state
    } catch (e) {
      _set(SyncState.failed, '$e');
      throw const SyncException(SyncProblem.failed);
    }
    _lastSynced = _clock.now();
    _set(SyncState.idle);
  }

  /// Replays one entry. The entry's effects and the note "read up to here"
  /// are written in a single transaction, so a crash can never leave an entry
  /// applied twice or skipped.
  Future<void> _apply(RemoteOp op) async {
    if (op.seq <= _applied) return;

    OpEnvelope entry;
    try {
      entry = OpEnvelope.decode(op.payload);
    } on Object {
      _set(SyncState.needsUpdate);
      throw const SyncException(SyncProblem.unsupported);
    }
    if (entry.name == _eraseOp) {
      await _applyErase(op);
      return;
    }
    if (entry.v > opVersion || !_handlers.handles(entry.name)) {
      _set(SyncState.needsUpdate);
      throw const SyncException(SyncProblem.unsupported);
    }

    Object? result;
    Object? error;
    StackTrace? stack;
    try {
      result = await _handlers.replay.inTransaction(() async {
        final value = await _handlers.run(entry);
        await _handlers.replay.setState(_appliedKey, '${op.seq}');
        return value;
      });
    } catch (e, s) {
      // A rule said no (not enough stock, wrong PIN...). Every phone gets the
      // same answer, so every phone skips this entry the same way. The
      // person who made it is told.
      if (_isTransient(e)) rethrow;
      // A piece of the shop's starting data must never be dropped quietly: a
      // shop with part of its data missing is worse than one that says so.
      if (entry.name.startsWith('import.')) {
        throw StateError('could not read ${entry.name} (entry ${op.seq}): $e');
      }
      error = e;
      stack = s;
      skipped.add((seq: op.seq, operation: entry.name, error: e));
      await _handlers.replay.setState(_appliedKey, '${op.seq}');
    }
    _applied = op.seq;

    final waiting = _pending.remove(op.opId);
    if (waiting != null && !waiting.isCompleted) {
      error != null ? waiting.completeError(error, stack) : waiting.complete(result);
    }
  }

  /// The owner erased the shop. A phone that has been reading this shop is
  /// emptied and goes back to working on its own; a phone that has not read
  /// anything yet (it is only now joining a shop made after the erase) just
  /// steps over the notice.
  Future<void> _applyErase(RemoteOp op) async {
    if (_applied == 0) {
      await _handlers.replay.setState(_appliedKey, '${op.seq}');
      _applied = op.seq;
      return;
    }
    await _wipeThisPhone();
  }

  /// Empties this phone and disconnects it. Its device id (and the theme and
  /// language) are kept.
  Future<void> _wipeThisPhone() async {
    await _database.erase();
    _applied = 0;
    _lastSynced = null;
    skipped.clear();
    await _settings.write(_urlKey, '');
    await _settings.write(_keyKey, '');
    _config = null;
    _transport = null;
    _set(SyncState.off);
    if (!_erased.isClosed) _erased.add(null);
  }

  @override
  Future<void> eraseEverything() => _exclusive(() async {
        final person = _actor.user;
        if (person == null || !person.isOwner) throw const SyncException(SyncProblem.notOwner);
        if (enabled) {
          // The shared database first: if that cannot be reached, nothing is erased.
          final notice = OpEnvelope(
            name: _eraseOp,
            args: const {},
            at: _clock.now().millisecondsSinceEpoch,
            actor: (id: person.id, name: person.name),
          );
          await _guard(() => _need.erase(opId: _newId(), device: _deviceId, at: notice.at, payload: notice.encode()));
        }
        await _wipeThisPhone();
      });

  /// Trouble that might not happen again (so the entry is retried later),
  /// as opposed to a rule being broken (which always will).
  bool _isTransient(Object e) {
    if (e is! DatabaseException) return false;
    final message = e.toString().toLowerCase();
    return [
      'database is locked',
      'database table is locked',
      'database is closed',
      'disk i/o error',
      'database or disk is full',
      'attempt to write a readonly database',
      'unable to open database file',
    ].any(message.contains);
  }

  // ---- making a change ---------------------------------------------------

  @override
  Future<T> write<T>(String operation, Map<String, Object?> args, Future<T> Function() standalone) {
    if (!enabled) return _standalone(operation, args, standalone);
    return _submit<T>(operation, args);
  }

  /// Not shared: the change is made here, and written in the activity log
  /// (a log that cannot be written never undoes or blocks the change).
  Future<T> _standalone<T>(String operation, Map<String, Object?> args, Future<T> Function() change) async {
    final plain = args.cast<String, dynamic>();
    Map<String, Object?> before = const {};
    try {
      before = await _activity.before(operation, plain);
    } catch (_) {}
    final result = await change();
    try {
      await _activity.after(operation, plain, before, result, at: _clock.now().millisecondsSinceEpoch, actor: _actor.user);
    } catch (_) {}
    return result;
  }

  Future<T> _submit<T>(String name, Map<String, Object?> args) async {
    final person = _actor.user;
    final entry = OpEnvelope(
      name: name,
      args: args,
      at: _clock.now().millisecondsSinceEpoch,
      actor: person == null ? null : (id: person.id, name: person.name),
    );
    final opId = _newId();
    final answer = Completer<Object?>();
    answer.future.ignore(); // an error is delivered below, to whoever awaits it
    _pending[opId] = answer;

    try {
      await _exclusive(() async {
        await _append(opId, entry); // if this fails, nothing was recorded
        try {
          await _pullLocked();
        } on Object {
          // It IS in the log; this phone just has not seen it come back.
          throw const SyncException(SyncProblem.delayed);
        }
      });
      if (!answer.isCompleted) throw const SyncException(SyncProblem.delayed);
      return (await answer.future) as T;
    } finally {
      _pending.remove(opId);
    }
  }

  /// Adds the entry. A failed try is repeated a couple of times with the same
  /// id (the server keeps only one copy), then reported as offline.
  Future<void> _append(String opId, OpEnvelope entry) async {
    const attempts = 3;
    for (var attempt = 1;; attempt++) {
      try {
        await _guard(() => _need.append(
              opId: opId,
              device: _deviceId,
              at: entry.at,
              payload: entry.encode(),
            ));
        return;
      } on SyncException catch (e) {
        if (e.problem != SyncProblem.offline || attempt >= attempts) rethrow;
        await _pause(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  // ---- one thing at a time ----------------------------------------------

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }
}
