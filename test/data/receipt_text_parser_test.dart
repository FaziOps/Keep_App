import 'package:flutter_test/flutter_test.dart';
import 'package:keepr/features/receipts/data/parsing/receipt_text_parser.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/domain/entities/receipt_draft.dart';
import 'package:keepr/features/receipts/domain/services/receipt_factory.dart';

final now = DateTime(2026, 10, 7, 11);

/// The Techzone Electronics demo receipt, as rows.
const techzone = [
  'TECHZONE',
  'ELECTRONICS',
  '1042 Market St, San Francisco, CA 94103',
  'www.techzone.com',
  'OCTOBER 04, 2026 14:32',
  'INVOICE: #884920',
  '(REG: 3 / TRAN: 104 / EMP: Sarah J.)',
  r'1x Sony WH-1000XM5 Black  $399.99',
  r'1x Anker 65W GaN Fast Charger  $39.99',
  r'1x 2-Yr Hardware Protection Plan  $49.99',
  '-----------------',
  r'SUBTOTAL:  $489.97',
  r'Sales Tax (8.5%):  $41.65',
  r'TOTAL:  $531.62',
  'PAYMENT METHOD: VISA **** 4821',
  'Auth: 09182C / Seq: 0045 / Card: CHIP',
  r'TOTAL PAID:  $531.62',
  '--- RETURNS & WARRANTY ---',
  'RETURNS: 14 DAYS FOR FULL REFUND WITH RECEIPT',
  'AND ORIGINAL PACKAGING FOR ALL ITEMS.',
  'WARRANTY: 1-YEAR MANUFACTURER WARRANTY INCLUDED',
  'PROTECTION PLAN ACTIVE FOR 2 YEARS.',
  'THANK YOU FOR SHOPPING AT TECHZONE!',
  '#88492000104',
];

void main() {
  group('Techzone demo receipt', () {
    final draft = ReceiptTextParser.parseRows(techzone, currencyHint: 'PKR', now: now);

    test('reads store, date, total, currency and payment', () {
      expect(draft.merchant, 'Techzone Electronics');
      expect(draft.purchaseDate, DateTime(2026, 10, 4));
      expect(draft.totalMinor, 53162);
      expect(draft.currency, 'USD');
      expect(draft.paymentMethod, 'Visa •••• 4821');
      expect(draft.category, Category.electronics);
      expect(draft.engine, ExtractionEngine.onDevice);
    });

    test('reads every item with its price', () {
      expect(draft.items.map((i) => i.name), [
        'Sony WH-1000XM5 Black',
        'Anker 65W GaN Fast Charger',
        '2-Yr Hardware Protection Plan',
      ]);
      expect(draft.items.map((i) => i.unitPriceMinor), [39999, 3999, 4999]);
      expect(draft.items.every((i) => i.quantity == 1), isTrue);
    });

    test('reads return window and warranties', () {
      expect(draft.suggestedReturnDays, 14);
      expect(draft.suggestedWarrantyMonths, 12);
      expect(draft.items.last.warrantyMonths, 24);
      expect(draft.items.last.isExtendedWarranty, isTrue);
    });

    test('totals that add up are trusted, so nothing needs checking', () {
      expect(draft.confidence['total'], greaterThan(0.9));
      expect(draft.lowConfidenceFields, isEmpty);
    });

    test('becomes a complete receipt with warranties per item', () {
      var n = 0;
      final r = ReceiptFactory.fromDraft(
        draft,
        id: 'r',
        householdId: 'h',
        userId: 'u',
        now: now,
        newId: () => 'id${n++}',
      );
      expect(r.items.map((i) => i.warranty?.months), [12, 12, 24]);
      expect(r.returnDays, 14);
      expect(r.total.currency, 'USD');
      expect(r.ocrText, contains('TECHZONE'));
    });
  });

  test('assembles names and prices recognised as separate boxes into rows', () {
    OcrLine box(String text, double left, double top) =>
        OcrLine(text: text, left: left, top: top, width: 0.3, height: 0.02);
    final rows = ReceiptTextParser.assembleRows([
      box(r'$399.99', 0.70, 0.401),
      box('1x Sony WH-1000XM5 Black', 0.10, 0.400),
      box(r'$39.99', 0.72, 0.432),
      box('1x Anker 65W GaN Fast Charger', 0.10, 0.430),
      box('TOTAL:', 0.10, 0.50),
      box(r'$439.98', 0.70, 0.503),
    ]);
    expect(rows, [r'1x Sony WH-1000XM5 Black  $399.99', r'1x Anker 65W GaN Fast Charger  $39.99', r'TOTAL:  $439.98']);
  });

  test('Pakistani receipt in rupees with day-first dates and quantities', () {
    final d = ReceiptTextParser.parseRows(
      [
        'CITY MOBILES',
        'Hall Road, Lahore',
        'Date: 28/09/2026',
        'Samsung Galaxy A55 128GB  Rs 89,999',
        'IMEI: 356789104455120',
        '2 x Screen Protector  1,000',
        'Grand Total  Rs 90,999',
        'Cash',
        'Warranty: 12 months official',
        'No return after 7 days',
      ],
      currencyHint: 'USD',
      now: now,
    );

    expect(d.currency, 'PKR');
    expect(d.merchant, 'City Mobiles');
    expect(d.purchaseDate, DateTime(2026, 9, 28));
    expect(d.totalMinor, 9099900);
    expect(d.items.first.serialNumber, '356789104455120');
    expect(d.items.last.quantity, 2);
    expect(d.items.last.unitPriceMinor, 50000);
    expect(d.paymentMethod, 'Cash');
    expect(d.suggestedWarrantyMonths, 12);
    expect(d.suggestedReturnDays, 7);
  });

  test('a photo without receipt text is rejected', () {
    final d = ReceiptTextParser.parseRows(['Hello world', 'Nice view'], currencyHint: 'USD', now: now);
    expect(ReceiptTextParser.looksLikeReceipt(d), isFalse);
  });
}
