import 'package:material_ui/material_ui.dart';

import '../core/bangla.dart';
import '../core/language.dart';
import '../domain/activity.dart';
import '../domain/entities.dart';
import '../domain/payments.dart';
import '../domain/sales.dart';
import '../domain/shop.dart';
import '../domain/stock.dart';
import '../domain/sync.dart';
import '../domain/users.dart';

/// Labels (in the app's language) and icons for domain enums. Kept in the presentation layer
/// so the domain stays free of UI text.
extension ProductKindLabel on ProductKind {
  String get label => switch (this) {
        ProductKind.loose => tr('খোলা / ওজনে', 'Loose / by weight'),
        ProductKind.standard => tr('সাধারণ', 'Regular'),
        ProductKind.bulky => tr('বড় / দামি', 'Large / valuable'),
      };

  IconData get icon => switch (this) {
        ProductKind.loose => Icons.scale_outlined,
        ProductKind.standard => Icons.hardware_outlined,
        ProductKind.bulky => Icons.inventory_2_outlined,
      };

  /// Sensible default unit so staff rarely have to change it.
  String get defaultUnit => switch (this) {
        ProductKind.loose => 'কেজি',
        ProductKind.standard => 'পিস',
        ProductKind.bulky => 'পিস',
      };
}

extension LocationTypeLabel on LocationType {
  /// A custom type is shown as the name the shop gave it.
  String get label {
    if (this == LocationType.shelf) return tr('তাক', 'Shelf');
    if (this == LocationType.floorArea) return tr('মেঝে', 'Floor');
    if (this == LocationType.storeroom) return tr('গুদাম', 'Storeroom');
    if (this == LocationType.yard) return tr('উঠান / বাইরে', 'Yard / outside');
    return name;
  }

  IconData get icon {
    if (this == LocationType.shelf) return Icons.shelves;
    if (this == LocationType.floorArea) return Icons.crop_square;
    if (this == LocationType.storeroom) return Icons.warehouse;
    if (this == LocationType.yard) return Icons.yard;
    return Icons.inventory_2_outlined;
  }
}

extension StockReasonLabel on StockReason {
  String get label => switch (this) {
        StockReason.initial => Bn.reasonInitial,
        StockReason.edit => Bn.reasonEdit,
        StockReason.place => Bn.reasonPlace,
        StockReason.move => Bn.reasonMove,
        StockReason.count => Bn.reasonCount,
        StockReason.restock => Bn.reasonRestock,
        StockReason.sale => Bn.reasonSale,
        StockReason.saleVoid => Bn.reasonSaleVoid,
      };

  IconData get icon => switch (this) {
        StockReason.initial => Icons.add_box_outlined,
        StockReason.edit => Icons.edit_outlined,
        StockReason.place => Icons.place_outlined,
        StockReason.move => Icons.swap_horiz,
        StockReason.count => Icons.fact_check_outlined,
        StockReason.restock => Icons.local_shipping_outlined,
        StockReason.sale => Icons.point_of_sale,
        StockReason.saleVoid => Icons.undo,
      };
}

/// The message to show when a stock rule is broken.
String stockProblemMessage(StockProblem problem) => switch (problem) {
      StockProblem.belowPlaced => Bn.stockBelowPlaced,
      StockProblem.exceedsStock => Bn.stockExceeds,
      StockProblem.notEnoughAtSource => Bn.stockNotEnoughAtSource,
      StockProblem.invalidQuantity => Bn.stockInvalidQuantity,
      StockProblem.sameLocation => Bn.stockSameLocation,
      StockProblem.insufficientStock => Bn.stockInsufficient,
    };

String saleProblemMessage(SaleProblem problem) => switch (problem) {
      SaleProblem.emptyBill => Bn.saleBillEmpty,
      SaleProblem.contactRequired => Bn.saleContactRequired,
      SaleProblem.invalidPayment => Bn.saleInvalidPayment,
      SaleProblem.customerRequiredForDue => Bn.saleCustomerRequiredForDue,
      SaleProblem.invalidCustomer => Bn.saleInvalidCustomer,
    };

/// A message for any stock or billing rule that was broken, or null if [error]
/// is something else (which should not be hidden).
String paymentProblemMessage(PaymentProblem problem) => switch (problem) {
      PaymentProblem.invalidAmount => Bn.payInvalidAmount,
      PaymentProblem.exceedsDue => Bn.payExceedsDue,
      PaymentProblem.unknownCustomer => Bn.payUnknownCustomer,
    };

String authProblemMessage(AuthProblem problem) => switch (problem) {
      AuthProblem.invalidName => Bn.authInvalidName,
      AuthProblem.invalidPin => Bn.authInvalidPin,
      AuthProblem.nameTaken => Bn.authNameTaken,
      AuthProblem.wrongPin => Bn.authWrongPin,
      AuthProblem.unknownUser => Bn.authUnknownUser,
      AuthProblem.inactive => Bn.authInactive,
      AuthProblem.lastOwner => Bn.authLastOwner,
      AuthProblem.invalidPhone => Bn.authInvalidPhone,
    };

String syncProblemMessage(SyncProblem problem) => switch (problem) {
      SyncProblem.offline => Bn.syncOffline,
      SyncProblem.unauthorized => Bn.syncUnauthorized,
      SyncProblem.delayed => Bn.syncDelayed,
      SyncProblem.unsupported => Bn.syncUnsupported,
      SyncProblem.notFresh => Bn.syncNotFresh,
      SyncProblem.nothingToJoin => Bn.syncNothingToJoin,
      SyncProblem.alreadyShared => Bn.syncAlreadyShared,
      SyncProblem.badSettings => Bn.syncBadSettings,
      SyncProblem.notConnected => Bn.syncNotConnected,
      SyncProblem.failed => Bn.syncFailed,
      SyncProblem.notOwner => Bn.eraseOwnerOnly,
      SyncProblem.serverOutdated => Bn.syncServerOutdated,
    };

String syncStateLabel(SyncState state) => switch (state) {
      SyncState.off => Bn.syncStateOff,
      SyncState.idle => Bn.syncStateIdle,
      SyncState.syncing => Bn.syncStateSyncing,
      SyncState.offline => Bn.syncStateOffline,
      SyncState.rejected => Bn.syncStateRejected,
      SyncState.needsUpdate => Bn.syncStateNeedsUpdate,
      SyncState.failed => Bn.syncStateFailed,
    };

String activityGroupLabel(ActivityGroup group) => switch (group) {
      ActivityGroup.all => Bn.activityGroupAll,
      ActivityGroup.sales => Bn.activityGroupSales,
      ActivityGroup.stock => Bn.activityGroupStock,
      ActivityGroup.people => Bn.activityGroupPeople,
    };

IconData activityIcon(String kind) => switch (kind) {
      ActivityKind.sale => Icons.point_of_sale,
      ActivityKind.saleVoided => Icons.cancel_outlined,
      ActivityKind.paymentCollected => Icons.payments_outlined,
      ActivityKind.restocked => Icons.add_box_outlined,
      ActivityKind.stockAdjusted || ActivityKind.stockCounted => Icons.fact_check_outlined,
      ActivityKind.stockPlaced || ActivityKind.stockMoved => Icons.swap_horiz,
      ActivityKind.productAdded => Icons.add_circle_outline,
      ActivityKind.productEdited => Icons.edit_outlined,
      ActivityKind.productDeleted || ActivityKind.categoryDeleted || ActivityKind.locationDeleted => Icons.delete_outline,
      ActivityKind.categoryAdded => Icons.category_outlined,
      ActivityKind.locationAdded => Icons.shelves,
      ActivityKind.locationEdited => Icons.edit_location_alt_outlined,
      ActivityKind.categoryEdited => Icons.edit_outlined,
      ActivityKind.locationTypeRenamed => Icons.label_outline,
      ActivityKind.locationTypeDeleted => Icons.label_off_outlined,
      ActivityKind.userAdded || ActivityKind.userSwitched => Icons.badge_outlined,
      ActivityKind.pinChanged => Icons.password,
      ActivityKind.profileUpdated => Icons.account_circle_outlined,
      ActivityKind.signIn => Icons.login,
      ActivityKind.shopRenamed => Icons.storefront,
      _ => Icons.history,
    };

/// What somebody did, in a sentence. Names were copied into the entry when it
/// was written, so it still reads right if something was renamed or deleted.
String activitySentence(ActivityEntry e) {
  final d = e.detail;
  String text(String key) => (d[key] as String?) ?? '';
  double number(String key) => (d[key] as num?)?.toDouble() ?? 0;
  String money(String key) => d[key] == null ? '' : formatMoney(number(key));
  String qty(String key) => formatNumber(number(key));
  String? place(String key) => d[key] as String?;

  return switch (e.kind) {
    ActivityKind.sale => Bn.activitySale(
        money('total'),
        (d['items'] as num?)?.toInt() ?? 0,
        text('customer'),
        number('due') > 0 ? money('due') : '',
      ),
    ActivityKind.saleVoided => Bn.activitySaleVoided(toBanglaDigits('${d['billId'] ?? ''}'), money('total')),
    ActivityKind.paymentCollected => Bn.activityPayment(money('amount'), text('customer')),
    ActivityKind.restocked => Bn.activityRestocked(text('product'), qty('quantity')),
    ActivityKind.stockAdjusted => Bn.activityStockAdjusted(text('product'), qty('total')),
    ActivityKind.stockPlaced => Bn.activityStockPlaced(text('product'), place('location') ?? '', qty('quantity')),
    ActivityKind.stockCounted => Bn.activityStockCounted(text('product'), place('location') ?? '', qty('quantity')),
    ActivityKind.stockMoved => Bn.activityStockMoved(text('product'), place('from') ?? '', place('to') ?? '', qty('quantity')),
    ActivityKind.productAdded => Bn.activityProductAdded(text('product')),
    ActivityKind.productEdited => Bn.activityProductEdited(text('product')),
    ActivityKind.productDeleted => Bn.activityProductDeleted(text('product')),
    ActivityKind.categoryAdded => Bn.activityCategoryAdded(text('name')),
    ActivityKind.categoryDeleted => Bn.activityCategoryDeleted(text('name')),
    ActivityKind.locationAdded => Bn.activityLocationAdded(text('name')),
    ActivityKind.locationDeleted => Bn.activityLocationDeleted(text('name')),
    ActivityKind.categoryEdited => Bn.activityCategoryEdited(text('previous'), text('name')),
    ActivityKind.locationTypeRenamed => Bn.activityLocationTypeRenamed(text('previous'), text('name')),
    ActivityKind.locationTypeDeleted => Bn.activityLocationTypeDeleted(text('name')),
    ActivityKind.locationEdited => Bn.activityLocationEdited(text('previous'), text('name')),
    ActivityKind.userAdded => Bn.activityUserAdded(
        text('name'),
        text('role') == UserRole.owner.name ? Bn.roleOwner : Bn.roleStaff,
      ),
    ActivityKind.pinChanged => Bn.activityPinChanged(text('name')),
    ActivityKind.profileUpdated => Bn.activityProfileUpdated(text('name')),
    ActivityKind.userSwitched => d['active'] == true ? Bn.activityUserOn(text('name')) : Bn.activityUserOff(text('name')),
    ActivityKind.signIn => Bn.activitySignIn,
    ActivityKind.shopRenamed => Bn.activityShopRenamed(text('name')),
    _ => e.kind,
  };
}

String shopProblemMessage(ShopProblem problem) => switch (problem) {
      ShopProblem.emptyName => Bn.shopNameEmpty,
      ShopProblem.nameTooLong => Bn.shopNameTooLong,
    };

String categoryProblemMessage(CategoryProblem problem) => switch (problem) {
      CategoryProblem.emptyName => Bn.categoryNameEmpty,
      CategoryProblem.unknownCategory => Bn.categoryUnknown,
      CategoryProblem.nameTaken => Bn.categoryNameTaken,
    };

String locationProblemMessage(LocationProblem problem) => switch (problem) {
      LocationProblem.emptyName => Bn.locationNameEmpty,
      LocationProblem.unknownLocation => Bn.locationUnknown,
      LocationProblem.builtInType => Bn.locationTypeBuiltIn,
    };

String roleLabel(UserRole role) => role == UserRole.owner ? Bn.roleOwner : Bn.roleStaff;

String? ruleMessage(Object error) => switch (error) {
      StockException(:final problem) => stockProblemMessage(problem),
      SaleException(:final problem) => saleProblemMessage(problem),
      PaymentException(:final problem) => paymentProblemMessage(problem),
      AuthException(:final problem) => authProblemMessage(problem),
      SyncException(:final problem) => syncProblemMessage(problem),
      ShopException(:final problem) => shopProblemMessage(problem),
      LocationException(:final problem) => locationProblemMessage(problem),
      CategoryException(:final problem) => categoryProblemMessage(problem),
      _ => null,
    };
