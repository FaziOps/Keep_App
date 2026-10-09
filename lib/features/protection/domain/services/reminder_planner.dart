import '../../../receipts/domain/entities/receipt.dart';
import '../../../receipts/domain/services/protection_rules.dart';
import '../entities/reminder.dart';

/// BR-03 / BR-04: which reminders a receipt should have.
class ReminderPlanner {
  const ReminderPlanner._();

  static const returnOffsetDays = 3;
  static const warrantyOffsetsDays = [30, 7];
  static const fireHour = 10;

  static List<Reminder> plan(Receipt receipt, DateTime now) {
    if (!receipt.status.isConfirmed || receipt.isDeleted) return const [];
    final reminders = <Reminder>[];

    final deadline = receipt.returnDeadline;
    if (deadline != null) {
      final fireAt = _at(deadline, returnOffsetDays);
      if (fireAt.isAfter(now)) {
        reminders.add(
          Reminder(
            id: '${receipt.id}_return',
            receiptId: receipt.id,
            type: ReminderType.returnWindow,
            fireAt: fireAt,
            title: 'Return window closing',
            body: '${receipt.merchant}: $returnOffsetDays days left to return your purchase.',
          ),
        );
      }
    }

    for (final item in receipt.items) {
      final end = receipt.warrantyEndFor(item);
      if (end == null) continue;
      for (final offset in warrantyOffsetsDays) {
        final fireAt = _at(end, offset);
        if (!fireAt.isAfter(now)) continue;
        reminders.add(
          Reminder(
            id: '${receipt.id}_${item.id}_w$offset',
            receiptId: receipt.id,
            type: ReminderType.warrantyEnd,
            fireAt: fireAt,
            title: 'Warranty ends in $offset days',
            body: '${item.name} from ${receipt.merchant}. Check it while it is still covered.',
          ),
        );
      }
    }
    reminders.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return reminders;
  }

  static DateTime _at(DateTime day, int daysBefore) => DateTime(day.year, day.month, day.day - daysBefore, fireHour);
}
