import 'package:flutter_test/flutter_test.dart';
import 'package:keepr/core/domain/money.dart';
import 'package:keepr/core/failures.dart';
import 'package:keepr/features/billing/domain/entities/entitlement.dart';
import 'package:keepr/features/insights/domain/insights.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/domain/entities/receipt_draft.dart';
import 'package:keepr/features/receipts/domain/services/receipt_factory.dart';
import 'package:keepr/features/receipts/domain/services/receipt_validator.dart';

import '../helpers/fixtures.dart';

void main() {
  group('ReceiptValidator (BR-05, BR-06, BR-11)', () {
    test('a complete receipt is valid', () {
      expect(ReceiptValidator.validate(receipt(items: [item(months: 12)]), now: fixedNow), isEmpty);
    });

    test('rejects empty merchant, future date and bad currency', () {
      final errors = ReceiptValidator.validate(
        receipt(merchant: ' ', purchaseDate: DateTime(2026, 10, 7), currency: 'rs'),
        now: fixedNow,
      );
      expect(errors.keys, containsAll(['merchant', 'purchaseDate', 'currency']));
    });

    test('rejects warranty above 120 months and return window above 365 days', () {
      final errors = ReceiptValidator.validate(receipt(returnDays: 400, items: [item(months: 121)]), now: fixedNow);
      expect(errors.keys, containsAll(['returnDays', 'items.0.warranty']));
    });

    test('unconfirmed low-confidence fields block saving', () {
      final errors = ReceiptValidator.validate(receipt(), now: fixedNow, unconfirmedLowConfidence: {'total'});
      expect(errors['total'], isNotNull);
    });
  });

  group('Entitlement (BR-07)', () {
    test('free plan allows 15 scans and 3 claim packs', () {
      var e = Entitlement.free(fixedNow);
      for (var i = 0; i < 15; i++) {
        expect(e.allows(QuotaKind.aiScan), isTrue);
        e = e.consumed(QuotaKind.aiScan);
      }
      expect(e.allows(QuotaKind.aiScan), isFalse);
      expect(e.scansLeft, 0);
      expect(e.copyWith(claimPacksUsed: 3).allows(QuotaKind.claimPack), isFalse);
    });

    test('premium is unlimited until it expires', () {
      final e = Entitlement.free(
        fixedNow,
      ).copyWith(tier: PlanTier.premium, scansUsed: 999, expiresAt: DateTime(2026, 11, 1));
      expect(e.allows(QuotaKind.aiScan), isTrue);
      expect(e.rolledOver(DateTime(2026, 11, 2)).isPremium, isFalse);
    });

    test('counters reset on a new month', () {
      final e = Entitlement.free(fixedNow).copyWith(scansUsed: 15, claimPacksUsed: 3);
      final next = e.rolledOver(DateTime(2026, 11, 1));
      expect(next.scansUsed, 0);
      expect(next.claimPacksUsed, 0);
    });
  });

  group('ReceiptFactory', () {
    test('builds a receipt from an AI draft with suggested warranty', () {
      var n = 0;
      final draft = ReceiptDraft(
        currency: 'PKR',
        status: ReceiptStatus.needsReview,
        merchant: ' City Mobiles ',
        purchaseDate: DateTime(2026, 9, 28),
        totalMinor: 8999900,
        category: Category.electronics,
        items: const [DraftItem(name: 'Phone', unitPriceMinor: 8999900, confidence: 0.9)],
        suggestedWarrantyMonths: 12,
        suggestedReturnDays: 7,
        confidence: const {'merchant': 0.95, 'total': 0.5},
      );
      final r = ReceiptFactory.fromDraft(
        draft,
        id: 'r',
        householdId: 'h',
        userId: 'u',
        now: fixedNow,
        newId: () => 'id${n++}',
      );

      expect(r.merchant, 'City Mobiles');
      expect(r.total, const Money(8999900, 'PKR'));
      expect(r.items.single.warranty?.months, 12);
      expect(r.returnDays, 7);
      expect(draft.lowConfidenceFields, {'total'});
    });

    test('clamps an AI date in the future to today', () {
      final draft = ReceiptDraft(
        currency: 'USD',
        status: ReceiptStatus.needsReview,
        purchaseDate: DateTime(2027, 1, 1),
      );
      final r = ReceiptFactory.fromDraft(
        draft,
        id: 'r',
        householdId: 'h',
        userId: 'u',
        now: fixedNow,
        newId: () => 'x',
      );
      expect(r.purchaseDate, DateTime(2026, 10, 6));
    });
  });

  group('Insights', () {
    test('totals by month and category in the chosen currency', () {
      final receipts = [
        receipt(
          id: 'a',
          purchaseDate: DateTime(2026, 10, 2),
          totalMinor: 1000,
          items: [item(priceMinor: 1000, months: 12)],
        ),
        receipt(id: 'b', purchaseDate: DateTime(2026, 9, 2), totalMinor: 500, category: Category.groceries),
        receipt(id: 'c', purchaseDate: DateTime(2026, 9, 3), totalMinor: 700, currency: 'USD'),
        receipt(id: 'd', purchaseDate: DateTime(2026, 9, 4), totalMinor: 900, status: ReceiptStatus.needsReview),
      ];
      final insights = ComputeInsights.compute(receipts, currency: 'PKR', months: 3, now: fixedNow);

      expect(insights.totalSpent.minor, 1500);
      expect(insights.byCategory.keys.first, Category.electronics);
      expect(insights.monthly.map((m) => m.total.minor), [0, 500, 1000]);
      expect(insights.otherCurrencyCount, 1);
      expect(insights.receiptCount, 3);
      expect(insights.protectedValue.minor, 1000);
    });

    test('CSV escapes commas and quotes', () {
      final csv = ReceiptsCsv.build([receipt(merchant: 'Ali "Best", Store')]);
      expect(csv.split('\n')[1], startsWith('"Ali ""Best"", Store",2026-10-01,18999.00,PKR'));
    });
  });
}
