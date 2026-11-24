import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/data/app_database.dart';
import 'package:hardware_shop/data/sqlite_activity_repository.dart';
import 'package:hardware_shop/data/sync/activity_recorder.dart';
import 'package:hardware_shop/domain/activity.dart';
import 'package:hardware_shop/domain/repositories.dart';
import 'package:hardware_shop/domain/sync.dart';
import 'package:hardware_shop/domain/users.dart';
import 'package:hardware_shop/presentation/activity/activity_page.dart';
import 'package:hardware_shop/presentation/activity/activity_viewmodel.dart';
import 'package:hardware_shop/presentation/auth/auth_viewmodel.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:hardware_shop/presentation/labels.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

const _rahim = AppUser(id: 1, name: 'রহিম', role: UserRole.staff);
const _karim = AppUser(id: 2, name: 'করিম', role: UserRole.staff);

DateTime _at(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

ActivityEntry _entry(int id, String kind, AppUser? who, DateTime at, [Map<String, dynamic> detail = const {}]) =>
    ActivityEntry(id: id, at: at, userId: who?.id, userName: who?.name ?? '', kind: kind, detail: detail);

/// An activity log that applies the same narrowing as the real one.
class _FakeActivity implements ActivityRepository {
  final List<ActivityEntry> entries;
  _FakeActivity(this.entries);

  final calls = <({int limit, int? userId, ActivityGroup group})>[];

  @override
  Future<List<ActivityEntry>> recent({int limit = 100, int? userId, ActivityGroup group = ActivityGroup.all}) async {
    calls.add((limit: limit, userId: userId, group: group));
    final kinds = group.kinds;
    return entries
        .where((e) => userId == null || e.userId == userId)
        .where((e) => kinds.isEmpty || kinds.contains(e.kind))
        .take(limit)
        .toList();
  }
}

class _Users implements UserRepository {
  final List<AppUser> people;
  _Users(this.people);

  @override
  Future<List<AppUser>> all() async => people;

  @override
  Future<AppUser> signIn(int userId, String pin) async {
    final user = people.firstWhere((u) => u.id == userId);
    if (pin != '1234') throw const AuthException(AuthProblem.wrongPin);
    return user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Sync implements SyncService {
  int syncs = 0;
  @override
  Future<void> syncNow() async => syncs++;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Notifier implements ActivityNotifier {
  final seen = <AppUser>[];
  AppUser? sessionWhenCalled;
  final Session session;
  _Notifier(this.session);

  @override
  void signedIn(AppUser user) {
    seen.add(user);
    sessionWhenCalled = session.user;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('reading the log (SQL)', () {
    const dbFile = 'activity_test.db';
    late AppDatabase db;
    late ActivityRecorder recorder;
    late SqliteActivityRepository repo;

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      db = AppDatabase(fileName: dbFile);
      recorder = ActivityRecorder(db);
      repo = SqliteActivityRepository(db);
    });

    tearDown(() async => (await db.db).close());

    Future<void> add(AppUser? who, String kind, DateTime at, [Map<String, Object?> detail = const {}]) =>
        recorder.add(at: at.millisecondsSinceEpoch, actor: who, kind: kind, detail: detail);

    test('an empty log is an empty list', () async {
      expect(await repo.recent(), isEmpty);
    });

    test('newest first, with who, when and the details', () async {
      await add(_rahim, ActivityKind.sale, _at(22, 9), {'total': 100});
      await add(_karim, ActivityKind.restocked, _at(22, 11), {'product': 'পেরেক', 'quantity': 4});
      await add(_rahim, ActivityKind.signIn, _at(21, 8));
      final entries = await repo.recent();
      expect(entries.map((e) => e.kind), [ActivityKind.restocked, ActivityKind.sale, ActivityKind.signIn]);
      expect((entries.first.userId, entries.first.userName, entries.first.at), (2, 'করিম', _at(22, 11)));
      expect(entries.first.detail, {'product': 'পেরেক', 'quantity': 4});
    });

    test('two things at the same moment keep the order they happened in', () async {
      await add(_rahim, ActivityKind.productAdded, _at(22, 9), {'product': 'ক'});
      await add(_rahim, ActivityKind.restocked, _at(22, 9), {'product': 'ক'});
      expect((await repo.recent()).map((e) => e.kind), [ActivityKind.restocked, ActivityKind.productAdded]);
    });

    test('one person only', () async {
      await add(_rahim, ActivityKind.sale, _at(22, 9));
      await add(_karim, ActivityKind.sale, _at(22, 10));
      await add(_rahim, ActivityKind.signIn, _at(22, 11));
      expect((await repo.recent(userId: 1)).map((e) => e.userName).toSet(), {'রহিম'});
      expect(await repo.recent(userId: 1), hasLength(2));
      expect(await repo.recent(userId: 99), isEmpty);
    });

    test('one kind of work: sales and money, stock and products, people and sign-ins', () async {
      await add(_rahim, ActivityKind.sale, _at(22, 9));
      await add(_rahim, ActivityKind.paymentCollected, _at(22, 10));
      await add(_rahim, ActivityKind.restocked, _at(22, 11));
      await add(_rahim, ActivityKind.categoryAdded, _at(22, 12));
      await add(_rahim, ActivityKind.signIn, _at(22, 13));
      await add(_rahim, ActivityKind.pinChanged, _at(22, 14));
      Future<List<String>> kinds(ActivityGroup g) async => (await repo.recent(group: g)).map((e) => e.kind).toList();
      expect(await kinds(ActivityGroup.sales), [ActivityKind.paymentCollected, ActivityKind.sale]);
      expect(await kinds(ActivityGroup.stock), [ActivityKind.categoryAdded, ActivityKind.restocked]);
      expect(await kinds(ActivityGroup.people), [ActivityKind.pinChanged, ActivityKind.signIn]);
      expect(await kinds(ActivityGroup.all), hasLength(6));
    });

    test('a person and a kind of work together', () async {
      await add(_rahim, ActivityKind.sale, _at(22, 9));
      await add(_karim, ActivityKind.sale, _at(22, 10));
      await add(_rahim, ActivityKind.signIn, _at(22, 11));
      final entries = await repo.recent(userId: 1, group: ActivityGroup.sales);
      expect(entries.map((e) => (e.userName, e.kind)), [('রহিম', ActivityKind.sale)]);
    });

    test('only as many as asked for', () async {
      for (var i = 0; i < 12; i++) {
        await add(_rahim, ActivityKind.sale, _at(22, 8, i));
      }
      expect(await repo.recent(limit: 5), hasLength(5));
      expect((await repo.recent(limit: 5)).first.at, _at(22, 8, 11));
      expect(await repo.recent(limit: 50), hasLength(12));
    });

    test('an entry whose details cannot be read still shows, without them', () async {
      final raw = await db.db;
      await raw.insert('activity_log', {'at': 1, 'user_name': 'ক', 'kind': 'sale', 'detail': 'not json at all'});
      await raw.insert('activity_log', {'at': 2, 'user_name': 'খ', 'kind': 'sale', 'detail': '[1,2]'});
      final entries = await repo.recent();
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.detail.isEmpty), isTrue);
    });
  });

  group('upgrading', () {
    const dbFile = 'activity_upgrade_test.db';

    test('a database from before the activity log gets one, and everything else is untouched', () async {
      await deleteDatabase(p.join(await getDatabasesPath(), dbFile));
      var db = AppDatabase(fileName: dbFile);
      var raw = await db.db;
      await raw.insert('categories', {'name': 'আগের ক্যাটাগরি'});
      await raw.execute('DROP TABLE activity_log');
      await raw.execute('PRAGMA user_version = 11');
      await raw.close();

      db = AppDatabase(fileName: dbFile);
      raw = await db.db;
      addTearDown(raw.close);
      expect((await raw.query('categories', where: 'name = ?', whereArgs: ['আগের ক্যাটাগরি'])), hasLength(1));
      await ActivityRecorder(db).add(at: 5, actor: _rahim, kind: ActivityKind.signIn);
      expect(await SqliteActivityRepository(db).recent(), hasLength(1));
    });
  });

  group('how each kind reads', () {
    String say(String kind, [Map<String, dynamic> detail = const {}]) =>
        activitySentence(_entry(1, kind, _rahim, _at(22, 10), detail));

    test('selling and money', () {
      expect(say(ActivityKind.sale, {'total': 370.0, 'items': 2, 'customer': 'রহিম', 'due': 150.0}),
          'বিক্রি করেছেন: ৳৩৭০ • ২টি পণ্য • রহিম • বাকি ৳১৫০');
      expect(say(ActivityKind.sale, {'total': 100.0, 'items': 1, 'customer': '', 'due': 0.0}), 'বিক্রি করেছেন: ৳১০০ • ১টি পণ্য');
      expect(say(ActivityKind.saleVoided, {'billId': 7, 'total': 300.0}), 'বিক্রি বাতিল করেছেন: রসিদ নং ৭ • ৳৩০০');
      expect(say(ActivityKind.paymentCollected, {'amount': 50.0, 'customer': 'রহিম'}), 'বাকির টাকা নিয়েছেন: ৳৫০ • রহিম');
      expect(say(ActivityKind.customerAdded, {'billId': 7, 'customer': 'রহিম'}), 'বিক্রিতে গ্রাহক যোগ করেছেন: রসিদ নং ৭ • রহিম');
    });

    test('stock', () {
      expect(say(ActivityKind.restocked, {'product': 'পেরেক', 'quantity': 5.0}), 'মজুদ যোগ করেছেন: পেরেক • +৫');
      expect(say(ActivityKind.stockAdjusted, {'product': 'তার', 'total': 8.0}), 'মজুদ ঠিক করেছেন: তার • মোট ৮');
      expect(say(ActivityKind.stockPlaced, {'product': 'পেরেক', 'location': 'তাক ক', 'quantity': 4.0}), 'পেরেক সাজিয়েছেন: তাক ক • ৪');
      expect(say(ActivityKind.stockCounted, {'product': 'পেরেক', 'location': 'তাক ক', 'quantity': 6.0}), 'পেরেক গণনা করেছেন: তাক ক • ৬');
      expect(say(ActivityKind.stockMoved, {'product': 'পেরেক', 'from': 'তাক ক', 'to': 'তাক খ', 'quantity': 2.0}),
          'পেরেক সরিয়েছেন: তাক ক → তাক খ • ২');
    });

    test('products, categories and places', () {
      expect(say(ActivityKind.productAdded, {'product': 'হাতুড়ি'}), 'নতুন পণ্য যোগ করেছেন: হাতুড়ি');
      expect(say(ActivityKind.productEdited, {'product': 'হাতুড়ি'}), 'পণ্য বদলেছেন: হাতুড়ি');
      expect(say(ActivityKind.productDeleted, {'product': 'হাতুড়ি'}), 'পণ্য মুছেছেন: হাতুড়ি');
      expect(say(ActivityKind.categoryAdded, {'name': 'রং'}), 'ক্যাটাগরি যোগ করেছেন: রং');
      expect(say(ActivityKind.categoryDeleted, {'name': 'রং'}), 'ক্যাটাগরি মুছেছেন: রং');
      expect(say(ActivityKind.locationTypeRenamed, {'previous': 'আলমারি', 'name': 'র‍্যাক'}), 'স্থানের ধরন বদলেছেন: আলমারি → র‍্যাক');
      expect(say(ActivityKind.locationTypeDeleted, {'name': 'আলমারি'}), 'স্থানের ধরন মুছেছেন: আলমারি');
      expect(say(ActivityKind.categoryEdited, {'previous': 'রং', 'name': 'রঙ'}), 'ক্যাটাগরি বদলেছেন: রং → রঙ');
      expect(say(ActivityKind.categoryEdited, {'previous': '', 'name': 'রঙ'}), 'ক্যাটাগরি বদলেছেন: রঙ');
      expect(say(ActivityKind.locationAdded, {'name': 'তাক ক'}), 'স্থান যোগ করেছেন: তাক ক');
      expect(say(ActivityKind.locationDeleted, {'name': 'তাক ক'}), 'স্থান মুছেছেন: তাক ক');
      expect(say(ActivityKind.locationEdited, {'previous': 'তাক ক', 'name': 'তাক খ'}), 'স্থান বদলেছেন: তাক ক → তাক খ');
      expect(say(ActivityKind.locationEdited, {'previous': 'তাক ক', 'name': 'তাক ক'}), 'স্থান বদলেছেন: তাক ক');
    });

    test('people', () {
      expect(say(ActivityKind.userAdded, {'name': 'রহিম', 'role': 'staff'}), 'নতুন কর্মী যোগ করেছেন: রহিম (কর্মী)');
      expect(say(ActivityKind.userAdded, {'name': 'ভাই', 'role': 'owner'}), 'নতুন কর্মী যোগ করেছেন: ভাই (মালিক)');
      expect(say(ActivityKind.pinChanged, {'name': 'রহিম'}), 'PIN বদলেছেন: রহিম');
      expect(say(ActivityKind.profileUpdated, {'name': 'রহিম'}), 'প্রোফাইল বদলেছেন: রহিম');
      expect(say(ActivityKind.userSwitched, {'name': 'রহিম', 'active': true}), 'রহিম-কে চালু করেছেন');
      expect(say(ActivityKind.userSwitched, {'name': 'রহিম', 'active': false}), 'রহিম-কে বন্ধ করেছেন');
      expect(say(ActivityKind.signIn), 'অ্যাপে ঢুকেছেন');
      expect(say(ActivityKind.shopRenamed, {'name': 'হাসান হার্ডওয়্যার'}), 'দোকানের নাম বদলেছেন: হাসান হার্ডওয়্যার');
    });

    test('a kind from a newer version, or missing details, never crashes', () {
      expect(say('somethingNew'), 'somethingNew');
      for (final kind in ActivityGroup.values.expand((g) => g.kinds)) {
        expect(() => say(kind), returnsNormally, reason: kind);
      }
    });

    test('every kind has its own icon; an unknown one still gets one', () {
      for (final kind in ActivityGroup.values.expand((g) => g.kinds)) {
        expect(activityIcon(kind), isNot(Icons.history), reason: kind);
      }
      expect(activityIcon('somethingNew'), Icons.history);
    });

    test('every kind belongs to exactly one group', () {
      final seen = <String>[];
      for (final g in [ActivityGroup.sales, ActivityGroup.stock, ActivityGroup.people]) {
        seen.addAll(g.kinds);
      }
      expect(seen.toSet(), hasLength(seen.length), reason: 'no kind in two groups');
      expect(seen, hasLength(26), reason: 'all twenty-six kinds are covered');
    });
  });

  group('view model', () {
    late _FakeActivity activity;
    late _Sync sync;
    late ActivityViewModel vm;

    ActivityViewModel make(List<ActivityEntry> entries) {
      activity = _FakeActivity(entries);
      sync = _Sync();
      return ActivityViewModel(activity, _Users([_rahim, _karim]), FakeClock(_at(22, 15)), sync);
    }

    test('loads the newest entries and the people to pick from', () async {
      vm = make([_entry(2, ActivityKind.sale, _rahim, _at(22, 10)), _entry(1, ActivityKind.signIn, _karim, _at(22, 9))]);
      await vm.load();
      expect(vm.loading, isFalse);
      expect(vm.entries, hasLength(2));
      expect(vm.people.map((u) => u.name), ['রহিম', 'করিম']);
      expect(vm.hasMore, isFalse);
    });

    test('picking a person or a kind narrows the list and starts again from the newest', () async {
      vm = make([
        _entry(3, ActivityKind.sale, _rahim, _at(22, 11)),
        _entry(2, ActivityKind.sale, _karim, _at(22, 10)),
        _entry(1, ActivityKind.signIn, _rahim, _at(22, 9)),
      ]);
      await vm.load();
      await vm.showMore(); // limit now 200
      await vm.setPerson(1);
      expect(vm.entries.map((e) => e.id), [3, 1]);
      expect(activity.calls.last.limit, ActivityViewModel.pageSize, reason: 'back to the first page');
      await vm.setGroup(ActivityGroup.sales);
      expect(vm.entries.map((e) => e.id), [3]);
      await vm.setPerson(null);
      expect(vm.entries.map((e) => e.id), [3, 2], reason: 'sales by everyone');
    });

    test('"show more" asks for another page; it is offered only when there may be more', () async {
      vm = make([for (var i = 0; i < 250; i++) _entry(i, ActivityKind.sale, _rahim, _at(22, 8).add(Duration(minutes: i)))]);
      await vm.load();
      expect(vm.entries, hasLength(100));
      expect(vm.hasMore, isTrue);
      await vm.showMore();
      expect(vm.entries, hasLength(200));
      await vm.showMore();
      expect(vm.entries, hasLength(250));
      expect(vm.hasMore, isFalse);
    });

    test('pull to refresh first fetches what other phones did, then shows it', () async {
      vm = make([_entry(1, ActivityKind.sale, _rahim, _at(22, 10))]);
      await vm.refresh();
      expect(sync.syncs, 1);
      expect(vm.entries, hasLength(1));
    });

    test('day headings: today, yesterday, then the date', () {
      vm = make(const []);
      expect(vm.dayHeading(_at(22, 1)), 'আজ');
      expect(vm.dayHeading(_at(21, 23)), 'গতকাল');
      expect(vm.dayHeading(_at(10, 9)), '১০/১১/২০২৬');
      expect(vm.sameDay(_at(22, 1), _at(22, 23)), isTrue);
      expect(vm.sameDay(_at(22, 1), _at(21, 23)), isFalse);
    });
  });

  group('screen', () {
    late _FakeActivity activity;

    Future<ActivityViewModel> open(WidgetTester tester, List<ActivityEntry> entries) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      activity = _FakeActivity(entries);
      final vm = ActivityViewModel(activity, _Users([_rahim, _karim]), FakeClock(_at(22, 15)));
      await tester.pumpWidget(MaterialApp(home: ActivityPage(viewModel: vm)));
      await tester.pumpAndSettle();
      return vm;
    }

    testWidgets('a quiet shop explains itself', (tester) async {
      await open(tester, const []);
      expect(find.text(Bn.activityEmpty), findsOneWidget);
    });

    testWidgets('shows what each person did, who did it and when, under the day', (tester) async {
      await open(tester, [
        _entry(3, ActivityKind.sale, _rahim, _at(22, 14, 5), {'total': 370.0, 'items': 2, 'customer': '', 'due': 0.0}),
        _entry(2, ActivityKind.restocked, _karim, _at(22, 9, 30), {'product': 'পেরেক', 'quantity': 5.0}),
        _entry(1, ActivityKind.signIn, _rahim, _at(21, 18, 45)),
      ]);
      expect(find.text('আজ'), findsOneWidget);
      expect(find.text('গতকাল'), findsOneWidget);
      expect(find.text('বিক্রি করেছেন: ৳৩৭০ • ২টি পণ্য'), findsOneWidget);
      expect(find.text('রহিম • ১৪:০৫'), findsOneWidget);
      expect(find.text('মজুদ যোগ করেছেন: পেরেক • +৫'), findsOneWidget);
      expect(find.text('করিম • ০৯:৩০'), findsOneWidget);
      expect(find.text('অ্যাপে ঢুকেছেন'), findsOneWidget);
      expect(find.text('রহিম • ১৮:৪৫'), findsOneWidget);
    });

    testWidgets('an entry from nobody (before anyone was signed in) is shown as unknown', (tester) async {
      await open(tester, [_entry(1, ActivityKind.userAdded, null, _at(22, 8), {'name': 'মালিক', 'role': 'owner'})]);
      expect(find.text('${Bn.activityUnknownPerson} • ০৮:০০'), findsOneWidget);
    });

    testWidgets('anyone can be picked, and everyone can be shown again', (tester) async {
      await open(tester, [
        _entry(3, ActivityKind.sale, _rahim, _at(22, 11), {'total': 100.0, 'items': 1}),
        _entry(2, ActivityKind.restocked, _karim, _at(22, 10), {'product': 'তার', 'quantity': 2.0}),
      ]);
      expect(find.text(Bn.activityEveryone), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'করিম'));
      await tester.pumpAndSettle();
      expect(activity.calls.last.userId, 2);
      expect(find.text('মজুদ যোগ করেছেন: তার • +২'), findsOneWidget);
      expect(find.textContaining('বিক্রি করেছেন'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, Bn.activityEveryone));
      await tester.pumpAndSettle();
      expect(activity.calls.last.userId, isNull);
      expect(find.textContaining('বিক্রি করেছেন'), findsOneWidget);
    });

    testWidgets('a kind of work can be picked', (tester) async {
      await open(tester, [
        _entry(3, ActivityKind.sale, _rahim, _at(22, 11), {'total': 100.0, 'items': 1}),
        _entry(2, ActivityKind.restocked, _karim, _at(22, 10), {'product': 'তার', 'quantity': 2.0}),
      ]);
      for (final label in [Bn.activityGroupAll, Bn.activityGroupSales, Bn.activityGroupStock, Bn.activityGroupPeople]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget, reason: label);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, Bn.activityGroupStock));
      await tester.pumpAndSettle();
      expect(activity.calls.last.group, ActivityGroup.stock);
      expect(find.textContaining('মজুদ যোগ করেছেন'), findsOneWidget);
      expect(find.textContaining('বিক্রি করেছেন'), findsNothing);
    });

    testWidgets('when a choice leaves nothing, it says so (not "nothing has happened yet")', (tester) async {
      await open(tester, [_entry(3, ActivityKind.sale, _rahim, _at(22, 11), {'total': 100.0, 'items': 1})]);
      await tester.tap(find.widgetWithText(ChoiceChip, Bn.activityGroupPeople));
      await tester.pumpAndSettle();
      expect(find.text(Bn.activityEmptyFiltered), findsOneWidget);
      expect(find.text(Bn.activityEmpty), findsNothing);
    });

    testWidgets('a long history is shown a page at a time', (tester) async {
      await open(tester, [
        for (var i = 0; i < 150; i++) _entry(i, ActivityKind.signIn, _rahim, _at(22, 8).add(Duration(minutes: i))),
      ]);
      expect(find.text(Bn.activityMore), findsNothing, reason: 'the button is below the first hundred (scroll to it)');
      await tester.scrollUntilVisible(find.text(Bn.activityMore), 500, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text(Bn.activityMore));
      await tester.pumpAndSettle();
      expect(activity.calls.last.limit, 200);
      await tester.scrollUntilVisible(find.byType(ItemCard).last, 500, scrollable: find.byType(Scrollable).last);
      expect(find.text(Bn.activityMore), findsNothing, reason: 'that was everything');
    });
  });

  group('noting sign-ins', () {
    late Session session;
    late _Notifier notifier;
    late AuthViewModel vm;

    setUp(() {
      session = Session();
      notifier = _Notifier(session);
      vm = AuthViewModel(_Users([_rahim]), session, notifier);
    });

    test('a successful sign-in is noted, after the person is signed in', () async {
      await vm.signIn(_rahim, '1234');
      expect(notifier.seen.map((u) => u.name), ['রহিম']);
      expect(notifier.sessionWhenCalled?.id, 1, reason: 'so the note is made under their own name');
    });

    test('a wrong PIN is not a sign-in and is not noted', () async {
      await expectLater(vm.signIn(_rahim, '0000'), throwsA(isA<AuthException>()));
      expect(notifier.seen, isEmpty);
      expect(session.user, isNull);
    });

    test('signing in works the same with no way of noting it', () async {
      final plain = AuthViewModel(_Users([_rahim]), session);
      await plain.signIn(_rahim, '1234');
      expect(session.user?.name, 'রহিম');
    });
  });
}
