import 'dart:typed_data';

import '../../../../core/domain/clock.dart';
import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../../household/domain/entities/household.dart';
import '../../../sync/data/outbox.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../datasources/receipt_local_data_source.dart';
import '../datasources/receipt_remote_data_source.dart';

/// Offline-first: every read comes from the local store; writes are stored
/// locally and queued in the outbox for the sync service.
class ReceiptRepositoryImpl implements ReceiptRepository {
  ReceiptRepositoryImpl({
    required ReceiptLocalDataSource local,
    required Outbox outbox,
    required Clock clock,
    required void Function() onLocalChange,
    ReceiptRemoteDataSource? remote,
  }) : _local = local,
       _outbox = outbox,
       _clock = clock,
       _onLocalChange = onLocalChange,
       _remote = remote;

  final ReceiptLocalDataSource _local;
  final Outbox _outbox;
  final Clock _clock;
  final void Function() _onLocalChange;
  final ReceiptRemoteDataSource? _remote;

  static const trashDays = 30;

  bool _isCloud(String householdId) => _remote != null && !householdId.startsWith(Household.localIdFor(''));

  @override
  Stream<List<Receipt>> watchReceipts(String householdId) => _local.watchHousehold(householdId);

  @override
  Stream<Receipt?> watchReceipt(String id) => _local.watchOne(id);

  @override
  Future<Result<Receipt>> getReceipt(String id) async {
    final r = _local.get(id);
    return r == null ? const Failure(NotFoundFailure('Receipt not found.')) : Success(r);
  }

  @override
  Future<Result<Receipt>> save(Receipt receipt, {Map<String, Uint8List> newAttachmentBytes = const {}}) async {
    try {
      final cloud = _isCloud(receipt.householdId);
      final toStore = receipt.copyWith(syncState: cloud ? SyncState.pending : SyncState.localOnly);
      for (final entry in newAttachmentBytes.entries) {
        await _local.putAttachment(entry.key, entry.value);
      }
      await _local.put(toStore);
      if (cloud) {
        await _outbox.enqueue('receipt', receipt.id);
        _onLocalChange();
      }
      return Success(toStore);
    } catch (_) {
      return const Failure(UnexpectedFailure('Could not save the receipt on this device.'));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    final existing = _local.get(id);
    if (existing == null) return const Failure(NotFoundFailure());
    final now = _clock();
    final result = await save(existing.copyWith(deletedAt: now, updatedAt: now));
    return result.fold(Failure.new, (_) => const Success(null));
  }

  @override
  Stream<List<Receipt>> watchTrash(String householdId) => _local
      .watchHousehold(householdId)
      .map(
        (_) =>
            _local.all().where((r) => r.householdId == householdId && r.isDeleted).toList()
              ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!)),
      );

  @override
  Future<Result<Receipt>> restore(String id) async {
    final existing = _local.get(id);
    if (existing == null) return const Failure(NotFoundFailure());
    return save(existing.copyWith(deletedAt: null, updatedAt: _clock()));
  }

  @override
  Future<Uint8List?> attachmentBytes(Attachment attachment) async {
    final cached = await _local.getAttachment(attachment.id);
    if (cached != null) return cached;
    final path = attachment.remotePath;
    if (path == null || _remote == null) return null;
    try {
      final bytes = await _remote.downloadAttachment(path);
      await _local.putAttachment(attachment.id, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Receipt>> findDuplicates({
    required String householdId,
    required String merchant,
    required DateTime purchaseDate,
    required int totalMinor,
    String? excludeId,
  }) async {
    final name = merchant.trim().toLowerCase();
    final day = dateOnly(purchaseDate);
    return _local
        .forHousehold(householdId)
        .where(
          (r) =>
              r.id != excludeId &&
              r.merchant.trim().toLowerCase() == name &&
              dateOnly(r.purchaseDate) == day &&
              r.total.minor == totalMinor,
        )
        .toList();
  }

  @override
  Future<void> purgeExpiredTrash(DateTime now) async {
    for (final r in _local.all()) {
      final deletedAt = r.deletedAt;
      if (deletedAt == null || now.difference(deletedAt).inDays < trashDays) continue;
      if (_outbox.contains('receipt', r.id)) continue;
      for (final a in r.attachments) {
        await _local.removeAttachment(a.id);
      }
      await _local.remove(r.id);
    }
  }
}
