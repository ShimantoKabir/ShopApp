import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/bangla.dart';
import '../../domain/shop.dart';
import '../../domain/sync.dart';

/// The shop's name, as shown on the menu and on receipts. One for the whole
/// app: when the owner renames the shop it changes everywhere at once, and when
/// another phone renames it, this one follows after the next sync.
class ShopNameViewModel extends ChangeNotifier {
  final ShopRepository _shop;
  StreamSubscription<void>? _subscription;
  String? _name;

  ShopNameViewModel(this._shop, [SyncService? sync]) {
    _subscription = sync?.changes.listen((_) => load().catchError((Object _) {}));
  }

  /// The name the owner chose, or the app's own name until they do.
  String get name => _name ?? Bn.appTitle;

  /// Whether the owner has chosen a name.
  bool get hasName => _name != null;

  Future<void> load() async {
    final loaded = await _shop.name();
    if (loaded != _name) {
      _name = loaded;
      notifyListeners();
    }
  }

  /// Throws [ShopException] (empty, too long) or [SyncException] (no connection).
  Future<void> rename(String newName) async {
    await _shop.rename(newName);
    await load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
