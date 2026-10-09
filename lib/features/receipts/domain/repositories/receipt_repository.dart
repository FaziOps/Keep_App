import 'dart:typed_data';

import '../../../../core/result.dart';
import '../entities/receipt.dart';
import '../entities/receipt_draft.dart';

abstract interface class ReceiptRepository {
  /// Live, non-deleted receipts of a household, newest purchase first.
  Stream<List<Receipt>> watchReceipts(String householdId);

  Stream<Receipt?> watchReceipt(String id);

  Future<Result<Receipt>> getReceipt(String id);

  /// Saves locally (source of truth) and queues the change for sync.
  /// [newAttachmentBytes] maps attachment id -> image bytes.
  Future<Result<Receipt>> save(Receipt receipt, {Map<String, Uint8List> newAttachmentBytes = const {}});

  /// Soft delete (BR-09).
  Future<Result<void>> delete(String id);

  /// Receipts deleted in the last 30 days.
  Stream<List<Receipt>> watchTrash(String householdId);

  Future<Result<Receipt>> restore(String id);

  /// Image bytes, from the local cache or downloaded from the cloud.
  Future<Uint8List?> attachmentBytes(Attachment attachment);

  /// BR-10 candidates.
  Future<List<Receipt>> findDuplicates({
    required String householdId,
    required String merchant,
    required DateTime purchaseDate,
    required int totalMinor,
    String? excludeId,
  });

  /// Removes receipts that have been in the trash for over 30 days.
  Future<void> purgeExpiredTrash(DateTime now);
}

/// Port to receipt reading. Implementations combine on-device text
/// recognition with the cloud AI service.
abstract interface class ReceiptExtractor {
  /// Cloud AI is configured and the user is signed in.
  bool get isCloudAvailable;

  /// The device can read text itself (Android and iOS).
  bool get isOnDeviceAvailable;

  /// Reads [image]. With [allowCloud] false (e.g. quota used up) only the
  /// device is used. The returned draft records which engine produced it.
  Future<Result<ReceiptDraft>> extract({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
    bool allowCloud = true,
  });
}
