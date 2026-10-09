import '../../../../core/domain/clock.dart';
import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../../billing/domain/repositories/entitlement_repository.dart';
import '../entities/receipt.dart';
import '../repositories/receipt_repository.dart';
import '../services/receipt_factory.dart';

/// FR-AI-07: runs AI extraction for receipts captured while offline.
class ProcessQueuedReceipts {
  const ProcessQueuedReceipts(this._repository, this._extractor, this._entitlements, this._clock, this._newId);

  final ReceiptRepository _repository;
  final ReceiptExtractor _extractor;
  final EntitlementRepository _entitlements;
  final Clock _clock;
  final String Function() _newId;

  /// Returns how many receipts were moved to NeedsReview.
  Future<int> call(List<Receipt> queued) async {
    var processed = 0;
    for (final receipt in queued.where((r) => r.status == ReceiptStatus.queuedOffline)) {
      if (!_extractor.isCloudAvailable) break;
      if (!(await _entitlements.current()).allows(QuotaKind.aiScan)) break;
      final cover = receipt.coverImage;
      if (cover == null) continue;
      final bytes = await _repository.attachmentBytes(cover);
      if (bytes == null) continue;

      final result = await _extractor.extract(image: bytes, mimeType: cover.mimeType, currency: receipt.total.currency);
      switch (result) {
        case Success(:final value):
          await _entitlements.recordUsage(QuotaKind.aiScan);
          final now = _clock();
          await _repository.save(
            ReceiptFactory.applyDraft(receipt, value, newId: _newId, now: now).copyWith(updatedAt: now),
          );
          processed++;
        case Failure(failure: NetworkFailure()):
          return processed;
        case Failure():
          await _repository.save(receipt.copyWith(status: ReceiptStatus.extractionFailed, updatedAt: _clock()));
      }
    }
    return processed;
  }
}
