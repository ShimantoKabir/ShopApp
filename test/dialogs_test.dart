import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/presentation/components/components.dart';
import 'package:material_ui/material_ui.dart';

/// Confirms each dialog the way a user does: open, type, confirm. These catch
/// crashes that only happen while the dialog animates closed (for example a
/// text controller disposed while its field is still on screen).

Future<void> open(WidgetTester tester, Future<void> Function(BuildContext) show) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(body: Center(child: ElevatedButton(onPressed: () => show(context), child: const Text('open')))),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('showNumberDialog: confirming returns the number and closes cleanly', (tester) async {
    double? result = -1;
    await open(tester, (c) async => result = await showNumberDialog(c, title: 'শিরোনাম', label: 'পরিমাণ', initial: 3));
    await tester.enterText(find.byType(TextField), '১২');
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(result, 12);
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('showNumberDialog: submitting from the keyboard works too', (tester) async {
    double? result = -1;
    await open(tester, (c) async => result = await showNumberDialog(c, title: 'শিরোনাম', label: 'পরিমাণ'));
    await tester.enterText(find.byType(TextField), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showNumberDialog: cancelling returns null and closes cleanly', (tester) async {
    double? result = -1;
    await open(tester, (c) async => result = await showNumberDialog(c, title: 'শিরোনাম', label: 'পরিমাণ', initial: 3));
    await tester.tap(find.text('বাতিল'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showTextPromptDialog: confirming returns trimmed text and closes cleanly', (tester) async {
    String? result = 'unset';
    await open(tester, (c) async => result = await showTextPromptDialog(c, title: 'নতুন', hint: 'নাম'));
    await tester.enterText(find.byType(TextField), '  পাইপ ');
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(result, 'পাইপ');
    expect(tester.takeException(), isNull);
  });

  testWidgets('showTextWithChoiceDialog: returns text and the chosen option, closes cleanly', (tester) async {
    ({String text, int choice})? result;
    await open(
      tester,
      (c) async => result = await showTextWithChoiceDialog<int>(
        c,
        title: 'নতুন স্থান',
        choiceLabel: 'ধরন',
        options: const [(value: 1, label: 'তাক'), (value: 2, label: 'গুদাম')],
        initialChoice: 1,
      ),
    );
    await tester.enterText(find.byType(TextField), 'তাক ৫');
    await tester.tap(find.text('গুদাম'));
    await tester.pump();
    await tester.tap(find.text('যোগ করুন'));
    await tester.pumpAndSettle();
    expect(result?.text, 'তাক ৫');
    expect(result?.choice, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showChoiceNumberDialog: returns the choice and number, closes cleanly', (tester) async {
    ({int choice, double number})? result;
    await open(
      tester,
      (c) async => result = await showChoiceNumberDialog<int>(
        c,
        title: 'সরান',
        choiceLabel: 'যে স্থানে',
        options: const [(value: 1, label: 'তাক ১'), (value: 2, label: 'গুদাম')],
        initialChoice: 1,
        numberLabel: 'পরিমাণ',
        initialNumber: 3,
      ),
    );
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('গুদাম').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(result?.choice, 2);
    expect(result?.number, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showChoiceNumberDialog: an invalid number does not close the dialog', (tester) async {
    await open(
      tester,
      (c) => showChoiceNumberDialog<int>(
        c,
        title: 'সরান',
        choiceLabel: 'যে স্থানে',
        options: const [(value: 1, label: 'তাক ১')],
        initialChoice: 1,
        numberLabel: 'পরিমাণ',
      ),
    );
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('সংরক্ষণ'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('showConfirmDialog and showInfoDialog close cleanly', (tester) async {
    bool? confirmed;
    await open(tester, (c) async => confirmed = await showConfirmDialog(c, message: 'নিশ্চিত?', confirmLabel: 'হ্যাঁ'));
    await tester.tap(find.text('হ্যাঁ'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);

    await open(tester, (c) => showInfoDialog(c, message: 'তথ্য'));
    await tester.tap(find.text('ঠিক আছে'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
