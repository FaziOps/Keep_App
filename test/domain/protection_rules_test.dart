import 'package:flutter_test/flutter_test.dart';
import 'package:keepr/features/protection/domain/services/reminder_planner.dart';
import 'package:keepr/features/protection/domain/entities/reminder.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/domain/services/protection_rules.dart';

import '../helpers/fixtures.dart';

void main() {
  group('BR-01 warranty end date', () {
    test('adds calendar months', () {
      expect(ProtectionRules.addMonths(DateTime(2026, 3, 15), 12), DateTime(2027, 3, 15));
      expect(ProtectionRules.addMonths(DateTime(2026, 11, 20), 3), DateTime(2027, 2, 20));
    });

    test('clamps to the last day of shorter months', () {
      expect(ProtectionRules.addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(ProtectionRules.addMonths(DateTime(2027, 1, 31), 13), DateTime(2028, 2, 29));
    });

    test('no warranty for 0 months or null', () {
      expect(ProtectionRules.warrantyEnd(DateTime(2026, 1, 1), const Warranty(months: 0)), isNull);
      expect(ProtectionRules.warrantyEnd(DateTime(2026, 1, 1), null), isNull);
    });
  });

  test('BR-02 return deadline is end of day', () {
    expect(ProtectionRules.returnDeadline(DateTime(2026, 10, 1), 14), DateTime(2026, 10, 15, 23, 59, 59));
    expect(ProtectionRules.returnDeadline(DateTime(2026, 10, 1), null), isNull);
  });

  group('BR-12 warranty status', () {
    final now = DateTime(2026, 10, 6);
    test('active when more than 30 days left', () {
      expect(ProtectionRules.statusFor(DateTime(2026, 11, 6), now), WarrantyStatus.active);
    });
    test('expiring soon at 30 days or less', () {
      expect(ProtectionRules.statusFor(DateTime(2026, 11, 5), now), WarrantyStatus.expiringSoon);
      expect(ProtectionRules.statusFor(DateTime(2026, 10, 6), now), WarrantyStatus.expiringSoon);
    });
    test('expired after the end date', () {
      expect(ProtectionRules.statusFor(DateTime(2026, 10, 5), now), WarrantyStatus.expired);
    });
  });

  test('protected value counts only items under warranty', () {
    final r = receipt(
      items: [
        item(id: 'a', priceMinor: 1000, months: 12),
        item(id: 'b', priceMinor: 500),
      ],
    );
    expect(r.protectedValue(fixedNow).minor, 1000);
    expect(r.overallWarrantyStatus(fixedNow), WarrantyStatus.active);
  });

  group('BR-03 / BR-04 reminder plan', () {
    test('return −3 days and warranty −30/−7 days at 10:00', () {
      final r = receipt(purchaseDate: DateTime(2026, 10, 1), returnDays: 14, items: [item(months: 12)]);
      final plan = ReminderPlanner.plan(r, fixedNow);

      expect(plan.map((p) => p.type), [ReminderType.returnWindow, ReminderType.warrantyEnd, ReminderType.warrantyEnd]);
      expect(plan[0].fireAt, DateTime(2026, 10, 12, 10));
      expect(plan[1].fireAt, DateTime(2027, 9, 1, 10));
      expect(plan[2].fireAt, DateTime(2027, 9, 24, 10));
    });

    test('skips reminders in the past', () {
      final r = receipt(purchaseDate: DateTime(2026, 9, 1), returnDays: 7, items: [item(months: 1)]);
      expect(ReminderPlanner.plan(r, fixedNow), isEmpty);
    });

    test('drafts and deleted receipts get no reminders', () {
      final draft = receipt(status: ReceiptStatus.needsReview, returnDays: 30, items: [item(months: 12)]);
      final deleted = receipt(deletedAt: fixedNow, returnDays: 30);
      expect(ReminderPlanner.plan(draft, fixedNow), isEmpty);
      expect(ReminderPlanner.plan(deleted, fixedNow), isEmpty);
    });

    test('ids are deterministic so re-planning is idempotent', () {
      final r = receipt(returnDays: 14, items: [item(months: 12)]);
      expect(ReminderPlanner.plan(r, fixedNow).map((e) => e.id), ReminderPlanner.plan(r, fixedNow).map((e) => e.id));
    });
  });
}
