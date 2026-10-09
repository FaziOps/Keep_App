import '../../../core/storage/local_store.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.entity,
    required this.entityId,
    required this.op,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String entity;
  final String entityId;
  final String op;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  String get key => '$entity:$entityId';

  Map<String, dynamic> toJson() => {
    'entity': entity,
    'entity_id': entityId,
    'op': op,
    'queued_at': queuedAt.toIso8601String(),
    'attempts': attempts,
    'last_error': lastError,
  };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
    entity: j['entity'] as String,
    entityId: j['entity_id'] as String,
    op: j['op'] as String,
    queuedAt: DateTime.parse(j['queued_at'] as String),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    lastError: j['last_error'] as String?,
  );

  OutboxEntry failed(String error) => OutboxEntry(
    entity: entity,
    entityId: entityId,
    op: op,
    queuedAt: queuedAt,
    attempts: attempts + 1,
    lastError: error,
  );
}

/// Pending writes waiting to be pushed. One entry per entity: the latest
/// local state is what gets uploaded, so repeated edits collapse.
class Outbox {
  const Outbox(this._store);
  final LocalStore _store;

  Future<void> enqueue(String entity, String entityId, {String op = 'upsert'}) {
    final entry = OutboxEntry(entity: entity, entityId: entityId, op: op, queuedAt: DateTime.now());
    return _store.outbox.put(entry.key, LocalStore.encode(entry.toJson()));
  }

  List<OutboxEntry> pending() {
    final entries = [for (final raw in _store.outbox.values) OutboxEntry.fromJson(LocalStore.decode(raw))]
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return entries;
  }

  bool contains(String entity, String entityId) => _store.outbox.containsKey('$entity:$entityId');

  int get length => _store.outbox.length;

  Stream<int> watchLength() => watchBox(_store.outbox, () => _store.outbox.length);

  Future<void> complete(OutboxEntry entry) => _store.outbox.delete(entry.key);

  Future<void> markFailed(OutboxEntry entry, String error) =>
      _store.outbox.put(entry.key, LocalStore.encode(entry.failed(error).toJson()));
}
