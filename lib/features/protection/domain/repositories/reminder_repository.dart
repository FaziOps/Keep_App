import '../entities/reminder.dart';

abstract interface class ReminderRepository {
  Stream<List<Reminder>> watchAll();
  Stream<List<Reminder>> watchForReceipt(String receiptId);
  Future<List<Reminder>> forReceipt(String receiptId);
  Future<void> replaceForReceipt(String receiptId, List<Reminder> reminders);
  Future<void> dismiss(String reminderId);
}

/// Port to the OS notification system.
abstract interface class ReminderScheduler {
  /// False on platforms without scheduled local notifications (web).
  bool get isSupported;
  Future<bool> requestPermission();
  Future<void> schedule(Reminder reminder);
  Future<void> cancel(String reminderId);
}
