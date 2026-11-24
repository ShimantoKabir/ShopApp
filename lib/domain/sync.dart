// Sharing the shop between phones.
//
// Every change to the shop's data is written as one entry in a log that all
// phones share and read in the same order. Each phone keeps its own copy of
// the data and replays the log into it, so every phone ends up the same, and
// the shop's own rules (such as "cannot sell more than is in stock") run the
// same way everywhere. Only these small types are known to the screens.

/// One entry of the shared log, as the server hands it out.
class RemoteOp {
  final int seq;
  final String opId;
  final String device;
  final int at;
  final String payload;
  const RemoteOp({required this.seq, required this.opId, required this.device, required this.at, required this.payload});
}

/// Talks to the place where the log is kept.
abstract class SyncTransport {
  /// The number of the newest entry (0 when the log is empty).
  Future<int> head();

  /// Entries after number [after], oldest first, and the newest number.
  Future<({List<RemoteOp> ops, int head})> fetch(int after, {int limit = 500});

  /// Adds an entry and returns its number. Sending the same [opId] again
  /// returns the same number (a retry is never a second copy).
  Future<int> append({required String opId, required String device, required int at, required String payload});

  /// Deletes every entry in the log and leaves only this one (the notice that
  /// the shop was erased). Returns its number.
  Future<int> erase({required String opId, required String device, required int at, required String payload});
}

/// Where the log is and the key that opens it.
class SyncConfig {
  final String url;
  final String key;
  const SyncConfig({required this.url, required this.key});
}

typedef SyncTransportFactory = SyncTransport Function(SyncConfig config);

/// Runs a change to the shop's data.
///
/// Repositories send every change through this. When the shop is shared, the
/// change goes in the log and is replayed on every phone; otherwise
/// [standalone] simply does it here.
abstract class WriteGateway {
  Future<T> write<T>(String operation, Map<String, Object?> args, Future<T> Function() standalone);
}

/// Erasing all of the shop's data, on this phone and (when shared) everywhere.
abstract class DataEraser {
  /// Fires when this phone's data has just been erased: by the owner here, or
  /// because the owner erased the shop from another phone.
  Stream<void> get erased;

  /// Owner only. Erases every product, sale, customer, user and record on this
  /// phone, and, when the shop is shared, in the shared database too (so every
  /// other phone is emptied the next time it reads). This phone then works on
  /// its own again. Cannot be undone. Throws [SyncException] (notOwner,
  /// offline, unauthorized); when it throws, nothing was erased.
  Future<void> eraseEverything();
}

enum SyncState {
  /// Not shared: this phone keeps its own data.
  off,

  /// Shared, and up to date as far as we know.
  idle,
  syncing,

  /// Shared, but the server cannot be reached right now.
  offline,

  /// The server refused our key.
  rejected,

  /// The log holds changes this version of the app does not understand.
  needsUpdate,

  /// Something else went wrong (see [SyncService.detail]).
  failed,
}

/// What the screens use to manage sharing.
abstract class SyncService {
  SyncState get state;
  String? get detail;
  DateTime? get lastSynced;

  /// True when this phone is part of a shared shop.
  bool get enabled;

  /// Where the shop's log normally lives (so people only type the key).
  String get defaultUrl;

  /// Told whenever [state] or [lastSynced] changes.
  Stream<void> get changes;

  /// Checks the address and key and remembers them. Throws [SyncException].
  Future<void> connect({required String url, required String key});

  /// A brand-new phone joins a shop that already exists: downloads everything.
  /// Throws [SyncException] (notFresh, nothingToJoin, offline, unauthorized).
  Future<void> join();

  /// The owner's phone makes its data the shared shop (only when nothing has
  /// been shared yet). Throws [SyncException] (alreadyShared, offline, ...).
  Future<void> shareThisPhone();

  /// Fetches what other phones did. Never throws; look at [state].
  Future<void> syncNow();

  /// Forgets the address and key, so this phone works on its own again. Its
  /// data is left exactly as it is.
  Future<void> disconnect();
}

enum SyncProblem {
  /// No connection (or the server did not answer).
  offline,

  /// The key is wrong.
  unauthorized,

  /// The change reached the shop but this phone has not seen it come back yet.
  /// It is NOT lost: do not repeat it.
  delayed,

  /// The log has changes from a newer version of the app.
  unsupported,

  /// This phone already has shop data, so it cannot join another shop.
  notFresh,

  /// The log is empty: there is no shop to join.
  nothingToJoin,

  /// The log already has data: the shop is already shared.
  alreadyShared,

  /// The address or key is missing or malformed.
  badSettings,

  /// Nothing is connected.
  notConnected,

  /// Something went wrong while reading the shop's data from the log.
  failed,

  /// Only the owner may do this.
  notOwner,

  /// The shared server is older than this app and cannot do this yet.
  serverOutdated,
}

class SyncException implements Exception {
  final SyncProblem problem;
  const SyncException(this.problem);

  @override
  String toString() => 'SyncException($problem)';
}
