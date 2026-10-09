import 'dart:async';

import '../../../core/domain/clock.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../../../core/storage/local_store.dart';
import '../../protection/domain/usecases/schedule_reminders.dart';
import '../../receipts/data/datasources/receipt_local_data_source.dart';
import '../../receipts/data/datasources/receipt_remote_data_source.dart';
import '../../receipts/data/models/receipt_model.dart';
import '../../receipts/domain/entities/receipt.dart';
import '../domain/sync_repository.dart';
import 'outbox.dart';

/// Offline-first sync (SSD-4): drains the outbox, then pulls remote changes
/// for the active household.
class SyncService implements SyncRepository {
  SyncService({
    required LocalStore store,
    required ReceiptLocalDataSource local,
    required Outbox outbox,
    required Clock clock,
    required ScheduleReminders scheduleReminders,
    required String? Function() activeCloudHouseholdId,
    required Future<void> Function() afterSync,
    ReceiptRemoteDataSource? remote,
  }) : _store = store,
       _local = local,
       _outbox = outbox,
       _clock = clock,
       _scheduleReminders = scheduleReminders,
       _activeCloudHouseholdId = activeCloudHouseholdId,
       _afterSync = afterSync,
       _remote = remote {
    _status = SyncStatus(enabled: remote != null, pendingOps: outbox.length, lastSyncedAt: _lastSyncedAtAny());
    _outboxSub = outbox.watchLength().listen((n) => _update(_status.copyWith(pendingOps: n)));
  }

  final LocalStore _store;
  final ReceiptLocalDataSource _local;
  final Outbox _outbox;
  final Clock _clock;
  final ScheduleReminders _scheduleReminders;
  final String? Function() _activeCloudHouseholdId;
  final Future<void> Function() _afterSync;
  final ReceiptRemoteDataSource? _remote;

  final _statusController = StreamController<SyncStatus>.broadcast();
  late SyncStatus _status;
  StreamSubscription<int>? _outboxSub;
  Timer? _debounce;
  Timer? _periodic;
  Future<Result<SyncReport>>? _running;

  @override
  SyncStatus get status => _status;

  @override
  Stream<SyncStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  void _update(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Starts background triggers: connectivity regained and a 15-minute timer.
  void start(Stream<bool> online) {
    online.listen((isOnline) {
      if (isOnline) requestSync();
    });
    _periodic ??= Timer.periodic(const Duration(minutes: 15), (_) => requestSync());
  }

  @override
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  @override
  Future<Result<SyncReport>> syncNow() => _running ??= _sync().whenComplete(() => _running = null);

  Future<Result<SyncReport>> _sync() async {
    final remote = _remote;
    final householdId = _activeCloudHouseholdId();
    if (remote == null || householdId == null) {
      return const Success(SyncReport(skipped: true));
    }
    _update(_status.copyWith(isSyncing: true, clearError: true));
    var pushed = 0, pulled = 0, conflicts = 0;
    try {
      // 1. Push pending operations in order.
      for (final entry in _outbox.pending()) {
        if (entry.entity != 'receipt') {
          await _outbox.complete(entry);
          continue;
        }
        final receipt = _local.get(entry.entityId);
        if (receipt == null) {
          await _outbox.complete(entry);
          continue;
        }
        try {
          final uploaded = await _uploadAttachments(remote, receipt);
          final outcome = await remote.upsertReceipt(ReceiptModel.toJson(uploaded));
          if (outcome.conflict) {
            conflicts++;
            await _applyServerVersion(outcome.row, localAttachments: uploaded.attachments);
          } else {
            final latest = _local.get(receipt.id);
            // Only mark synced if the user did not edit it during the upload.
            if (latest != null && latest.updatedAt == receipt.updatedAt) {
              await _local.put(uploaded.copyWith(syncState: SyncState.synced));
            }
          }
          await _outbox.complete(entry);
          pushed++;
        } catch (e) {
          await _outbox.markFailed(entry, e.toString());
          final current = _local.get(receipt.id);
          if (current != null) await _local.put(current.copyWith(syncState: SyncState.failed));
          rethrow;
        }
      }

      // 2. Pull changes made on other devices or by household members.
      final sinceKey = 'last_sync:$householdId';
      final since = _store.meta.get(sinceKey);
      final rows = await remote.pullChanges(householdId, since == null ? null : DateTime.parse(since));
      DateTime? newest;
      for (final row in rows) {
        final id = row['id'] as String;
        // Server clock is the cursor; client timestamps are only used for LWW.
        final updatedAt = DateTime.parse((row['server_updated_at'] ?? row['updated_at']) as String);
        if (newest == null || updatedAt.isAfter(newest)) newest = updatedAt;
        if (_outbox.contains('receipt', id)) continue; // local change wins; it is pushed next time
        final server = ReceiptModel.fromJson(row, syncState: SyncState.synced);
        await _local.put(server);
        await _scheduleReminders(server);
        pulled++;
      }
      if (newest != null) await _store.meta.put(sinceKey, newest.toUtc().toIso8601String());

      await _afterSync();
      _update(_status.copyWith(isSyncing: false, lastSyncedAt: _clock(), pendingOps: _outbox.length));
      return Success(SyncReport(pushed: pushed, pulled: pulled, conflicts: conflicts));
    } catch (e) {
      _update(
        _status.copyWith(
          isSyncing: false,
          lastError: 'Sync paused. Will retry automatically.',
          pendingOps: _outbox.length,
        ),
      );
      return const Failure(NetworkFailure());
    }
  }

  Future<Receipt> _uploadAttachments(ReceiptRemoteDataSource remote, Receipt receipt) async {
    final attachments = <Attachment>[];
    for (final a in receipt.attachments) {
      if (a.isUploaded) {
        attachments.add(a);
        continue;
      }
      final bytes = await _local.getAttachment(a.id);
      if (bytes == null) continue;
      final path = await remote.uploadAttachment(
        householdId: receipt.householdId,
        receiptId: receipt.id,
        attachmentId: a.id,
        bytes: bytes,
        mimeType: a.mimeType,
      );
      attachments.add(a.withRemotePath(path));
    }
    return receipt.copyWith(attachments: attachments);
  }

  /// BR-13: the newer server row wins; attachments are additive.
  Future<void> _applyServerVersion(Map<String, dynamic> row, {required List<Attachment> localAttachments}) async {
    final server = ReceiptModel.fromJson(row, syncState: SyncState.synced);
    final serverIds = server.attachments.map((a) => a.id).toSet();
    final missing = localAttachments.where((a) => !serverIds.contains(a.id)).toList();
    final merged = server.copyWith(
      attachments: [...server.attachments, ...missing],
      syncState: missing.isEmpty ? SyncState.synced : SyncState.pending,
    );
    await _local.put(merged);
    if (missing.isNotEmpty) await _outbox.enqueue('receipt', merged.id);
    await _scheduleReminders(merged);
  }

  DateTime? _lastSyncedAtAny() {
    DateTime? latest;
    for (final key in _store.meta.keys.whereType<String>().where((k) => k.startsWith('last_sync:'))) {
      final d = DateTime.tryParse(_store.meta.get(key) ?? '');
      if (d != null && (latest == null || d.isAfter(latest))) latest = d;
    }
    return latest?.toLocal();
  }

  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    _outboxSub?.cancel();
    _statusController.close();
  }
}
