# Dokan Khata (দোকান খাতা)

An offline-first inventory and point-of-sale app for a small hardware shop, in
Bangla and English. Stock and locations (with QR labels), selling with a cart,
billing with dues, customers, WhatsApp receipts, staff logins with an activity
log, and an optional **sync database** so several phones share one shop.

Flutter app + a small Cloudflare Worker (`server/`) for the sync database.

## ব্যবহার নির্দেশিকা (বাংলায়)

এই অ্যাপ দিয়ে দোকানের মজুদ, বিক্রি, বাকি ও হিসাব ফোনেই রাখা যায়। ইন্টারনেট না থাকলেও চলে। একাধিক ফোনে একই দোকান চালাতে চাইলে শেষের "একাধিক ফোনে দোকান চালানো" অংশ দেখুন।

### ১. প্রথমবার চালু করা

1. অ্যাপ খুললে **"দোকান চালু করুন"** পাতা আসবে। মালিকের নাম ও **PIN** (৪ থেকে ৬ সংখ্যা) দিন। PIN মনে রাখুন, এটি ছাড়া ঢোকা যাবে না।
2. পরের বার থেকে **"প্রবেশ করুন"** পাতায় নিজের নাম বেছে PIN দিলেই হবে।
3. মালিক সবকিছু করতে পারেন। কর্মী সব পাতা দেখতে পারেন ও বিক্রি করতে পারেন, কিন্তু নতুন কর্মী যোগ, PIN বদল, দোকানের নাম বদল ও সব তথ্য মোছা শুধু মালিক করতে পারেন।

### ২. অ্যাপের পাতাগুলো

উপরে বাঁ দিকের **≡ (মেনু)** চাপলে পাতাগুলো দেখা যাবে:

| পাতা | কী কাজ |
|---|---|
| **ড্যাশবোর্ড** | আজকের বিক্রি, লাভ, বাকি ইত্যাদির সারাংশ (আজ / ৭ দিন…) |
| **মজুদ** | সব পণ্য, দাম ও কতটা আছে; নতুন পণ্য যোগ |
| **বিক্রি** | পণ্য বেছে কার্টে তুলে বিক্রি করা |
| **গ্রাহক** | যাঁরা কিনেছেন, কার কত বাকি, টাকা নেওয়া |
| **হিসাব** | দিনের বিল ও মোট হিসাব, ভুল বিল বাতিল |
| স্থান সমূহ, ক্যাটাগরি সমূহ | তাক/গুদাম ও পণ্যের ধরন বানানো ও বদলানো |
| কর্মী | নতুন কর্মী যোগ, PIN বদল, বন্ধ করা (শুধু মালিক বদলাতে পারেন) |
| কর্মীদের কাজ | কে কখন কী করেছেন, সবাই দেখতে পারেন |
| আমার প্রোফাইল | নিজের নাম, ফোন, ঠিকানা, PIN |
| সেটিংস | ভাষা, থিম, দোকানের নাম, সিঙ্ক ডাটাবেস, সব তথ্য মুছুন |

কার্টে পণ্য থাকলে প্রতিটি পাতার উপরে ডানে **কার্টের আইকন** দেখা যায়, গায়ে কয়টি পণ্য আছে তার সংখ্যা লেখা থাকে। চাপলে কার্ট খোলে।

### ৩. দোকান সাজানো (একবার করলেই হয়)

**ক্যাটাগরি:** নতুন দোকানে শুরুতে একটি ক্যাটাগরি থাকে: *General*। মেনু → **ক্যাটাগরি সমূহ** থেকে নিজের ক্যাটাগরি যোগ করুন (যেমন পাইপ, পেরেক, রং)। নামের পাশের **পেন্সিল** চাপলে নাম বদলানো যায়, পণ্য থাকলেও।

**স্থান:** মেনু → **স্থান সমূহ** → **নতুন স্থান**। নাম দিন (যেমন "তাক ১", "বাম দেয়াল") আর ধরন বাছুন: তাক, মেঝে, গুদাম, উঠান। নিজের ধরন লাগলে **"নতুন ধরন"** চেপে নাম দিন (যেমন আলমারি)। প্রতিটি স্থানের একটি **QR কোড** থাকে: স্থানে ট্যাপ করে QR দেখে প্রিন্ট করে তাকে লাগিয়ে রাখুন। পরে **QR স্ক্যান** করলে সেই স্থানের পণ্য খুলে যায়।

- **পেন্সিল** দিয়ে স্থানের নাম বা ধরন বদলানো যায় (পণ্য থাকলেও; QR একই থাকে)।
- উপরের **ট্যাগ আইকন** দিয়ে নিজের বানানো ধরনের নাম বদলানো বা মোছা যায় (মুছলে সেই স্থানগুলো "তাক" হয়ে যায়)।
- যে স্থানে পণ্য আছে সেটি মোছা যায় না। আগে পণ্য সরাতে হবে।

### ৪. পণ্য যোগ করা ও মজুদ

1. **মজুদ** পাতা → নিচে **নতুন পণ্য**।
2. পণ্যের নাম লিখুন। **ধরন** বাছুন:
   - **খোলা / ওজনে**: কেজি, মিটার বা লিটারে বিক্রি হয় (আধা কেজিও বিক্রি করা যায়);
   - **সাধারণ**: পিস হিসাবে;
   - **বড় / দামি**: পাম্প, ট্যাংকের মতো, কম সংখ্যায়।
3. ক্যাটাগরি ও স্থান বাছুন। ক্যাটাগরির পাশের **+** দিয়ে নতুন ক্যাটাগরি, স্থানের পাশের **+** দিয়ে নতুন স্থান ওখান থেকেই বানানো যায়। QR আইকন দিয়ে তাকের QR স্ক্যান করেও স্থান ঠিক করা যায়।
4. **কেনা দাম**, **বিক্রি দাম**, **মজুদ** (কতটা আছে) ও **একক** দিন। সংরক্ষণ করুন। একই ধরনের অনেক পণ্য দিতে **"সংরক্ষণ + নতুন"** ব্যবহার করুন।

পরে পণ্যে ট্যাপ করলে:
- **মজুদ আনুন**: নতুন মাল এলে তা যোগ করুন (চাইলে নতুন কেনা দামও দেওয়া যায়)।
- **মজুদ ঠিক করুন**: গুনে দেখে মোট ঠিক করুন।
- **স্থান ও মজুদ বণ্টন**: মাল কোন তাকে কতটা আছে। এখানে **গণনা করে ঠিক করুন**, **অন্য স্থানে সরান** বা নতুন স্থান যোগ করা যায়।

উপরের সার্চ বক্স ও ক্যাটাগরির বোতাম দিয়ে পণ্য খুঁজে বের করুন।

### ৫. বিক্রি করা

1. মেনু → **বিক্রি**। নাম লিখে পণ্য খুঁজুন।
2. **দ্রুত বিক্রি:** পণ্যের পাশের **"+ ১"** চাপলে ১ একক কার্টে ওঠে।
3. **দাম বা পরিমাণ বদলে বিক্রি:** পণ্যে ট্যাপ করুন। নিচে একটি পপ-আপ আসবে, যেখানে **বিক্রি দাম** ও **কেনা দাম** দুটোই দেখা যায়।
   - পরিমাণ লিখুন বা **+ / −** চাপুন। খোলা পণ্যে **¼, ½, ১** বোতামে এক ট্যাপে ঠিক করা যায়। যেমন ১ কেজি মজুদ থেকে আধা কেজি বিক্রি: **½** চাপুন, দাম আপনিই আধা হবে।
   - দাম বদলাতে পারেন। **"কেনা দামে (লাভ ছাড়া)"** চাপলে কেনা দামে বিক্রি হবে।
   - মাল একাধিক স্থানে থাকলে কোন স্থান থেকে নেবেন তা বাছতে পারেন।
   - **কার্টে যোগ করুন** চাপুন।
4. উপরের **কার্ট আইকন** (বা নিচের বার) চাপলে **কার্ট** খোলে: পরিমাণ বাড়ান/কমান, পণ্য বাদ দিন। এখানে দুটি বোতাম:
   - **বিক্রি করুন**: বিক্রির পাতায় যান;
   - **বাতিল**: কার্টের সব পণ্য বাদ (আগে জিজ্ঞেস করবে, কিছু বিক্রি হবে না)।

> **একাধিক ফোনে চালালে:** বিক্রির পাতা, কার্ট ও বিক্রি সম্পন্ন করার আগে অ্যাপ নিজে থেকে দেখে নেয় অন্য ফোনে কিছু বিক্রি হয়েছে কিনা। হয়ে থাকলে লিখে জানায়, যেমন "অন্য ফোনে বিক্রি হয়ে থাকতে পারে: … এখন মাত্র ২ আছে", আর কার্ট ঠিক করে দেয়।

### ৬. বিক্রি সম্পন্ন করা

কার্ট থেকে **বিক্রি করুন** চাপলে বিক্রির শেষ পাতা আসে।

- **পুরো টাকা পেয়েছি** চালু থাকলে (ডিফল্ট) কিছু লিখতে হয় না। নিচে **"গ্রাহকের তথ্য"** অংশটি ছোট হয়ে থাকে। সময় থাকলে এটি চেপে গ্রাহকের নাম, নম্বর, ঠিকানা নিয়ে রাখুন (সবই ঐচ্ছিক)। নম্বর হিসেবে **WhatsApp নম্বর** চেয়ে নিন, তাহলে রসিদ সহজে পাঠানো যায়। নম্বরের ঘরের পাশের **কন্টাক্ট আইকন** চেপে ফোনের কন্টাক্ট থেকে গ্রাহককে বেছে নিলে নাম ও নম্বর নিজে থেকে বসে যায়। এজন্য অ্যাপের কোনো অনুমতি লাগে না: ফোনের নিজের তালিকা খোলে, আর শুধু আপনার বাছাই করা একজনের তথ্য অ্যাপ পায়।
- **বাকিতে বিক্রি:** **পুরো টাকা পেয়েছি** বন্ধ করুন। **কত টাকা পেয়েছি** লিখুন (কিছু না পেলে ফাঁকা রাখুন), নিচে কত **বাকি** তা দেখাবে, আর গ্রাহকের তথ্য আপনিই খুলে যাবে। বাকির জন্য **নাম, মোবাইল/WhatsApp নম্বর, ঠিকানা ও NID** দিতেই হবে। (পুরনো গ্রাহকের নম্বর লিখলে বাকি তথ্য আপনিই বসে যায়।) NID রসিদে ছাপা হয় না।
- শেষে **নিশ্চিত করুন** চাপুন।

### ৭. রসিদ

বিক্রির পরে রসিদ আসে। **WhatsApp** চাপলে গ্রাহকের নম্বরে WhatsApp খুলে রসিদ তৈরি হয়ে থাকবে, আপনি শুধু Send চাপবেন। **শেয়ার** দিয়ে যেকোনো অ্যাপে পাঠানো যায়। নম্বর না থাকলে অ্যাপ নম্বর চাইবে। রসিদ সবসময় বাংলায় যায়, অ্যাপ ইংরেজিতে থাকলেও।

**গ্রাহক ছাড়া বিক্রি হয়ে গেলে?** পরে যোগ করা যায়। রসিদের নিচে **গ্রাহক যোগ করুন** চাপুন (অথবা **হিসাব** পাতায় ওই বিলের কার্ডে একই বোতাম)। নম্বর দিতেই হবে (WhatsApp নম্বর হলে ভালো); নাম, ঠিকানা, NID ঐচ্ছিক। পুরনো গ্রাহকের নম্বর দিলে তাঁর রেকর্ডেই বিলটি যুক্ত হয়। যে বিলে গ্রাহক আছে সেটি বদলাতে পারেন শুধু মালিক (**গ্রাহক বদলান**)। সব ফোনে একসঙ্গে বদলে যায়, আর কে যোগ করলেন তা **কাজের তালিকায়** থাকে।

### ৮. গ্রাহক ও বাকি আদায়

- **গ্রাহক** পাতায় সবার তালিকা। নাম বা নম্বর দিয়ে খুঁজুন; **"বাকি আছে"** চাপলে শুধু যাদের বাকি আছে তারা আসবে।
- কার্ডে নম্বর থাকলে ছোট **ফোন** ও **শেয়ার** আইকন থাকে: ফোন চাপলে কল হয়, শেয়ার চাপলে যেকোনো অ্যাপে (WhatsApp, SMS…) বাকির তাগাদার বার্তা পাঠানো যায়। (যাঁর বাকি নেই তাঁর শুধু ফোন আইকন থাকে।)
- গ্রাহকের নামে ট্যাপ করলে তাঁর সব কেনাকাটা, জমা দেওয়া টাকা ও বাকি দেখা যায়। বাকি থাকলে **টাকা নিন** চাপুন, কত পেলেন লিখুন (কম হলেও চলবে)। টাকা নেওয়ার সঙ্গে সঙ্গে নতুন **টাকা গ্রহণের রসিদ** খুলে যায়: **WhatsApp** বা **শেয়ার** দিয়ে গ্রাহককে পাঠান। এই রসিদ **হিসাব** পাতায়ও থাকে (নিচে দেখুন)।

### ৯. হিসাব

**হিসাব** পাতায় দিন ধরে (← →) বিল ও মোট বিক্রি দেখা যায়। বিলে ট্যাপ করলে রসিদ খোলে (আবার পাঠানো যায়)। যে বিলে বাকি আছে, সেখানেও ফোন ও শেয়ার আইকন আছে। সেই বিলেই **টাকা নিন** বোতাম আছে: চাপলে গ্রাহকের মোট বাকি দেখায়, কত পেলেন লিখুন (কম হলেও চলবে), আর নতুন টাকা গ্রহণের রসিদ খুলে যায়। টাকা সবসময় গ্রাহকের সবচেয়ে পুরনো বাকি বিল থেকে কাটা হয় (গ্রাহক পাতার মতোই)। বাকির টাকা নেওয়া হলে সেটিও ওই দিনের তালিকায় (সবুজ টাকাসহ, কত বাকি রইল তাসহ) আসে; চাপলে তার রসিদ খোলে ও আবার পাঠানো যায়। (টাকা নেওয়া মুছে ফেলা যায় না, শুধু ভুল **বিলই** বাতিল করা যায়।) **ভুল বিল বাঁ দিকে টেনে বাতিল** করুন: মজুদ ফিরে আসবে।

### ১০. কর্মী

মালিক: মেনু → **কর্মী** → **নতুন কর্মী** (নাম ও PIN দিন)। কর্মীর নামে ট্যাপ করে **PIN বদলান** বা **বন্ধ করুন** (বন্ধ হলে ঢুকতে পারবেন না, কিন্তু তাঁর করা কাজের হিসাব থেকে যাবে)। **কর্মীদের কাজ** পাতায় কে কী করেছেন সবাই দেখতে পারেন।

### ১১. সেটিংস

- **ভাষা:** বাংলা বা English (শুধু এই ফোনের জন্য)।
- **থিম:** সিস্টেম, আলো বা অন্ধকার।
- **দোকানের নাম** (মালিক): মেনুর উপরে ও রসিদে এই নাম দেখায়।
- **সিঙ্ক ডাটাবেস:** একাধিক ফোনে একই দোকান (নিচে দেখুন)।
- **সব তথ্য মুছুন** (শুধু মালিক): নিচে "সাবধান" দেখুন।

### ১২. একাধিক ফোনে দোকান চালানো (সিঙ্ক ডাটাবেস)

একই দোকানের দুই বা বেশি ফোনে একই মজুদ ও হিসাব দেখতে চাইলে এটি করুন। (একটি ফোনেই চালালে এটি লাগবে না।) প্রতিটি দোকানের একটি আলাদা **গোপন কী (Key)** থাকে। কী কীভাবে বানাতে হয় তা নিচের "Shop keys" অংশে আছে। কী শুধু মালিক ও বিশ্বস্ত কর্মীকে দিন।

1. **মালিকের ফোনে:** সেটিংস → **সিঙ্ক ডাটাবেস** → গোপন কী লিখুন → **তথ্য শেয়ার করুন**।
2. **কর্মীর ফোনে:** অ্যাপ নতুন ইনস্টল করে (কোনো তথ্য না বসিয়ে) শুরুর পাতায় **"চালু দোকানে যুক্ত হন"** চাপুন, কী দিন, **যুক্ত হন** চাপুন। দোকানের সব তথ্য নেমে আসবে।
3. এরপর যেকোনো ফোনে বিক্রি বা বদল করলে বাকি ফোনে তা দেখা যায়।

জেনে রাখুন:
- দেখা, খোঁজা ও পাতা খোলা ইন্টারনেট ছাড়াই চলে। **বিক্রি বা কোনো বদল সেভ করতে ইন্টারনেট লাগে**, কারণ সব ফোনের মজুদ একই রাখতে হয়। ইন্টারনেট না থাকলে অ্যাপ জানাবে, আর কিছু সেভ হবে না।
- অ্যাপ নিজে নিজে বারবার সার্ভারে খোঁজে না। খোলার সময়, ফিরে আসার সময়, বদল করার সময় এবং বিক্রির মুহূর্তে (বিক্রির পাতা, পণ্য বাছা, কার্ট, বিক্রি সম্পন্ন) দেখে নেয়। হাতে মেলাতে চাইলে সেটিংস → সিঙ্ক ডাটাবেস → **মিলান**।
- দুই ফোন একই শেষ পণ্য একসাথে বেচতে চাইলে একটিই সফল হবে; অন্যটি "মজুদে এত পরিমাণ নেই" জানাবে।

### ১৩. সাবধান: সব তথ্য মুছুন

সেটিংস → **সব তথ্য মুছুন...** (শুধু মালিক)। এটি পণ্য, বিক্রি, গ্রাহক, বাকি, কর্মী ও কাজের তালিকা, সবকিছু **চিরতরে** মুছে দেয়, ফেরত আনা যায় না। চালানোর আগে সতর্কবার্তা আসে, একটি বাক্সে টিক দিয়ে "আমি সম্পূর্ণ সচেতন…" নিশ্চিত করতে হয় এবং `ERASE` লিখতে হয়। দোকান শেয়ার করা থাকলে সার্ভারের কপিও মুছে যায়, আর অন্য ফোনগুলো পরের বার ইন্টারনেট পেলে খালি হয়ে যায়। ইন্টারনেট না থাকলে কিছুই মোছা হয় না।

### ১৪. সমস্যা হলে

| সমস্যা | কী করবেন |
|---|---|
| PIN ভুলে গেছেন (কর্মী) | মালিককে বলুন: কর্মী → নামে ট্যাপ → PIN বদলান |
| "ইন্টারনেট নেই" | সংযোগ ফিরলে আবার চেষ্টা করুন; সেভ হয়নি |
| "মজুদে এত পরিমাণ নেই" | অন্য ফোনে বিক্রি হয়ে গেছে বা মজুদ কম; পরিমাণ কমান বা মজুদ ঠিক করুন |
| "কী (Key) ভুল" | কী ভুল লেখা বা বদলে গেছে; মালিকের কাছ থেকে ঠিক বা নতুন কী নিন |
| "অ্যাপের নতুন সংস্করণ লাগবে" | অন্য ফোনে নতুন সংস্করণ চলছে; এই ফোনেও নতুন APK ইনস্টল করুন |

---

## Run the app

```
flutter pub get
flutter run          # on a connected phone or emulator
flutter test         # all tests
flutter analyze
```

## Generate the APK

```
dart run tool/build_apk.dart
```

Every time you run it, it **raises the version first** (patch and build number,
for example `1.0.0+1` becomes `1.0.1+2`), writes it to `pubspec.yaml` (so the
app shows it at the bottom of the menu), builds the release APK, and puts the
version in the file name:

```
build/app/outputs/flutter-apk/dokan-khata-1.0.1-build2.apk
```

Options:

```
dart run tool/build_apk.dart --minor      # 1.0.5+9 -> 1.1.0+10
dart run tool/build_apk.dart --major      # 1.4.2+9 -> 2.0.0+10
dart run tool/build_apk.dart --no-bump    # build again at the current version
```

If the build fails, the version is put back, so a failed build never uses up a
number. The script finds Flutter on your PATH; if it is not there, set the
`FLUTTER` environment variable to the full path of the `flutter` command. Use a
fresh version for every APK you hand out: Android only updates an app to a
higher build number. (Plain `flutter build apk --release` also works, but it
does not raise the version or rename the file.)

Release builds are signed with the debug key until a real keystore is added.
Keep that keystore safe once there is one: phones can only update an app that
is signed with the same key.

## How sharing works

Every phone keeps its own copy of the data and works with no signal. When a
shop is shared, each change is added to one ordered log on the server, and every
phone replays that log, so all phones end up the same. The server only stores
the log; it knows nothing about products or stock. Each shop has its **own
log and its own shop key**; one server can hold many shops, and a shop can never
see another's data.

The app asks the server only when it opens, when you return to it, after a
change, and at sale moments (opening the sell screen, picking a product,
opening the cart or checkout). There is no background timer.

## Shop keys

A **shop key** is the password of one shop's log. Whoever has it can read and
change that shop's data, so give it only to the shop's owner and staff.

Keys are made on **your own computer** with the admin tool. The server stores
only a hash of each key, so a key cannot be looked up later: it is shown once
(saved to a file) when it is made. Phones never need a Cloudflare account.

### One-time server setup

You need Node 18+, a Cloudflare account, and `wrangler` 3.

```
cd server
npm install
npx wrangler@3 login
npx wrangler@3 d1 create hardware-shop       # put the printed database_id in wrangler.toml
```

Make an **admin key** (a long random secret that lets you create shops), keep it
in `server/ADMIN_KEY.txt`, and store it on the server:

```
node -e "console.log(require('crypto').randomBytes(24).toString('hex'))" > ADMIN_KEY.txt
npx wrangler@3 secret put ADMIN_KEY < ADMIN_KEY.txt
npx wrangler@3 deploy
```

Put the server's address (printed by `deploy`, like
`https://hardware-shop-sync.<you>.workers.dev`) in `lib/core/app_config.dart`
(`defaultSyncUrl`) before building the APK, and in `server/SERVER_URL.txt` so the
admin tool finds it.

### Create a shop and its key

From the `server` folder:

```
node tools/shop.mjs create "Hasan Hardware"
```

This creates the shop, prints its id, and saves its key to
`server/shops/<id>.txt` (the key itself is never printed). Give that key to the
shop's owner yourself (in person or a private message).

Other commands:

```
node tools/shop.mjs list              # every shop and how many changes it holds
node tools/shop.mjs new-key <id>      # a new key; the old one stops working at once
```

### Use the key on the phones

1. **Owner's phone:** *Settings → Sync database*, enter the shop key, and tap
   *Share this phone's data*. The server address is already filled in.
2. **Staff phones:** install the app on a fresh phone, and *Settings → Sync
   database* (or the join screen) with the same key; the shop is downloaded.

If a key leaks or is lost, run `new-key <id>` and give the new key to the phones
(they will show "key rejected" until they have it).

### Notes

- The shop that existed before the server held many shops is called `main`; its
  original key (the old `SHOP_KEY` secret) still works.
- The owner can erase everything from *Settings → Erase all data*. For a shared
  shop this erases the server copy too, and every other phone empties itself the
  next time it connects.
- Never commit keys. `server/.gitignore` already excludes `*.txt`, `.dev.vars`,
  `shops/`, and backups. `server/test/worker.test.mjs` is for a **local** server
  only (`wrangler dev --local`); never run it against the real one.
- Back up before changing the server: `npx wrangler@3 d1 export hardware-shop --remote --output backup.sql`.

## Set up a new computer (lost or replaced laptop)

Everything in the code is on GitHub, so a new computer can build the app again.
A few things are **not** in the code on purpose (secrets), and they only exist
on the old computer. Read "Back up these files" first, ideally **before** you
ever need it.

### Back up these files (keep a copy off the laptop)

Put them in a password manager or an encrypted cloud folder. Never in git.

| File on the old computer | What it is | If you lose it |
|---|---|---|
| `server/ADMIN_KEY.txt` | Lets you create shops and make new keys | Make a new one and store it on the server (step 8) |
| `server/shops/*.txt` | The key of each shop | Make a new key with `new-key <id>`; every phone must enter it again |
| `server/SERVER_URL.txt` (if present) | Server address | Not secret; it is in `lib/core/app_config.dart` |
| `%USERPROFILE%\.android\debug.keystore` | The key that signs the APK | New APKs will **not update** the app already installed on phones; they must uninstall first (their copy comes back from the server only if they were synced) |
| `%USERPROFILE%\.ssh\id_rsa_personal` (and `.pub`) | Your GitHub login key | Make a new SSH key and add it on GitHub |

The Cloudflare account and the live database are online, so they are not lost
with the laptop. Shop data is safe on the server and on every synced phone.

### Steps

1. **Install the tools** (Windows):
   - [Git](https://git-scm.com/download/win) (it includes Git Bash)
   - [Flutter](https://docs.flutter.dev/get-started/install) (Dart comes with it). The project was built with Flutter 3.50 / Dart 3.14. Unzip it, for example to `C:\src\flutter`, and add `C:\src\flutter\bin` to the PATH.
   - [Android Studio](https://developer.android.com/studio): open it once and let it install the **Android SDK**, platform tools and the bundled Java (JDK 21). Then in a terminal run `flutter doctor --android-licenses` and accept everything.
   - [Node.js](https://nodejs.org) 18 or newer (only for the server tools).
   - [VS Code](https://code.visualstudio.com) with the *Flutter* extension (optional, but it is what the project is edited in).
2. **Check the setup:** `flutter doctor`. Fix anything marked with a red cross.
3. **Get your GitHub login back.** Copy your old SSH key files into `%USERPROFILE%\.ssh\`, or make a new key (`ssh-keygen -t ed25519`) and add its `.pub` text on GitHub under *Settings → SSH keys*. The repository was pushed with the host name `github.com-personal`, so put this in `%USERPROFILE%\.ssh\config` (change the key file name if yours differs):
   ```
   Host github.com-personal
     HostName github.com
     User git
     IdentityFile ~/.ssh/id_rsa_personal
   ```
   Test it with `ssh -T git@github.com-personal`.
4. **Get the code:**
   ```
   git clone git@github.com-personal:ShimantoKabir/ShopApp.git hardware-shop-app
   cd hardware-shop-app
   git config user.name "Your Name"
   git config user.email "you@example.com"
   ```
5. **Fetch the packages and run the checks:**
   ```
   flutter pub get
   flutter analyze
   flutter test
   ```
   All tests should pass (two are skipped on purpose; they need a local server).
6. **Run on a phone:** turn on *Developer options → USB debugging* on the phone, connect it, then `flutter devices` and `flutter run`. Or start an emulator from Android Studio.
7. **Put the signing key back** (so new APKs can update the phones). Copy the backed-up `debug.keystore` to `%USERPROFILE%\.android\debug.keystore` **before** the first release build. If Flutter has already made a new one there, overwrite it. Then build as usual with `dart run tool/build_apk.dart`.
8. **Server tools** (only needed to create shops or change the server):
   ```
   cd server
   npm install
   npx wrangler@3 login
   ```
   `login` opens a browser; sign in to the same Cloudflare account. Copy `ADMIN_KEY.txt`, `SERVER_URL.txt` and the `shops` folder back into `server/`. Check with `node tools/shop.mjs list`; you should see your shops.
   - **No backup of the admin key?** Make a new one and store it on the server; this replaces the old one:
     ```
     node -e "console.log(require('crypto').randomBytes(24).toString('hex'))" > ADMIN_KEY.txt
     npx wrangler@3 secret put ADMIN_KEY < ADMIN_KEY.txt
     ```
   - **No backup of a shop's key?** Run `node tools/shop.mjs new-key <id>` (ids are shown by `list`), and give the new key to that shop's phones.
   - The server code is deployed already. Run `npx wrangler@3 deploy` only after you change something in `server/src`.
9. **Pick up the work again.** The code on GitHub is only as new as your last push, so anything not pushed from the old laptop is gone. Commit and push often.

### Quick check that everything works

- `flutter doctor` shows no red crosses
- `flutter test` passes
- `dart run tool/build_apk.dart --no-bump` makes an APK in `build/app/outputs/flutter-apk/`
- `node tools/shop.mjs list` (in `server`) lists your shops
