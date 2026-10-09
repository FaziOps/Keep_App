import '../../../core/storage/local_store.dart';
import '../domain/entities/reminder.dart';
import '../domain/repositories/reminder_repository.dart';

class ReminderRepositoryImpl implements ReminderRepository {
  const ReminderRepositoryImpl(this._store);
  final LocalStore _store;

  List<Reminder> _all() =>
      [for (final raw in _store.reminders.values) _fromJson(LocalStore.decode(raw))]
        ..sort((a, b) => a.fireAt.compareTo(b.fireAt));

  @override
  Stream<List<Reminder>> watchAll() => watchBox(_store.reminders, _all);

  @override
  Stream<List<Reminder>> watchForReceipt(String receiptId) =>
      watchBox(_store.reminders, () => _all().where((r) => r.receiptId == receiptId).toList());

  @override
  Future<List<Reminder>> forReceipt(String receiptId) async => _all().where((r) => r.receiptId == receiptId).toList();

  @override
  Future<void> replaceForReceipt(String receiptId, List<Reminder> reminders) async {
    final stale = _all().where((r) => r.receiptId == receiptId).map((r) => r.id);
    await _store.reminders.deleteAll(stale);
    await _store.reminders.putAll({for (final r in reminders) r.id: LocalStore.encode(_toJson(r))});
  }

  @override
  Future<void> dismiss(String reminderId) async {
    final raw = _store.reminders.get(reminderId);
    if (raw == null) return;
    final dismissed = _fromJson(LocalStore.decode(raw)).dismissed();
    await _store.reminders.put(reminderId, LocalStore.encode(_toJson(dismissed)));
  }

  static Map<String, dynamic> _toJson(Reminder r) => {
    'id': r.id,
    'receipt_id': r.receiptId,
    'type': r.type.name,
    'fire_at': r.fireAt.toIso8601String(),
    'title': r.title,
    'body': r.body,
    'state': r.state.name,
  };

  static Reminder _fromJson(Map<String, dynamic> j) => Reminder(
    id: j['id'] as String,
    receiptId: j['receipt_id'] as String,
    type: ReminderType.values.byName(j['type'] as String),
    fireAt: DateTime.parse(j['fire_at'] as String),
    title: j['title'] as String,
    body: j['body'] as String,
    state: ReminderState.values.byName(j['state'] as String),
  );
}
