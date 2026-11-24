import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/core/language.dart';
import 'package:hardware_shop/domain/settings.dart';
import 'package:hardware_shop/presentation/receipt/receipt_text.dart';
import 'package:hardware_shop/presentation/widgets/contact_actions.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  tearDown(() => Language.current = AppLanguage.bangla);

  Future<void> show(WidgetTester tester, FakeContactLauncher launcher, {String mobile = '', String whatsapp = '', String message = ''}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ContactActions(launcher: launcher, mobile: mobile, whatsapp: whatsapp, message: message)),
      ));

  testWidgets('nothing is shown when there is no valid number', (tester) async {
    for (final (mobile, whatsapp) in [('', ''), ('123', ''), ('', 'abc')]) {
      await show(tester, FakeContactLauncher(), mobile: mobile, whatsapp: whatsapp);
      expect(find.byType(IconButton), findsNothing, reason: '"$mobile" / "$whatsapp"');
    }
    expect(ContactActions.canReach('', '01712345678'), isTrue);
    expect(ContactActions.canReach('x', 'y'), isFalse);
  });

  testWidgets('there are two small buttons only: call and share (no separate SMS and WhatsApp)', (tester) async {
    await show(tester, FakeContactLauncher(), mobile: '01712345678', message: 'হ্যালো');
    expect(find.byType(IconButton), findsNWidgets(2));
    expect(find.byTooltip(Bn.contactCall), findsOneWidget);
    expect(find.byTooltip(Bn.contactShare), findsOneWidget);
    expect(find.byIcon(Icons.sms_outlined), findsNothing);
    expect(find.byIcon(Icons.chat_outlined), findsNothing);
    final size = tester.getSize(find.byType(IconButton).first);
    expect(size.width, lessThanOrEqualTo(36), reason: 'small');
  });

  testWidgets('call dials the number (the mobile first); share opens the share sheet with the message', (tester) async {
    final launcher = FakeContactLauncher();
    await show(tester, launcher, mobile: '01712345678', whatsapp: '01812345678', message: 'হ্যালো');
    await tester.tap(find.byTooltip(Bn.contactCall));
    await tester.tap(find.byTooltip(Bn.contactShare));
    await tester.pump();
    expect(launcher.calls, ['01712345678']);
    expect(launcher.shared, ['হ্যালো']);
  });

  testWidgets('with one number, call uses it whichever field it was in', (tester) async {
    for (final (mobile, whatsapp) in [('01712345678', ''), ('', '01712345678')]) {
      final launcher = FakeContactLauncher();
      await show(tester, launcher, mobile: mobile, whatsapp: whatsapp);
      await tester.tap(find.byTooltip(Bn.contactCall));
      await tester.pump();
      expect(launcher.calls, ['01712345678']);
    }
  });

  testWidgets('with nothing to share there is no share button', (tester) async {
    await show(tester, FakeContactLauncher(), mobile: '01712345678');
    expect(find.byTooltip(Bn.contactShare), findsNothing);
    expect(find.byTooltip(Bn.contactCall), findsOneWidget);
  });

  testWidgets('when it cannot be opened the person is told', (tester) async {
    final launcher = FakeContactLauncher()..result = false;
    await show(tester, launcher, mobile: '01712345678');
    await tester.tap(find.byTooltip(Bn.contactCall));
    await tester.pump();
    expect(find.text(Bn.contactFailed), findsOneWidget);
  });

  test('the reminder is always in Bangla, whatever the app language, and names the shop and amount', () {
    Language.current = AppLanguage.english;
    final text = buildDueReminderText(name: 'রহিম', due: 410, shopName: 'হাসান স্টোর');
    expect(text, 'রহিম, আসসালামু আলাইকুম। হাসান স্টোর-এ আপনার ৳৪১০ বাকি আছে। সুবিধামতো পরিশোধ করবেন। ধন্যবাদ।');
    expect(Language.current, AppLanguage.english, reason: 'the app language is left alone');
    expect(buildDueReminderText(name: '', due: 5, shopName: 'দোকান'), startsWith('আসসালামু আলাইকুম'));
  });
}
