import '../../../../core/domain/clock.dart';
import '../../../receipts/domain/entities/receipt.dart';
import '../entities/reminder.dart';
import '../repositories/reminder_repository.dart';
import '../services/reminder_planner.dart';

/// Replaces a receipt's reminders with a fresh plan and registers them with
/// the OS. Idempotent: safe to call after every save or sync.
class ScheduleReminders {
  const ScheduleReminders(this._repository, this._scheduler, this._clock, {required this.notificationsEnabled});

  final ReminderRepository _repository;
  final ReminderScheduler _scheduler;
  final Clock _clock;
  final bool Function() notificationsEnabled;

  Future<List<Reminder>> call(Receipt receipt) async {
    final previous = await _repository.forReceipt(receipt.id);
    final dismissed = {
      for (final r in previous)
        if (r.state == ReminderState.dismissed) r.id,
    };
    final planned = ReminderPlanner.plan(
      receipt,
      _clock(),
    ).map((r) => dismissed.contains(r.id) ? r.dismissed() : r).toList();

    for (final r in previous) {
      await _scheduler.cancel(r.id);
    }
    await _repository.replaceForReceipt(receipt.id, planned);

    if (notificationsEnabled() && _scheduler.isSupported) {
      for (final r in planned.where((r) => r.state == ReminderState.scheduled)) {
        await _scheduler.schedule(r);
      }
    }
    return planned;
  }

  Future<void> cancelFor(String receiptId) async {
    for (final r in await _repository.forReceipt(receiptId)) {
      await _scheduler.cancel(r.id);
    }
    await _repository.replaceForReceipt(receiptId, const []);
  }
}
