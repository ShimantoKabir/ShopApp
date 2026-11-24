import 'package:flutter_test/flutter_test.dart';
import 'package:hardware_shop/core/bangla.dart';
import 'package:hardware_shop/domain/entities.dart';

void main() {
  group('parseNumber', () {
    test('accepts English and Bangla digits', () {
      expect(parseNumber('120'), 120);
      expect(parseNumber('১২০'), 120);
      expect(parseNumber('১২.৫'), 12.5);
      expect(parseNumber('১,২০০'), 1200);
    });

    test('rejects empty, negative and garbage', () {
      expect(parseNumber(''), isNull);
      expect(parseNumber(null), isNull);
      expect(parseNumber('abc'), isNull);
      expect(parseNumber('-5'), isNull);
    });
  });

  test('formatNumber uses Bangla digits and drops .0', () {
    expect(formatNumber(120), '১২০');
    expect(formatNumber(12.5), '১২.৫০');
  });

  test('Product profit and stock value', () {
    const p = Product(
      name: 'পেরেক',
      purchasePrice: 80,
      sellingPrice: 100,
      stock: 10,
      unit: 'কেজি',
    );
    expect(p.profitPerUnit, 20);
    expect(p.stockValueAtCost, 800);
  });

  test('Product variantParts lists only filled details in order', () {
    const paint = Product(
      name: 'ওয়েদারকোট',
      kind: ProductKind.standard,
      brand: 'বার্জার',
      size: '৪ লিটার',
      finish: '',
      purchasePrice: 3000,
      sellingPrice: 3400,
      stock: 6,
      unit: 'ক্যান',
    );
    expect(paint.variantParts, ['বার্জার', '৪ লিটার']);
  });
}
