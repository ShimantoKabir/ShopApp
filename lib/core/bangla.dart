import 'language.dart';

/// The text for the language in use: [bangla] or [english] (see [Language]).
String _t(String bangla, String english) => Language.isBangla ? bangla : english;

/// All user-facing text lives here so the UI never hardcodes strings. Every entry
/// is looked up when it is shown, so it follows the app's language.
class Bn {
  static String get appTitle => _t('দোকান খাতা', 'Dokan Khata');
  static String get products => _t('পণ্য', 'Products');
  static String get addProduct => _t('নতুন পণ্য', 'New product');
  static String get editProduct => _t('পণ্য সম্পাদনা', 'Edit product');
  static String get search => _t('পণ্য খুঁজুন', 'Search products');
  static String get all => _t('সব', 'All');
  static String get name => _t('পণ্যের নাম', 'Product name');
  static String get category => _t('ক্যাটাগরি', 'Category');
  static String get location => _t('স্থান', 'Location');
  static String get noLocation => _t('স্থান নেই', 'No location');
  static String get purchasePrice => _t('কেনা দাম', 'Buying price');
  static String get sellingPrice => _t('বিক্রি দাম', 'Selling price');
  static String get stock => _t('মজুদ', 'Stock');
  static String get unit => _t('একক', 'Unit');
  static String get profit => _t('লাভ', 'Profit');
  static String get loss => _t('ক্ষতি', 'Loss');
  static String get perUnit => _t('প্রতি একক', 'per unit');
  static String get save => _t('সংরক্ষণ', 'Save');
  static String get saveAndNext => _t('সংরক্ষণ + নতুন', 'Save + new');
  static String get send => _t('পাঠান', 'Send');
  static String get cancel => _t('বাতিল', 'Cancel');
  static String get delete => _t('মুছুন', 'Delete');
  static String get edit => _t('সম্পাদনা', 'Edit');
  static String get add => _t('যোগ করুন', 'Add');
  static String get saved => _t('সংরক্ষিত হয়েছে', 'Saved');
  static String get required => _t('এটি আবশ্যক', 'This is required');
  static String get invalidNumber => _t('সঠিক সংখ্যা লিখুন', 'Enter a valid number');
  static String get noProducts => _t('কোনো পণ্য নেই। নিচের বোতাম চেপে যোগ করুন।', 'No products yet. Tap the button below to add one.');
  static String get noResults => _t('কিছু পাওয়া যায়নি', 'Nothing found');
  static String get categories => _t('ক্যাটাগরি সমূহ', 'Categories');
  static String get newCategory => _t('নতুন ক্যাটাগরি', 'New category');
  static String get locations => _t('স্থান সমূহ', 'Locations');
  static String get editCategory => _t('ক্যাটাগরি সম্পাদনা', 'Edit category');
  static String get categoryNameEmpty => _t('ক্যাটাগরির নাম লিখুন', 'Enter the category name');
  static String get categoryUnknown => _t('ক্যাটাগরিটি পাওয়া যায়নি', 'Category not found');
  static String get categoryNameTaken => _t('এই নামে আরেকটি ক্যাটাগরি আছে', 'Another category already has this name');
  static String activityCategoryEdited(String previous, String name) => Language.isBangla
      ? (previous.isEmpty || previous == name ? 'ক্যাটাগরি বদলেছেন: $name' : 'ক্যাটাগরি বদলেছেন: $previous → $name')
      : (previous.isEmpty || previous == name ? 'Changed a category: $name' : 'Renamed a category: $previous → $name');
  static String get editLocation => _t('স্থান সম্পাদনা', 'Edit location');
  static String get locationNameEmpty => _t('স্থানের নাম লিখুন', 'Enter the location name');
  static String get locationUnknown => _t('স্থানটি পাওয়া যায়নি', 'Location not found');
  static String activityLocationEdited(String previous, String name) => Language.isBangla
      ? (previous.isEmpty || previous == name ? 'স্থান বদলেছেন: $name' : 'স্থান বদলেছেন: $previous → $name')
      : (previous.isEmpty || previous == name ? 'Changed a location: $name' : 'Renamed a location: $previous → $name');
  static String get newLocation => _t('নতুন স্থান', 'New location');
  static String get locationNameHint => _t('যেমন: তাক ১, বাম দেয়াল, বাইরের উঠান', 'e.g. Shelf 1, left wall, outside yard');
  static String get categoryNameHint => _t('যেমন: পাইপ, তার, রং', 'e.g. Pipe, Wire, Paint');
  static String get scanQr => _t('QR স্ক্যান', 'Scan QR');
  static String get scanLocation => _t('স্থানের QR স্ক্যান করুন', 'Scan a location QR');
  static String get scanHint => _t('স্থানের QR কোডের দিকে ক্যামেরা ধরুন', 'Point the camera at the location QR code');
  static String get unknownQr => _t('এই QR কোড এই অ্যাপের কোনো স্থানের নয়', 'This QR code is not a location in this app');
  static String get locationQr => _t('স্থানের QR কোড', 'Location QR code');
  static String get locationQrHelp => _t('এই QR প্রিন্ট করে ওই স্থানে লাগিয়ে দিন', 'Print this QR and stick it at that location');
  static String get productsOnLocation => _t('এই স্থানের পণ্য', 'Products at this location');
  static String get totalItems => _t('মোট পণ্য', 'Total products');
  static String get stockValue => _t('মজুদের মূল্য (কেনা দামে)', 'Stock value (at buying price)');
  static String get updateStock => _t('মজুদ আপডেট', 'Update stock');
  static String get confirmDelete => _t('আপনি কি নিশ্চিত মুছে ফেলতে চান?', 'Are you sure you want to delete this?');
  static String get lowStock => _t('কম মজুদ', 'Low stock');
  static const taka = '৳';
  static String get kind => _t('ধরন', 'Type');
  static String get brand => _t('ব্র্যান্ড', 'Brand');
  static String get size => _t('সাইজ', 'Size');
  static String get finish => _t('রং / ফিনিশ', 'Colour / finish');
  static String get model => _t('মডেল / পার্ট নং', 'Model / part no.');
  static String get details => _t('বিস্তারিত (ব্র্যান্ড, সাইজ, মডেল, রং)', 'More details (brand, size, model, colour)');
  static String get locationTypesTitle => _t('স্থানের ধরন', 'Location types');
  static String get locationTypesEmpty => _t(
      'আপনার বানানো কোনো ধরন নেই। স্থান যোগ বা সম্পাদনার সময় "নতুন ধরন" চাপুন।',
      'No types of your own yet. Tap "New type" when adding or editing a location.');
  static String get editLocationType => _t('ধরনের নাম বদলান', 'Rename type');
  static String get locationTypeBuiltIn => _t('তাক, মেঝে, গুদাম ও উঠান বদলানো বা মোছা যায় না।', 'Shelf, Floor, Storeroom and Yard cannot be renamed or deleted.');
  static String locationTypeUsage(int n) => Language.isBangla
      ? '${toBanglaDigits('$n')}টি স্থান • মুছলে সেগুলো "তাক" হবে'
      : '$n location${n == 1 ? '' : 's'} • deleting makes them "Shelf"';
  static String activityLocationTypeRenamed(String previous, String name) =>
      Language.isBangla ? 'স্থানের ধরন বদলেছেন: $previous → $name' : 'Renamed a location type: $previous → $name';
  static String activityLocationTypeDeleted(String name) =>
      Language.isBangla ? 'স্থানের ধরন মুছেছেন: $name' : 'Deleted a location type: $name';
  static String get newLocationType => _t('নতুন ধরন', 'New type');
  static String get newLocationTypeTitle => _t('নতুন স্থানের ধরন', 'New location type');
  static String get newLocationTypeHint => _t('যেমন: আলমারি, র‍্যাক, কাউন্টার', 'e.g. Cabinet, Rack, Counter');
  static String get locationType => _t('স্থানের ধরন', 'Location type');
  static String get sectionInfo => _t('পণ্যের তথ্য', 'Product details');
  static String get sectionPricing => _t('দাম ও মজুদ', 'Price and stock');
  static String get sectionPlace => _t('ক্যাটাগরি ও স্থান', 'Category and location');
  static String get duplicateWarning => _t('এই নাম, ব্র্যান্ড ও সাইজের পণ্য আগে থেকেই আছে। তবুও সংরক্ষণ করবেন?', 'A product with this name, brand and size already exists. Save anyway?');
  static String get saveAnyway => _t('তবুও সংরক্ষণ', 'Save anyway');
  static String get priceMissing => _t('দাম বাকি', 'Price not set');
  static String get importProducts => _t('CSV থেকে পণ্য আনুন', 'Import products from CSV');
  static String get importIntro => _t('Excel বা Google Sheet থেকে CSV ফাইল সেভ করে এখানে বেছে নিন। পণ্যের নামের কলাম (Name বা Item) থাকতে হবে। ক্যাটাগরি, একক, ব্র্যান্ড, সাইজ, মডেল ও রং কলাম থাকলে সেগুলোও আসবে।', 'Save a CSV file from Excel or Google Sheets and choose it here. It needs a product name column (Name or Item). Category, unit, brand, size, model and colour columns are read too if they are there.');
  static String get importWithPrices => _t('ফাইলের দাম ও মজুদও আনুন', 'Also import prices and stock from the file');
  static String get importWithPricesHelp => _t('যাচাই করা না থাকলে বন্ধ রাখুন। বন্ধ থাকলে দাম ও মজুদ ০ হবে, পরে নিজে লিখবেন।', 'Turn this off if the file has not been checked. When it is off, price and stock are set to 0 and you fill them in later.');
  static String get pickFile => _t('ফাইল বেছে নিন', 'Choose file');
  static String get importDone => _t('আমদানি শেষ', 'Import finished');
  static String get importAdded => _t('নতুন যোগ হয়েছে', 'Newly added');
  static String get importSkipped => _t('আগে থেকেই ছিল (বাদ)', 'Already there (skipped)');
  static String get importFailed => _t('সমস্যা হয়েছে', 'Something went wrong');
  static String get importCancelled => _t('কোনো ফাইল বাছা হয়নি', 'No file was chosen');
  // --- Stock placement ---
  static String get sectionLocations => _t('স্থান ও মজুদ বণ্টন', 'Locations and stock split');
  static String get unplaced => _t('স্থান ঠিক হয়নি', 'Not placed');
  static String get addPlacement => _t('স্থান যোগ করুন', 'Add location');
  static String get placementQuantity => _t('এই স্থানে মোট পরিমাণ', 'Total quantity at this location');
  static String get recountAction => _t('গণনা করে ঠিক করুন', 'Count and correct');
  static String get recountLabel => _t('গণনা করে পাওয়া পরিমাণ', 'Quantity found by counting');
  static String get moveAction => _t('অন্য স্থানে সরান', 'Move to another location');
  static String get moveTo => _t('যে স্থানে সরাবেন', 'Move to which location');
  static String get moveQuantity => _t('কতটুকু সরাবেন', 'How much to move');
  static String get removeFromLocation => _t('সরান', 'Remove');
  static String get historyTitle => _t('মজুদের ইতিহাস', 'Stock history');
  static String get history => _t('ইতিহাস', 'History');
  static String get noHistory => _t('এখনো কোনো পরিবর্তন নেই', 'No changes yet');
  static String get understood => _t('ঠিক আছে', 'OK');
  static String get noLocationsYet => _t('আগে একটি স্থান তৈরি করুন', 'Create a location first');
  static String get locationEmpty => _t('খালি', 'Empty');
  static String get countHere => _t('এই স্থানে গণনা', 'Count at this location');
  static String get updatedFromPlacement => _t('মোট মজুদ আপডেট হয়েছে', 'Total stock was updated');

  static String productsCount(int n) =>
      Language.isBangla ? '${toBanglaDigits('$n')}টি পণ্য' : n == 1 ? '1 product' : '$n products';

  static String locationNotEmpty(int n) =>
      Language.isBangla ? 'এই স্থানে ${toBanglaDigits('$n')}টি পণ্যের মজুদ আছে। আগে সেগুলো অন্য স্থানে সরান বা এই স্থান থেকে সরিয়ে দিন, তারপর মুছুন।' : 'This location holds stock of ${n == 1 ? '1 product' : '$n products'}. First move it to another location or remove it from this location, then delete.';

  static String get stockBelowPlaced => _t('মোট মজুদ বিভিন্ন স্থানে রাখা পরিমাণের চেয়ে কম হতে পারে না। আগে স্থান থেকে কমান।', 'Total stock cannot be less than what is placed at locations. Reduce it at the locations first.');
  static String get stockExceeds => _t('মোট মজুদের চেয়ে বেশি পরিমাণ স্থানে রাখা যাবে না।', 'More than the total stock cannot be placed at locations.');
  static String get stockNotEnoughAtSource => _t('ওই স্থানে এত পরিমাণ নেই।', 'That location does not have this much.');
  static String get stockInvalidQuantity => _t('সঠিক পরিমাণ লিখুন।', 'Enter a valid quantity.');
  static String get stockSameLocation => _t('একই স্থানে সরানো যাবে না।', 'Cannot move to the same location.');

  static String get reasonInitial => _t('নতুন পণ্য', 'New product');
  static String get reasonEdit => _t('মজুদ সম্পাদনা', 'Stock edited');
  static String get reasonPlace => _t('স্থানে রাখা', 'Placed');
  static String get reasonMove => _t('স্থান পরিবর্তন', 'Moved');
  static String get reasonCount => _t('গণনা', 'Counted');

  // --- Navigation, restock, selling, daily account ---
  static String get navInventory => _t('মজুদ', 'Inventory');
  static String get navSell => _t('বিক্রি', 'Sell');
  static String get navAccount => _t('হিসাব', 'Accounts');
  static String get navDashboard => _t('ড্যাশবোর্ড', 'Dashboard');
  static String get navUsers => _t('কর্মী', 'Staff');
  static String get navProfile => _t('আমার প্রোফাইল', 'My profile');
  static String get navSync => _t('সিঙ্ক ডাটাবেস', 'Sync database');
  static String get navActivity => _t('কর্মীদের কাজ', 'Staff activity');
  static String appVersion(String version) =>
      Language.isBangla ? 'সংস্করণ ${toBanglaDigits(version)}' : 'Version $version';

  // Activity log
  static String get activityTitle => _t('কর্মীদের কাজ', 'Staff activity');
  static String get activityEveryone => _t('সবাই', 'Everyone');
  static String get activityGroupAll => _t('সব', 'All');
  static String get activityGroupSales => _t('বিক্রি ও টাকা', 'Sales and money');
  static String get activityGroupStock => _t('মজুদ ও পণ্য', 'Stock and products');
  static String get activityGroupPeople => _t('কর্মী ও লগইন', 'Staff and sign-ins');
  static String get activityEmpty => _t('এখনো কোনো কাজ লেখা হয়নি। কেউ কিছু করলে এখানে দেখা যাবে।', 'Nothing recorded yet. When someone does something, it will show here.');
  static String get activityEmptyFiltered => _t('এই বাছাইয়ে কোনো কাজ নেই', 'No activity for this choice');
  static String get activityMore => _t('আরও', 'More');
  static String get activityUnknownPerson => _t('অজানা', 'Unknown');
  static String activitySale(String total, int items, String customer, String due) =>
      Language.isBangla ? 'বিক্রি করেছেন: $total • ${toBanglaDigits('$items')}টি পণ্য${customer.isEmpty ? '' : ' • $customer'}${due.isEmpty ? '' : ' • বাকি $due'}' : 'Sold: $total • ${items == 1 ? '1 item' : '$items items'}${customer.isEmpty ? '' : ' • $customer'}${due.isEmpty ? '' : ' • due $due'}';
  static String activitySaleVoided(String bill, String total) =>
      Language.isBangla ? 'বিক্রি বাতিল করেছেন: রসিদ নং $bill${total.isEmpty ? '' : ' • $total'}' : 'Cancelled a sale: receipt no. $bill${total.isEmpty ? '' : ' • $total'}';
  static String activityPayment(String amount, String customer) =>
      Language.isBangla ? 'বাকির টাকা নিয়েছেন: $amount${customer.isEmpty ? '' : ' • $customer'}' : 'Took money for a due: $amount${customer.isEmpty ? '' : ' • $customer'}';
  static String activityRestocked(String product, String quantity) =>
      Language.isBangla ? 'মজুদ যোগ করেছেন: $product • +$quantity' : 'Added stock: $product • +$quantity';
  static String activityStockAdjusted(String product, String total) =>
      Language.isBangla ? 'মজুদ ঠিক করেছেন: $product • মোট $total' : 'Corrected stock: $product • total $total';
  static String activityStockPlaced(String product, String location, String quantity) =>
      Language.isBangla ? '$product সাজিয়েছেন: $location • $quantity' : 'Placed $product: $location • $quantity';
  static String activityStockCounted(String product, String location, String quantity) =>
      Language.isBangla ? '$product গণনা করেছেন: $location • $quantity' : 'Counted $product: $location • $quantity';
  static String activityStockMoved(String product, String from, String to, String quantity) =>
      Language.isBangla ? '$product সরিয়েছেন: $from → $to • $quantity' : 'Moved $product: $from → $to • $quantity';
  static String activityProductAdded(String name) =>
      Language.isBangla ? 'নতুন পণ্য যোগ করেছেন: $name' : 'Added a new product: $name';
  static String activityProductEdited(String name) =>
      Language.isBangla ? 'পণ্য বদলেছেন: $name' : 'Changed a product: $name';
  static String activityProductDeleted(String name) =>
      Language.isBangla ? 'পণ্য মুছেছেন: $name' : 'Deleted a product: $name';
  static String activityCategoryAdded(String name) =>
      Language.isBangla ? 'ক্যাটাগরি যোগ করেছেন: $name' : 'Added a category: $name';
  static String activityCategoryDeleted(String name) =>
      Language.isBangla ? 'ক্যাটাগরি মুছেছেন: $name' : 'Deleted a category: $name';
  static String activityLocationAdded(String name) =>
      Language.isBangla ? 'স্থান যোগ করেছেন: $name' : 'Added a location: $name';
  static String activityLocationDeleted(String name) =>
      Language.isBangla ? 'স্থান মুছেছেন: $name' : 'Deleted a location: $name';
  static String activityUserAdded(String name, String role) =>
      Language.isBangla ? 'নতুন কর্মী যোগ করেছেন: $name ($role)' : 'Added new staff: $name ($role)';
  static String activityPinChanged(String name) =>
      Language.isBangla ? 'PIN বদলেছেন: $name' : 'Changed PIN: $name';
  static String activityProfileUpdated(String name) =>
      Language.isBangla ? 'প্রোফাইল বদলেছেন: $name' : 'Changed profile: $name';
  static String activityUserOn(String name) =>
      Language.isBangla ? '$name-কে চালু করেছেন' : 'Switched on $name';
  static String activityUserOff(String name) =>
      Language.isBangla ? '$name-কে বন্ধ করেছেন' : 'Switched off $name';
  static String get activitySignIn => _t('অ্যাপে ঢুকেছেন', 'Signed in');

  // Sharing the shop between phones
  static String get syncTitle => _t('সিঙ্ক ডাটাবেস', 'Sync database');
  static String get syncIntro => _t('সবার ফোনে একই দোকান দেখতে ও বিক্রি করতে, এই ফোনের তথ্য ইন্টারনেটে শেয়ার করুন। এরপর যে কোনো ফোন থেকে বিক্রি বা মজুদ বদলানো যাবে, আর সবাই একই হিসাব দেখবে।', 'To let every phone see the same shop and sell from it, share the data on this phone over the internet. After that, sales and stock can be changed from any phone, and everyone sees the same figures.');
  static String get syncUrlLabel => _t('সার্ভারের ঠিকানা', 'Server address');
  static String get syncKeyLabel => _t('দোকানের গোপন কী (Key)', 'Shop secret key');
  static String get syncShareButton => _t('তথ্য শেয়ার করুন', 'Share data');
  static String get syncShareWarning => _t('এই ফোনের তথ্যই সবার দোকান হবে। কী (Key) দোকানের বাইরে কাউকে দেবেন না: যার কাছে কী থাকবে সে দোকানের সব তথ্য দেখতে পারবে।', 'The data on this phone becomes the shop for everyone. Do not give the key to anyone outside the shop: whoever has the key can see all of the shop data.');
  static String get syncConnected => _t('এই দোকান শেয়ার করা আছে', 'This shop is shared');
  static String get syncNow => _t('মিলান', 'Sync');
  static String get syncNeedsInternet => _t('দেখা সবসময় যাবে, কিন্তু বিক্রি বা মজুদ বদলাতে ইন্টারনেট লাগবে, যাতে সবার হিসাব এক থাকে।', 'You can always look, but changing sales or stock needs internet so that everyone has the same figures.');
  static String get syncStateOff => _t('শেয়ার করা নেই', 'Not shared');
  static String get syncStateIdle => _t('সংযুক্ত', 'Connected');
  static String get syncStateSyncing => _t('মিলানো হচ্ছে…', 'Syncing…');
  static String get syncStateOffline => _t('ইন্টারনেট নেই', 'No internet');
  static String get syncStateRejected => _t('কী (Key) গ্রহণ হয়নি', 'Key not accepted');
  static String get syncStateNeedsUpdate => _t('অ্যাপ আপডেট করুন', 'Update the app');
  static String get syncStateFailed => _t('সমস্যা হয়েছে', 'Something went wrong');
  static String syncLastTime(String when) =>
      Language.isBangla ? 'শেষ মিলানো: $when' : 'Last synced: $when';
  static String get syncNever => _t('এখনো মেলানো হয়নি', 'Not synced yet');
  static String get syncShared => _t('দোকান শেয়ার হয়েছে', 'The shop is now shared');
  static String get joinShopTitle => _t('দোকানে যুক্ত হন', 'Join the shop');
  static String get joinShopIntro => _t('অন্য ফোনে যে দোকান চালু আছে, তাতে এই ফোন যুক্ত করুন। দোকানের কী (Key) মালিকের কাছে পাবেন।', 'Connect this phone to the shop that is already running on another phone. You get the shop key from the owner.');
  static String get joinShopButton => _t('যুক্ত হন', 'Join');
  static String get joinShopLink => _t('চালু দোকানে যুক্ত হন', 'Join an existing shop');
  static String get syncOffline => _t('ইন্টারনেট নেই। সংযোগ ফিরলে আবার চেষ্টা করুন।', 'No internet. Try again when the connection is back.');
  static String get syncUnauthorized => _t('কী (Key) ভুল।', 'Wrong key.');
  static String get syncDelayed => _t('সংরক্ষণ হয়েছে, কিন্তু এই ফোনে দেখা যেতে একটু সময় লাগবে। আবার করবেন না।', 'It was saved, but it will take a moment to show on this phone. Do not do it again.');
  static String get syncUnsupported => _t('অ্যাপের নতুন সংস্করণ লাগবে। অ্যাপ আপডেট করুন।', 'A newer version of the app is needed. Update the app.');
  static String get syncNotFresh => _t('এই ফোনে আগেই দোকানের তথ্য আছে, তাই অন্য দোকানে যুক্ত করা যাবে না।', 'This phone already has shop data, so it cannot join another shop.');
  static String get syncNothingToJoin => _t('এখনো কোনো দোকান শেয়ার করা হয়নি। আগে মালিকের ফোন থেকে শেয়ার করুন।', 'No shop has been shared yet. Share it from the owner phone first.');
  static String get syncAlreadyShared => _t('এই দোকান আগেই শেয়ার করা হয়েছে। অন্য ফোনে "যুক্ত হন" ব্যবহার করুন।', 'This shop is already shared. Use "Join" on the other phone.');
  static String get syncBadSettings => _t('ঠিকানা বা কী (Key) সঠিক নয়।', 'The address or key is not correct.');
  static String get syncServerOutdated => _t('শেয়ার করা সার্ভার পুরোনো, এটি এখনো করতে পারে না। আগে সার্ভার আপডেট করুন। কিছু মোছা হয়নি।', 'The shared server is out of date and cannot do this yet. Update the server first. Nothing was erased.');
  static String get eraseOwnerOnly => _t('শুধু মালিক এটি করতে পারেন।', 'Only the owner can do this.');
  static String get eraseSection => _t('সব তথ্য মুছুন', 'Erase all data');
  static String get eraseHelp => _t(
      'এই ফোনের এবং সিঙ্ক ডাটাবেসের সব তথ্য চিরতরে মুছে যাবে।',
      "All data on this phone and in the sync database will be erased for good.");
  static String get eraseButton => _t('সব তথ্য মুছুন...', 'Erase all data...');
  static String get eraseDialogTitle => _t('সব তথ্য মুছে ফেলবেন?', 'Erase all data?');
  static String get eraseWarning => _t(
      'সতর্কতা: এটি ফিরিয়ে আনা যাবে না। সব পণ্য, স্টক, বিক্রি, রসিদ, গ্রাহক ও বাকি, কর্মী এবং কার্যকলাপের তালিকা মুছে যাবে। অ্যাপ নতুনের মতো শুরু হবে।',
      'Warning: this cannot be undone. All products, stock, sales, receipts, customers and dues, staff and the activity log will be erased. The app starts again like new.');
  static String get eraseSharedWarning => _t(
      'এই দোকান শেয়ার করা আছে: সিঙ্ক (লাইভ) ডাটাবেস মুছে যাবে এবং অন্য সব ফোনের তথ্যও মুছে যাবে (তারা পরের বার সংযোগ পেলে)।',
      'This shop is shared: the sync (live) database will be erased, and every other phone is emptied too (the next time it connects).');
  static String get eraseConsent => _t('আমি সম্পূর্ণ সচেতন যে সব তথ্য চিরতরে মুছে যাবে।', 'I am fully aware that all data will be erased permanently.');
  static String get eraseTypePrompt => _t('নিশ্চিত করতে নিচে লিখুন: ERASE', 'To confirm, type: ERASE');
  static const eraseWord = 'ERASE';
  static String get eraseConfirm => _t('সব মুছে ফেলুন', 'Erase everything');
  static String get eraseDone => _t('সব তথ্য মুছে ফেলা হয়েছে।', 'All data has been erased.');
  static String get erasedByOwner => _t('মালিক দোকানের সব তথ্য মুছে ফেলেছেন।', 'The owner erased all of the shop\'s data.');
  static String get syncNotConnected => _t('আগে সংযোগ দিন।', 'Connect first.');
  static String get syncNotConnectedStaff => _t('এই ফোন এখনো দোকানের সাথে যুক্ত নয়। মালিকের সাথে কথা বলুন।', 'This phone is not connected to the shop yet. Talk to the owner.');
  static String get syncAutomatic => _t('নতুন তথ্য নিজে থেকেই আসে: কয়েক সেকেন্ড পরপর, আর অ্যাপ খুললে। তাড়াতাড়ি দরকার হলে নিচের বোতাম চাপুন।', 'New data arrives by itself: every few seconds, and when you open the app. If you need it sooner, tap the button below.');
  static String get syncFailed => _t('দোকানের তথ্য মেলাতে সমস্যা হয়েছে। অ্যাপ আপডেট করে আবার চেষ্টা করুন।', 'There was a problem matching the shop data. Update the app and try again.');
  static String get navSettings => _t('সেটিংস', 'Settings');
  static String get navSignOut => _t('বেরিয়ে যান', 'Sign out');
  static String get menu => _t('মেনু', 'Menu');
  static String get copyToMobile => _t('মোবাইলেও এই নম্বর দিন', 'Use this number as the mobile number too');
  static String get copyToWhatsApp => _t('WhatsApp-এও এই নম্বর দিন', 'Use this number as the WhatsApp number too');

  // Sign in
  static String get loginTitle => _t('প্রবেশ করুন', 'Sign in');
  static String get chooseUser => _t('আপনি কে?', 'Who are you?');
  static String get pinLabel => _t('PIN (৪-৬ সংখ্যা)', 'PIN (4-6 digits)');
  static String get signIn => _t('ঢুকুন', 'Sign in');
  static String get setupTitle => _t('দোকান চালু করুন', 'Set up the shop');
  static String get setupIntro => _t('প্রথমে মালিকের নাম ও PIN দিন। পরে কর্মী যোগ করতে পারবেন।', 'First enter the owner name and PIN. You can add staff later.');
  static String get ownerName => _t('মালিকের নাম', 'Owner name');
  static String get pinConfirm => _t('PIN আবার লিখুন', 'Enter the PIN again');
  static String get pinMismatch => _t('দুটি PIN মিলছে না', 'The two PINs do not match');
  static String get createOwner => _t('শুরু', 'Start');
  static String get noActiveUsers => _t('কেউ ঢুকতে পারবেন না। মালিকের সাথে কথা বলুন।', 'Nobody can sign in. Talk to the owner.');
  static String get roleOwner => _t('মালিক', 'Owner');
  static String get roleStaff => _t('কর্মী', 'Staff');
  static String get authInvalidName => _t('নাম লিখুন', 'Enter a name');
  static String get authInvalidPin => _t('PIN ৪ থেকে ৬ সংখ্যার হতে হবে', 'The PIN must be 4 to 6 digits');
  static String get authNameTaken => _t('এই নামে আগেই একজন আছেন', 'Someone already has this name');
  static String get authWrongPin => _t('PIN ভুল', 'Wrong PIN');
  static String get authUnknownUser => _t('ব্যবহারকারী পাওয়া যায়নি', 'User not found');
  static String get authInactive => _t('এই ব্যবহারকারী বন্ধ আছেন', 'This user has been switched off');
  static String get authLastOwner => _t('শেষ মালিককে বন্ধ করা যাবে না', 'The last owner cannot be switched off');

  // My profile
  static String get profileTitle => _t('আমার প্রোফাইল', 'My profile');
  static String get profileDetails => _t('আমার তথ্য', 'My details');
  static String get profileMobile => _t('মোবাইল নম্বর', 'Mobile number');
  static String get profilePhone => _t('অন্য ফোন নম্বর', 'Other phone number');
  static String get profileAddress => _t('ঠিকানা', 'Address');
  static String get profileSaved => _t('সংরক্ষিত হয়েছে', 'Saved');
  static String get profilePinSection => _t('PIN বদলান', 'Change PIN');
  static String get currentPinLabel => _t('এখনকার PIN', 'Current PIN');
  static String get authInvalidPhone => _t('ফোন নম্বর সঠিক নয়', 'The phone number is not valid');

  // Staff
  static String get usersTitle => _t('কর্মী', 'Staff');
  static String get addUser => _t('নতুন কর্মী', 'New staff');
  static String get userName => _t('নাম', 'Name');
  static String get resetPin => _t('PIN বদলান', 'Change PIN');
  static String get newPinLabel => _t('নতুন PIN (৪-৬ সংখ্যা)', 'New PIN (4-6 digits)');
  static String get switchOff => _t('বন্ধ করুন', 'Switch off');
  static String get switchOn => _t('চালু করুন', 'Switch on');
  static String get inactiveChip => _t('বন্ধ', 'Off');
  static String get youChip => _t('আপনি', 'You');
  static String get userAdded => _t('যোগ হয়েছে', 'Added');
  static String get pinChanged => _t('PIN বদলেছে', 'PIN changed');

  // Settings
  static String get settingsTitle => _t('সেটিংস', 'Settings');
  static String get shopNameSection => _t('দোকানের নাম', 'Shop name');
  static String get shopNameLabel => _t('দোকানের নাম', 'Shop name');
  static String get shopNameHelp => _t('এই নাম মেনুর উপরে ও রসিদে দেখাবে। সব ফোনেই একই নাম থাকবে।', 'This name shows at the top of the menu and on receipts. Every phone shows the same name.');
  static String get shopNameSaved => _t('দোকানের নাম বদলেছে', 'Shop name changed');
  static String get shopNameEmpty => _t('দোকানের নাম লিখুন', 'Enter the shop name');
  static String get shopNameTooLong => _t('নাম অনেক লম্বা (সর্বোচ্চ ৬০ অক্ষর)', 'The name is too long (at most 60 characters)');
  static String activityShopRenamed(String name) =>
      Language.isBangla ? 'দোকানের নাম বদলেছেন: $name' : 'Renamed the shop: $name';
  static String get sellAtPrice => _t('বিক্রয় দাম', 'Selling price');
  static String get sellAtCost => _t('কেনা দামে (লাভ ছাড়া)', 'At buying price (no profit)');
  static String get noProfit => _t('লাভ ছাড়া বিক্রি', 'Sold with no profit');
  static const languageSection = 'ভাষা / Language';
  static const languageBangla = 'বাংলা';
  static const languageEnglish = 'English';
  static String get languageHelp => _t(
      'এটি শুধু এই ফোনের জন্য। গ্রাহকের রসিদ সবসময় বাংলায় যাবে।',
      'This is for this phone only. Receipts sent to customers are always in Bangla.');
  static String get themeSection => _t('থিম', 'Theme');
  static String get themeSystem => _t('সিস্টেম', 'System');
  static String get themeLight => _t('আলো', 'Light');
  static String get themeDark => _t('অন্ধকার', 'Dark');
  static String get themeHelp => _t('এটি শুধু এই ফোনের জন্য।', 'This is for this phone only.');

  // Who did it
  static String get soldByLabel => _t('বিক্রেতা', 'Sold by');
  static String get receivedByLabel => _t('নিয়েছেন', 'Taken by');
  static String get navCustomers => _t('গ্রাহক', 'Customers');

  // Customers
  static String get customersTitle => _t('গ্রাহক', 'Customers');
  static String get customerSearchHint => _t('নাম বা নম্বর দিয়ে খুঁজুন', 'Search by name or number');
  static String get customerFilterAll => _t('সব', 'All');
  static String get customerFilterDue => _t('বাকি আছে', 'Owes money');
  static String get noCustomers => _t('এখনো কোনো গ্রাহক নেই। প্রথম বিক্রির পর গ্রাহক এখানে আসবে।', 'No customers yet. Customers appear here after the first sale.');
  static String get noCustomerMatch => _t('কোনো গ্রাহক পাওয়া যায়নি', 'No customer found');
  static String get customerDetailTitle => _t('গ্রাহকের বিবরণ', 'Customer details');
  static String get customerSpent => _t('মোট কেনা', 'Total bought');
  static String get customerPaid => _t('মোট পরিশোধ', 'Total paid');
  static String get customerDue => _t('বাকি', 'Due');
  static String get customerBills => _t('কতবার কিনেছেন', 'Times bought');
  static String get customerProducts => _t('কত রকম পণ্য', 'Different products');
  static String get customerLastBuy => _t('শেষ কেনা', 'Last purchase');
  static String get customerHistory => _t('কেনার ইতিহাস', 'Purchase history');
  static String get customerNoHistory => _t('কোনো কেনাকাটা নেই', 'No purchases');
  static String get customerInfoSection => _t('যোগাযোগ', 'Contact');
  static String get customerNidLabel => _t('NID', 'NID');
  static String get customerNotFound => _t('গ্রাহক পাওয়া যায়নি', 'Customer not found');
  static String get customerPeopleDue => _t('মোট বাকি', 'Total due');

  // Collecting dues
  static String get collectPayment => _t('টাকা নিন', 'Take money');
  static String get collectTitle => _t('বাকির টাকা নিন', 'Take money for a due');
  static String get collectAmountLabel => _t('কত টাকা পেলেন', 'How much did you receive');
  static String get collectConfirm => _t('টাকা নিলাম', 'Received');
  static String get payInvalidAmount => _t('সঠিক টাকার অঙ্ক লিখুন', 'Enter a valid amount');
  static String get payExceedsDue => _t('বাকির চেয়ে বেশি নেওয়া যাবে না', 'Cannot take more than the due');
  static String get payUnknownCustomer => _t('গ্রাহক পাওয়া যায়নি', 'Customer not found');
  static String get paymentHistory => _t('টাকা নেওয়ার ইতিহাস', 'Payment history');
  static String get noPayments => _t('এখনো কোনো বাকি আদায় হয়নি', 'No dues collected yet');
  static String get paymentReceivedTitle => _t('টাকা নেওয়া হয়েছে', 'Money received');
  static String get sendPaymentReceipt => _t('রসিদ পাঠান', 'Send receipt');
  static String get paymentReceiptTitle => _t('টাকা গ্রহণের রসিদ', 'Payment receipt');
  static String get paymentReceivedLabel => _t('গ্রহণ', 'Received');
  static String get paymentRemainingLabel => _t('এখনো বাকি', 'Still due');
  static String get allDuePaid => _t('সব বাকি পরিশোধ হয়েছে', 'All dues are paid');
  static String get collectedLabel => _t('বাকি আদায়', 'Dues collected');
  static String get dashCollected => _t('বাকির টাকা পেয়েছি', 'Dues received');
  static String get dashNewDue => _t('এই সময়ের বাকি', 'Due in this period');
  static String paymentDone(double amount, double left) =>
      Language.isBangla ? left > 0 ? '${formatMoney(amount)} নেওয়া হয়েছে। এখনো বাকি ${formatMoney(left)}' : '${formatMoney(amount)} নেওয়া হয়েছে। আর কোনো বাকি নেই' : left > 0 ? '${formatMoney(amount)} received. Still due ${formatMoney(left)}' : '${formatMoney(amount)} received. Nothing more is due';
  static String customerCount(int n) =>
      Language.isBangla ? '${toBanglaDigits('$n')} জন গ্রাহক' : n == 1 ? '1 customer' : '$n customers';
  static String customerTimes(int n) =>
      Language.isBangla ? '${toBanglaDigits('$n')} বার' : n == 1 ? '1 time' : '$n times';

  // Dashboard
  static String get periodToday => _t('আজ', 'Today');
  static String get periodWeek => _t('৭ দিন', '7 days');
  static String get periodMonth => _t('৩০ দিন', '30 days');
  static String get dashSales => _t('বিক্রি', 'Sales');
  static String get dashProfit => _t('লাভ', 'Profit');
  static String get dashBills => _t('রসিদ', 'Bills');
  static String get dashAverageBill => _t('গড় রসিদ', 'Average bill');
  static String get dashSalesTrend => _t('দিনের বিক্রি', 'Sales by day');
  static String get dashTopProducts => _t('সেরা বিক্রির পণ্য', 'Best-selling products');
  static String get dashNoSales => _t('এই সময়ে কোনো বিক্রি নেই', 'No sales in this period');
  static String get dashReceivables => _t('বাকি আদায়', 'Dues to collect');
  static String get dashTotalDue => _t('মোট বাকি', 'Total due');
  static String get dashNoDue => _t('কারও কাছে বাকি নেই', 'Nobody owes anything');
  static String get dashStock => _t('মজুদের অবস্থা', 'Stock status');
  static String get dashStockCost => _t('মজুদের দাম (কেনা)', 'Stock value (cost)');
  static String get dashStockWorth => _t('মজুদের দাম (বিক্রি)', 'Stock value (selling)');
  static String get dashProducts => _t('মোট পণ্য', 'Total products');
  static String get dashOutOfStock => _t('মজুদ শেষ', 'Out of stock');
  static String get dashAllInStock => _t('সব পণ্য মজুদ আছে', 'Everything is in stock');
  static String get dashNeedsAttention => _t('নজর দিন', 'Needs attention');
  static String get dashMissingPrice => _t('দাম বসানো হয়নি', 'No price set');
  static String get dashUnplaced => _t('জায়গা ঠিক করা হয়নি', 'No location set');
  static String get dashVsBefore => _t('আগের সময়ের চেয়ে', 'Compared with before');
  static String get dashNoComparison => _t('আগের সময়ে বিক্রি ছিল না', 'No sales in the earlier period');
  static String get dashMore => _t('আরও', 'More');
  static String dashCustomers(int n) =>
      Language.isBangla ? '${toBanglaDigits('$n')} জন' : n == 1 ? '1 customer' : '$n customers';
  static String dashUp(String percent) =>
      Language.isBangla ? '▲ $percent বেশি' : '▲ $percent more';
  static String dashDown(String percent) =>
      Language.isBangla ? '▼ $percent কম' : '▼ $percent less';

  static String get restock => _t('মজুদ আনুন', 'Add stock');
  static String get restockQuantity => _t('কতটুকু এসেছে', 'How much arrived');
  static String get restockPrice => _t('নতুন কেনা দাম (ঐচ্ছিক)', 'New buying price (optional)');
  static String get restockWhere => _t('কোথায় রাখবেন', 'Where to put it');
  static String get restockLater => _t('পরে ঠিক করব', 'I will decide later');
  static String get restockDone => _t('মজুদ যোগ হয়েছে', 'Stock added');
  static String get editTotal => _t('মজুদ ঠিক করুন', 'Correct stock');

  static String get sellTitle => _t('বিক্রি', 'Sell');
  static String get sellSearch => _t('বিক্রির পণ্য খুঁজুন', 'Search products to sell');
  static String get sellMore => _t('আরও বিক্রি', 'More');
  static String get soldOut => _t('শেষ', 'Out');
  static String get quantity => _t('পরিমাণ', 'Quantity');
  static String get unitPrice => _t('একক দাম', 'Unit price');
  static String get saleTotal => _t('মোট', 'Total');
  static String get confirmSale => _t('নিশ্চিত করুন', 'Confirm');
  static String get sellFrom => _t('কোথা থেকে', 'Take from');
  static String get sellFromAny => _t('স্বয়ংক্রিয়', 'Automatic');
  static String get available => _t('মজুদ আছে', 'In stock');
  static String get noSellable => _t('বিক্রির জন্য কোনো পণ্য নেই', 'No products to sell');
  static String get undo => _t('বাতিল', 'Undo');

  static String soldMessage(String name, double total) =>
      Language.isBangla ? '$name বিক্রি হয়েছে • ${formatMoney(total)}' : '$name sold • ${formatMoney(total)}';
  static String addOneLabel(String unit) =>
      Language.isBangla ? '+ ১ $unit' : '+ 1 ${unitName(unit)}';

  static String get accountTitle => _t('দিনের হিসাব', 'Daily account');
  static String get totalSales => _t('মোট বিক্রি', 'Total sales');
  static String get totalProfit => _t('মোট লাভ', 'Total profit');
  static String get salesCount => _t('বিক্রির সংখ্যা', 'Number of sales');
  static String get today => _t('আজ', 'Today');
  static String get yesterday => _t('গতকাল', 'Yesterday');
  static String get noSalesThatDay => _t('এই দিনে কোনো বিক্রি নেই', 'No sales on this day');
  static String get voidSaleConfirm => _t('বিক্রি বাতিল করলে মজুদ ফিরে আসবে। বাতিল করবেন?', 'Cancelling a sale puts the stock back. Cancel it?');
  static String get voidSaleAction => _t('বিক্রি বাতিল', 'Cancel sale');
  static String get saleVoided => _t('বিক্রি বাতিল হয়েছে', 'Sale cancelled');
  static String get previousDay => _t('আগের দিন', 'Previous day');
  static String get nextDay => _t('পরের দিন', 'Next day');

  static String get reasonRestock => _t('মজুদ আনা', 'Stock added');
  static String get reasonSale => _t('বিক্রি', 'Sale');
  static String get reasonSaleVoid => _t('বিক্রি বাতিল', 'Sale cancelled');
  static String get stockInsufficient => _t('মজুদে এত পরিমাণ নেই।', 'There is not that much in stock.');

  // --- Cart, customer, payment, receipt ---
  static String get addToCart => _t('কার্টে যোগ করুন', 'Add to cart');
  static String get completeSale => _t('বিক্রি করুন', 'Sell');
  static String get checkoutTitle => _t('বিক্রি সম্পন্ন করুন', 'Complete sale');
  static String stockChangedElsewhere(String name, double left) => Language.isBangla
      ? (left <= 0
          ? 'অন্য ফোনে বিক্রি হয়ে থাকতে পারে: $name এখন আর নেই। কার্ট থেকে সরানো হয়েছে।'
          : 'অন্য ফোনে বিক্রি হয়ে থাকতে পারে: $name এখন মাত্র ${formatNumber(left)} আছে। কার্ট ঠিক করা হয়েছে।')
      : (left <= 0
          ? 'Another phone may have sold this: $name is out of stock now. Removed from the cart.'
          : 'Another phone may have sold this: only ${formatNumber(left)} of $name left. The cart was adjusted.');
  static String get cartTitle => _t('কার্ট', 'Cart');
  static String get cartIconTooltip => _t('কার্ট দেখুন', 'View cart');
  static String get cartEmpty => _t('কার্ট খালি', 'The cart is empty');
  static String get cartSell => _t('বিক্রি করুন', 'Sell');
  static String get cartCancel => _t('কার্ট বাতিল', 'Cancel cart');
  static String get cartCancelConfirm => _t('কার্টের সব পণ্য বাদ দেবেন? কিছু বিক্রি হবে না।', 'Remove everything from the cart? Nothing will be sold.');
  static String get cartCancelled => _t('কার্ট বাতিল করা হয়েছে', 'Cart cancelled');
  static String get contactShare => _t('শেয়ার করুন (যেকোনো অ্যাপে)', 'Share (on any app)');
  static String get cartLines => _t('কার্টের পণ্য', 'Items in cart');
  static String get removeFromCart => _t('কার্ট থেকে সরান', 'Remove from cart');
  static String cartSummary(int items, double total) =>
      Language.isBangla ? '${toBanglaDigits('$items')}টি পণ্য • ${formatMoney(total)}' : items == 1 ? '1 item • ${formatMoney(total)}' : '$items items • ${formatMoney(total)}';

  static String get customerSection => _t('গ্রাহকের তথ্য', 'Customer details');
  static String get customerAddress => _t('ঠিকানা', 'Address');
  static String get customerOptionalHint => _t('ঐচ্ছিক • সময় থাকলে গ্রাহকের তথ্য নিতে চাপুন', 'Optional • tap to take the customer\'s details when you have time');
  static String get customerPhone => _t('মোবাইল / WhatsApp নম্বর', 'Mobile / WhatsApp number');
  static String get customerPhoneHelp => _t(
      'গ্রাহকের WhatsApp নম্বর চেয়ে নিন: তাহলে রসিদ ও বাকির খবর WhatsApp-এ পাঠানো যাবে।',
      'Ask the customer for their WhatsApp number: then the receipt and due reminders can be sent on WhatsApp.');
  static String get contactCall => _t('ফোন করুন', 'Call');
  static String get contactSms => _t('এসএমএস পাঠান', 'Send SMS');
  static String get contactWhatsApp => _t('WhatsApp-এ পাঠান', 'Send on WhatsApp');
  static String get contactFailed => _t('খোলা যায়নি। নম্বরটি ঠিক আছে কিনা দেখুন।', 'Could not open it. Check the number.');
  static String get remindDue => _t('বাকির তাগাদা', 'Remind about due');
  static String dueReminder(String name, double due, String shop) => Language.isBangla
      ? '${name.isEmpty ? '' : '$name, '}আসসালামু আলাইকুম। $shop-এ আপনার ${formatMoney(due)} বাকি আছে। সুবিধামতো পরিশোধ করবেন। ধন্যবাদ।'
      : '${name.isEmpty ? '' : '$name, '}Assalamu alaikum. You have ${formatMoney(due)} due at $shop. Please pay when convenient. Thank you.';
  static String get customerWhatsApp => _t('WhatsApp নম্বর (রসিদ এখানে যাবে)', 'WhatsApp number (the receipt goes here)');
  static String get addressRequired => _t('ঠিকানা আবশ্যক', 'Address is required');
  static String get whatsAppRequired => _t('WhatsApp নম্বর আবশ্যক', 'WhatsApp number is required');
  static String get customerName => _t('গ্রাহকের নাম', 'Customer name');
  static String get customerMobile => _t('মোবাইল নম্বর', 'Mobile number');
  static String get customerNid => _t('জাতীয় পরিচয়পত্র (NID) নম্বর', 'National ID (NID) number');
  static String get customerNote => _t('গ্রাহকের তথ্য ঐচ্ছিক। পুরো টাকা না দিলে (বাকি) নাম, ঠিকানা, নম্বর ও NID আবশ্যক। NID রসিদে ছাপা হবে না।', 'Customer details are optional. If the full amount is not paid (a due), the name, address, number and NID are required. The NID is never printed on the receipt.');
  static String get knownCustomer => _t('পুরনো গ্রাহক: তথ্য বসানো হয়েছে', 'Returning customer: details filled in');
  static String get mobileInvalid => _t('সঠিক ১১ সংখ্যার মোবাইল নম্বর দিন (যেমন ০১৭১২৩৪৫৬৭৮)', 'Enter a valid 11-digit mobile number (e.g. 01712345678)');
  static String get nidInvalid => _t('NID নম্বর ১০, ১৩ বা ১৭ সংখ্যার হতে হবে', 'The NID must be 10, 13 or 17 digits');
  static String get requiredForDue => _t('বাকির জন্য এটি আবশ্যক', 'Required for a due');

  static String get paymentSection => _t('টাকা', 'Payment');
  static String get paidInFull => _t('পুরো টাকা পেয়েছি', 'Paid in full');
  static String get paidAmount => _t('কত টাকা পেয়েছি', 'How much was paid');
  static String get dueLabel => _t('বাকি', 'Due');
  static String get paidLabel => _t('পরিশোধ', 'Paid');
  static String get paidTooMuch => _t('মোট দামের বেশি নেওয়া যাবে না', 'Cannot take more than the total');

  static String get saleBillEmpty => _t('কার্টে কোনো পণ্য নেই।', 'There is nothing in the cart.');
  static String get saleContactRequired => _t('প্রতিটি বিক্রিতে গ্রাহকের WhatsApp নম্বর দিতে হবে।', 'Every sale needs the customer WhatsApp number.');
  static String get saleInvalidPayment => _t('টাকার পরিমাণ সঠিক নয়।', 'The amount is not valid.');
  static String get saleCustomerRequiredForDue => _t('বাকিতে বিক্রি করতে গ্রাহকের নাম, ঠিকানা, মোবাইল ও NID দিতে হবে।', 'To sell on credit, the customer name, address, mobile and NID are needed.');
  static String get saleInvalidCustomer => _t('মোবাইল বা NID নম্বর সঠিক নয়।', 'The mobile or NID number is not valid.');

  static String get receiptTitle => _t('রসিদ', 'Receipt');
  static String get receiptNo => _t('রসিদ নং', 'Receipt no.');
  static String get receiptThanks => _t('ধন্যবাদ! আবার আসবেন।', 'Thank you! Please come again.');
  static String get customerLabel => _t('গ্রাহক', 'Customer');
  static String get retailSale => _t('খুচরা বিক্রি', 'Retail sale');
  static String get sendWhatsApp => _t('WhatsApp', 'WhatsApp');
  static String get shareReceipt => _t('শেয়ার', 'Share');
  static String get receiptDone => _t('শেষ', 'Done');
  static String get whatsAppNumberLabel => _t('গ্রাহকের WhatsApp নম্বর', 'Customer WhatsApp number');
  static String get whatsAppFailed => _t('WhatsApp খোলা যায়নি। শেয়ার বাটন ব্যবহার করুন।', 'WhatsApp could not be opened. Use the share button.');
  static String get whatsAppBadNumber => _t('সঠিক মোবাইল নম্বর দিন।', 'Enter a valid mobile number.');
  static String get viewReceipt => _t('রসিদ দেখুন', 'View receipt');
  static String get dueTotal => _t('মোট বাকি', 'Total due');
  static String get saleDone => _t('বিক্রি হয়েছে', 'Sale done');

  /// The units a product can be sold in. These are stored in the database exactly as
  /// written here (Bangla), whatever the app's language, so every phone agrees.
  static const units = ['পিস', 'কেজি', 'ফুট', 'মিটার', 'লিটার', 'ক্যান', 'টিন', 'বক্স', 'কয়েল', 'রোল', 'জার', 'প্যাক', 'সেট', 'ডজন', 'শত', 'টন'];

  static const _unitsEnglish = {'পিস': 'pcs', 'কেজি': 'kg', 'ফুট': 'ft', 'মিটার': 'm', 'লিটার': 'L', 'ক্যান': 'can', 'টিন': 'tin', 'বক্স': 'box', 'কয়েল': 'coil', 'রোল': 'roll', 'জার': 'jar', 'প্যাক': 'pack', 'সেট': 'set', 'ডজন': 'dozen', 'শত': '100s', 'টন': 'ton'};

  /// How a stored unit is shown: as stored in Bangla, or in English.
  static String unitName(String stored) => Language.isBangla ? stored : (_unitsEnglish[stored] ?? stored);
}

const _bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Shows the digits in [input] the way the app is set to show numbers:
/// English digits (0-9) normally; Bangla digits only if [Language.englishDigits]
/// is off and the app is in Bangla.
String toBanglaDigits(String input) => Language.isBangla && !Language.englishDigits
    ? input.replaceAllMapped(RegExp(r'[0-9]'), (m) => _bnDigits[int.parse(m[0]!)])
    : input;

/// Formats a number for display (see [toBanglaDigits]), no trailing ".0".
String formatNumber(double value) {
  final text = value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);
  return toBanglaDigits(text);
}

String formatMoney(double value) => '${Bn.taka}${formatNumber(value)}';

/// The value 0-9 of a single Bangla digit, or null if [char] is not one.
int? banglaDigitValue(String char) {
  final i = _bnDigits.indexOf(char);
  return i == -1 ? null : i;
}

/// Parses user input, accepting both English and Bangla digits.
/// Returns null if the text is empty or not a valid non-negative number.
double? parseNumber(String? input) {
  if (input == null) return null;
  var s = input.trim();
  if (s.isEmpty) return null;
  for (var i = 0; i < _bnDigits.length; i++) {
    s = s.replaceAll(_bnDigits[i], '$i');
  }
  s = s.replaceAll(',', '').replaceAll('।', '.');
  final v = double.tryParse(s);
  return (v == null || v < 0) ? null : v;
}

/// "২২/১১/২০২৬ ১৫:৩৫" in Bangla digits.
String formatDateTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return toBanglaDigits('${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}');
}

/// "আজ", "গতকাল", or the date, relative to [now].
String dayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return Bn.today;
  if (diff == 1) return Bn.yesterday;
  String two(int n) => n.toString().padLeft(2, '0');
  return toBanglaDigits('${two(d.day)}/${two(d.month)}/${d.year}');
}

/// "১৫:৩৫" in Bangla digits.
String formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return toBanglaDigits('${two(t.hour)}:${two(t.minute)}');
}
