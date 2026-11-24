import 'users.dart';

/// What kinds of things are written in the activity log.
abstract final class ActivityKind {
  static const sale = 'sale';
  static const saleVoided = 'saleVoided';
  static const paymentCollected = 'paymentCollected';
  static const restocked = 'restocked';
  static const stockAdjusted = 'stockAdjusted';
  static const stockPlaced = 'stockPlaced';
  static const stockCounted = 'stockCounted';
  static const stockMoved = 'stockMoved';
  static const productAdded = 'productAdded';
  static const productEdited = 'productEdited';
  static const productDeleted = 'productDeleted';
  static const categoryAdded = 'categoryAdded';
  static const categoryDeleted = 'categoryDeleted';
  static const categoryEdited = 'categoryEdited';
  static const locationAdded = 'locationAdded';
  static const locationDeleted = 'locationDeleted';
  static const locationEdited = 'locationEdited';
  static const locationTypeRenamed = 'locationTypeRenamed';
  static const locationTypeDeleted = 'locationTypeDeleted';
  static const userAdded = 'userAdded';
  static const pinChanged = 'pinChanged';
  static const profileUpdated = 'profileUpdated';
  static const userSwitched = 'userSwitched';
  static const signIn = 'signIn';
  static const shopRenamed = 'shopRenamed';
}

/// A way to narrow the list down.
enum ActivityGroup {
  all,

  /// Selling, cancelling a sale, taking money for dues.
  sales,

  /// Stock, products, categories and shelves.
  stock,

  /// Signing in and everything about the people who use the app.
  people;

  /// The kinds that belong to this group (empty = all of them).
  Set<String> get kinds => switch (this) {
        ActivityGroup.all => const {},
        ActivityGroup.sales => const {ActivityKind.sale, ActivityKind.saleVoided, ActivityKind.paymentCollected},
        ActivityGroup.stock => const {
            ActivityKind.restocked,
            ActivityKind.stockAdjusted,
            ActivityKind.stockPlaced,
            ActivityKind.stockCounted,
            ActivityKind.stockMoved,
            ActivityKind.productAdded,
            ActivityKind.productEdited,
            ActivityKind.productDeleted,
            ActivityKind.categoryAdded,
            ActivityKind.categoryDeleted,
            ActivityKind.categoryEdited,
            ActivityKind.locationAdded,
            ActivityKind.locationDeleted,
            ActivityKind.locationEdited,
            ActivityKind.locationTypeRenamed,
            ActivityKind.locationTypeDeleted,
          },
        ActivityGroup.people => const {
            ActivityKind.signIn,
            ActivityKind.userAdded,
            ActivityKind.pinChanged,
            ActivityKind.profileUpdated,
            ActivityKind.userSwitched,
            ActivityKind.shopRenamed,
          },
      };
}

/// One thing somebody did.
class ActivityEntry {
  final int id;
  final DateTime at;

  /// Who did it. Null (and an empty [userName]) if nobody was signed in.
  final int? userId;
  final String userName;
  final String kind;

  /// The details (product, amount...). Names are copied in, so the entry still
  /// reads right if the thing is later renamed or deleted.
  final Map<String, dynamic> detail;

  const ActivityEntry({
    required this.id,
    required this.at,
    this.userId,
    this.userName = '',
    required this.kind,
    this.detail = const {},
  });
}

abstract class ActivityRepository {
  /// The most recent activity first, [limit] entries. Narrow it to one person
  /// with [userId] and/or to a [group] of kinds.
  Future<List<ActivityEntry>> recent({int limit = 100, int? userId, ActivityGroup group = ActivityGroup.all});
}

/// Notes that someone signed in. Never throws and never makes anyone wait: a
/// note that cannot be made (no connection...) is simply not made.
abstract class ActivityNotifier {
  void signedIn(AppUser user);
}
