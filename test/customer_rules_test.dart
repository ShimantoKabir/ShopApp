import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/domain/customer_rules.dart';
import 'package:hardware_shop/domain/sales.dart';
import 'package:hardware_shop/presentation/receipt_text.dart';

void main() {
  group('mobile numbers', () {
    test('every usual way of writing a valid number is accepted and normalised to 11 digits', () {
      for (final input in [
        '01712345678',
        '০১৭১২৩৪৫৬৭৮', // Bangla digits
        '+8801712345678',
        '8801712345678',
        '017-1234-5678',
        ' 01712 345678 ',
        '+৮৮০ ১৭১২ ৩৪৫৬৭৮',
      ]) {
        expect(isValidMobile(input), isTrue, reason: input);
        expect(normalizeMobile(input), '01712345678', reason: input);
      }
    });

    test('every operator prefix 013-019 is valid', () {
      for (final op in ['013', '014', '015', '016', '017', '018', '019']) {
        expect(isValidMobile('${op}12345678'), isTrue, reason: op);
      }
    });

    test('wrong numbers are rejected', () {
      for (final input in [
        '',
        '1234',
        '0171234567', // 10 digits
        '017123456789', // 12 digits
        '01212345678', // 012 is not a mobile operator
        '01012345678', // 010 is not either
        '11712345678', // does not start with 01
        'abcdefghijk',
        '+8801712345', // too short
        '88017123456789', // too long
      ]) {
        expect(isValidMobile(input), isFalse, reason: input);
      }
    });

    test('WhatsApp number is the international form, or null when invalid', () {
      expect(whatsAppNumber('01712345678'), '8801712345678');
      expect(whatsAppNumber('০১৭১২৩৪৫৬৭৮'), '8801712345678');
      expect(whatsAppNumber('+8801712345678'), '8801712345678');
      expect(whatsAppNumber('12345'), isNull);
      expect(whatsAppNumber(''), isNull);
    });
  });

  group('NID numbers', () {
    test('10, 13 and 17 digits are valid, in any digits and with spaces or dashes', () {
      for (final input in ['1234567890', '1234567890123', '12345678901234567', '১২৩৪৫৬৭৮৯০', '1234 567 890', '123-456-7890']) {
        expect(isValidNid(input), isTrue, reason: input);
      }
    });

    test('other lengths and non-numbers are rejected', () {
      for (final input in ['', '123', '123456789', '12345678901', '12345678901234', '123456789012345678', 'abcdefghij']) {
        expect(isValidNid(input), isFalse, reason: input);
      }
    });

    test('normalising keeps digits only (Bangla turned into English)', () {
      expect(normalizeNid('১২৩ ৪৫৬-৭৮৯০'), '1234567890');
    });
  });

  test('digitsOnly drops everything that is not a digit', () {
    expect(digitsOnly('+৮৮ (০১৭) 12-34'), '8801712' '34');
  });

  group('receipt text', () {
    final at = DateTime(2026, 11, 22, 15, 35);
    Sale line(String name, double qty, double price, {String unit = 'কেজি'}) =>
        Sale(productName: name, unit: unit, quantity: qty, unitPrice: price, unitCost: 0, at: at);

    Bill bill({
      double paid = 330,
      String name = 'রহিম',
      String mobile = '01712345678',
      String address = 'কাজিপুর, সিরাজগঞ্জ',
      String whatsapp = '01812345678',
      List<Sale>? lines,
    }) =>
        Bill(
          id: 12,
          customerName: name,
          customerMobile: mobile,
          customerAddress: address,
          customerWhatsApp: whatsapp,
          paid: paid,
          at: at,
          lines: lines ?? [line('পেরেক', 2, 110), line('তার', 1, 110)],
        );

    test('has the shop, number, date, customer, every line and the totals in Bangla', () {
      final text = buildReceiptText(bill(), shopName: 'আমার দোকান');
      expect(text, contains('আমার দোকান'));
      expect(text, contains('রসিদ নং: ১২'));
      expect(text, contains('২২/১১/২০২৬ ১৫:৩৫'));
      expect(text, contains('গ্রাহক: রহিম'));
      expect(text, contains('পেরেক'));
      expect(text, contains('২ কেজি × ৳১১০ = ৳২২০'));
      expect(text, contains('তার'));
      expect(text, contains('মোট: ৳৩৩০'));
      expect(text, contains('পরিশোধ: ৳৩৩০'));
      expect(text, contains('ধন্যবাদ'));
    });

    test('shows the due only when something is unpaid', () {
      expect(buildReceiptText(bill(paid: 330), shopName: 'দোকান'), isNot(contains('বাকি')));
      final due = buildReceiptText(bill(paid: 100), shopName: 'দোকান');
      expect(due, contains('পরিশোধ: ৳১০০'));
      expect(due, contains('বাকি: ৳২৩০'));
    });

    test('includes the customer address', () {
      final text = buildReceiptText(bill(), shopName: 'দোকান');
      expect(text, contains('ঠিকানা: কাজিপুর, সিরাজগঞ্জ'));
    });

    test('a bill with no name still shows the address; no address means no address line', () {
      final noName = buildReceiptText(bill(name: ''), shopName: 'দোকান');
      expect(noName, isNot(contains('গ্রাহক:')));
      expect(noName, contains('ঠিকানা:'));
      expect(buildReceiptText(bill(address: ''), shopName: 'দোকান'), isNot(contains('ঠিকানা')));
    });

    test('an old bill with no customer details has neither line', () {
      final text = buildReceiptText(bill(name: '', mobile: '', address: '', whatsapp: ''), shopName: 'দোকান');
      expect(text, isNot(contains('গ্রাহক')));
      expect(text, isNot(contains('ঠিকানা')));
    });

    test('phone numbers (mobile or WhatsApp) and the NID are never put on the receipt', () {
      final text = buildReceiptText(bill(), shopName: 'দোকান');
      expect(text, isNot(contains('01712345678')));
      expect(text, isNot(contains('01812345678')));
      expect(text, isNot(contains('০১৭১২৩৪৫৬৭৮')));
      expect(text, isNot(contains('NID')));
    });
  });

  group('Bill totals', () {
    final at = DateTime(2026, 11, 22);
    Sale line(double qty, double price, double cost) =>
        Sale(productName: 'x', unit: 'পিস', quantity: qty, unitPrice: price, unitCost: cost, at: at);

    test('total, cost, profit and due', () {
      final bill = Bill(paid: 100, at: at, lines: [line(2, 100, 80), line(1, 50, 60)]);
      expect(bill.total, 250);
      expect(bill.cost, 220);
      expect(bill.profit, 30);
      expect(bill.due, 150);
    });

    test('due is never negative or a rounding crumb', () {
      expect(Bill(paid: 300, at: at, lines: [line(1, 250, 0)]).due, 0);
      expect(Bill(paid: 0.1 + 0.2, at: at, lines: [line(1, 0.3, 0)]).due, 0);
    });

    test('hasCustomer reflects a name, a mobile or a WhatsApp number', () {
      expect(Bill(paid: 0, at: at, lines: const []).hasCustomer, isFalse);
      expect(Bill(paid: 0, at: at, lines: const [], customerName: 'রহিম').hasCustomer, isTrue);
      expect(Bill(paid: 0, at: at, lines: const [], customerMobile: '01712345678').hasCustomer, isTrue);
      expect(Bill(paid: 0, at: at, lines: const [], customerWhatsApp: '01712345678').hasCustomer, isTrue);
    });
  });
}
