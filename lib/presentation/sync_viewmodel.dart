import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/sync.dart';

/// Shows and controls the sharing of the shop between phones.
class SyncViewModel extends ChangeNotifier {
  final SyncService _sync;
  late final StreamSubscription<void> _subscription;

  SyncViewModel(this._sync) {
    _subscription = _sync.changes.listen((_) => notifyListeners());
  }

  /// True while connecting or uploading (the button is busy).
  bool working = false;

  SyncState get state => _sync.state;
  bool get enabled => _sync.enabled;
  DateTime? get lastSynced => _sync.lastSynced;
  String get defaultUrl => _sync.defaultUrl;

  Future<void> _work(Future<void> Function() action) async {
    working = true;
    notifyListeners();
    try {
      await action();
    } finally {
      working = false;
      notifyListeners();
    }
  }

  /// The owner's phone: connect, then make this phone's data the shared shop.
  /// If it cannot be shared, the phone is left on its own as before. Throws
  /// [SyncException].
  Future<void> shareThisPhone(String url, String key) => _work(() async {
        await _sync.connect(url: url, key: key);
        try {
          await _sync.shareThisPhone();
        } catch (_) {
          await _sync.disconnect();
          rethrow;
        }
      });

  /// A new phone: connect and download the shop. Throws [SyncException]. If
  /// there is nothing to join, or this phone has a shop already, nothing is
  /// kept; if the signal is lost part-way, trying again carries on.
  Future<void> joinShop(String url, String key) => _work(() async {
        await _sync.connect(url: url, key: key);
        try {
          await _sync.join();
        } on SyncException catch (e) {
          if (e.problem == SyncProblem.notFresh || e.problem == SyncProblem.nothingToJoin) await _sync.disconnect();
          rethrow;
        }
      });

  Future<void> syncNow() => _work(_sync.syncNow);

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
