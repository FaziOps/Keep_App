import 'dart:typed_data';

import '../../../../core/domain/clock.dart';
import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../../billing/domain/repositories/entitlement_repository.dart';
import '../../../protection/domain/usecases/schedule_reminders.dart';
import '../entities/receipt.dart';
import '../entities/receipt_draft.dart';
import '../repositories/receipt_repository.dart';
import '../services/receipt_validator.dart';

/// Captured image -> structured draft (SSD-2). Uses cloud AI when it is
/// available and within quota, otherwise reads the receipt on the device.
class ScanReceipt {
  const ScanReceipt(this._extractor, this._entitlements);

  final ReceiptExtractor _extractor;
  final EntitlementRepository _entitlements;

  /// Cloud AI (quota-limited) is available for this account.
  bool get isCloudAvailable => _extractor.isCloudAvailable;

  /// Some automatic reader exists on this device / account.
  bool get isAiAvailable => _extractor.isCloudAvailable || _extractor.isOnDeviceAvailable;

  Future<Result<ReceiptDraft>> call({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
  }) async {
    ReceiptDraft manual(ReceiptStatus status, String message) => ReceiptDraft.manual(
      currency: currency,
      image: image,
      imageMimeType: mimeType,
      status: status,
      message: message,
    );

    if (!isAiAvailable) {
      return Success(
        manual(
          ReceiptStatus.manualEntry,
          'Automatic reading works in the Android and iOS apps, or with a Keepr cloud account. Add the details below.',
        ),
      );
    }

    final cloudAllowed = _extractor.isCloudAvailable && (await _entitlements.current()).allows(QuotaKind.aiScan);
    if (!cloudAllowed && !_extractor.isOnDeviceAvailable) {
      return const Failure(QuotaExceeded(QuotaKind.aiScan));
    }

    final result = await _extractor.extract(
      image: image,
      mimeType: mimeType,
      currency: currency,
      locale: locale,
      allowCloud: cloudAllowed,
    );
    switch (result) {
      case Success(:final value):
        if (value.engine == ExtractionEngine.cloudAi) await _entitlements.recordUsage(QuotaKind.aiScan);
        return Success(value.withImage(image, mimeType));
      case Failure(failure: NetworkFailure()):
        // FR-AI-07: keep the capture; extraction is retried on reconnect.
        return Success(
          manual(
            ReceiptStatus.queuedOffline,
            'You are offline. Save it now and Keepr will read it when you reconnect, or fill in the details yourself.',
          ),
        );
      case Failure(failure: final QuotaExceeded q):
        return Failure(q);
      case Failure(:final failure):
        return Success(manual(ReceiptStatus.extractionFailed, failure.message));
    }
  }
}

/// Validates, stores and schedules reminders (SSD-3).
class SaveReceipt {
  const SaveReceipt(this._repository, this._scheduleReminders, this._clock);

  final ReceiptRepository _repository;
  final ScheduleReminders _scheduleReminders;
  final Clock _clock;

  /// Saves a confirmed receipt. Business rules must pass.
  Future<Result<Receipt>> confirm(
    Receipt receipt, {
    Map<String, Uint8List> newAttachmentBytes = const {},
    Set<String> unconfirmedLowConfidence = const {},
  }) async {
    final now = _clock();
    final errors = ReceiptValidator.validate(receipt, now: now, unconfirmedLowConfidence: unconfirmedLowConfidence);
    if (errors.isNotEmpty) return Failure(ValidationFailure(errors));

    final saved = await _repository.save(
      receipt.copyWith(status: ReceiptStatus.confirmed, updatedAt: now),
      newAttachmentBytes: newAttachmentBytes,
    );
    if (saved case Success(:final value)) {
      await _scheduleReminders(value);
    }
    return saved;
  }

  /// Saves an unconfirmed draft (e.g. queued for offline extraction).
  Future<Result<Receipt>> saveDraft(Receipt receipt, {Map<String, Uint8List> newAttachmentBytes = const {}}) =>
      _repository.save(receipt.copyWith(updatedAt: _clock()), newAttachmentBytes: newAttachmentBytes);
}

class DeleteReceipt {
  const DeleteReceipt(this._repository, this._scheduleReminders);

  final ReceiptRepository _repository;
  final ScheduleReminders _scheduleReminders;

  Future<Result<void>> call(String id) async {
    final result = await _repository.delete(id);
    if (result.isSuccess) await _scheduleReminders.cancelFor(id);
    return result;
  }
}

class ArchiveReceipt {
  const ArchiveReceipt(this._repository, this._scheduleReminders, this._clock);

  final ReceiptRepository _repository;
  final ScheduleReminders _scheduleReminders;
  final Clock _clock;

  Future<Result<Receipt>> call(Receipt receipt, {required bool archived}) async {
    final updated = receipt.copyWith(
      status: archived ? ReceiptStatus.archived : ReceiptStatus.confirmed,
      updatedAt: _clock(),
    );
    final result = await _repository.save(updated);
    if (result case Success(:final value)) {
      archived ? await _scheduleReminders.cancelFor(value.id) : await _scheduleReminders(value);
    }
    return result;
  }
}

/// BR-10.
class FindDuplicates {
  const FindDuplicates(this._repository);
  final ReceiptRepository _repository;

  Future<List<Receipt>> call(Receipt candidate) {
    if (candidate.merchant.trim().isEmpty) return Future.value(const []);
    return _repository.findDuplicates(
      householdId: candidate.householdId,
      merchant: candidate.merchant,
      purchaseDate: candidate.purchaseDate,
      totalMinor: candidate.total.minor,
      excludeId: candidate.id,
    );
  }
}
