/// The longest a shop's name may be (it must fit on the menu and a receipt).
const maxShopNameLength = 60;

enum ShopProblem {
  /// Nothing (or only spaces) was written.
  emptyName,

  /// More than [maxShopNameLength] characters.
  nameTooLong,
}

/// A rule about the shop's name was broken; nothing changed.
class ShopException implements Exception {
  final ShopProblem problem;
  const ShopException(this.problem);

  @override
  String toString() => 'ShopException($problem)';
}

/// What is known about the shop itself. Shared by every phone of the shop.
abstract class ShopRepository {
  /// The shop's name, or null if the owner never chose one.
  Future<String?> name();

  /// Throws [ShopException] (emptyName, nameTooLong). Spaces around the name are
  /// dropped.
  Future<void> rename(String name);
}
