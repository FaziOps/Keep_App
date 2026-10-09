enum ReminderType { returnWindow, warrantyEnd, custom }

enum ReminderState { scheduled, dismissed }

class Reminder {
  const Reminder({
    required this.id,
    required this.receiptId,
    required this.type,
    required this.fireAt,
    required this.title,
    required this.body,
    this.state = ReminderState.scheduled,
  });

  /// Deterministic id so re-planning a receipt is idempotent.
  final String id;
  final String receiptId;
  final ReminderType type;
  final DateTime fireAt;
  final String title;
  final String body;
  final ReminderState state;

  Reminder dismissed() => Reminder(
    id: id,
    receiptId: receiptId,
    type: type,
    fireAt: fireAt,
    title: title,
    body: body,
    state: ReminderState.dismissed,
  );
}
