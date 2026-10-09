import 'dart:typed_data';

import '../../../core/domain/clock.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../../billing/domain/repositories/entitlement_repository.dart';
import '../../receipts/domain/entities/receipt.dart';
import '../../receipts/domain/repositories/receipt_repository.dart';

class ClaimPack {
  const ClaimPack({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
}

class ClaimPackRequest {
  const ClaimPackRequest({
    required this.receipt,
    required this.images,
    required this.issueDescription,
    required this.claimantName,
    required this.generatedAt,
    this.claimantEmail,
    this.itemId,
  });

  final Receipt receipt;
  final List<Uint8List> images;
  final String issueDescription;
  final String claimantName;
  final String? claimantEmail;
  final DateTime generatedAt;

  /// The item being claimed; null means the whole purchase.
  final String? itemId;
}

abstract interface class ClaimPackRenderer {
  Future<Uint8List> render(ClaimPackRequest request);
}

class GenerateClaimPack {
  const GenerateClaimPack(this._receipts, this._entitlements, this._renderer, this._clock);

  final ReceiptRepository _receipts;
  final EntitlementRepository _entitlements;
  final ClaimPackRenderer _renderer;
  final Clock _clock;

  Future<Result<ClaimPack>> call({
    required String receiptId,
    required String issueDescription,
    required String claimantName,
    String? claimantEmail,
    String? itemId,
  }) async {
    final entitlement = await _entitlements.current();
    if (!entitlement.allows(QuotaKind.claimPack)) {
      return const Failure(QuotaExceeded(QuotaKind.claimPack));
    }
    final found = await _receipts.getReceipt(receiptId);
    final receipt = found.valueOrNull;
    if (receipt == null) return Failure(found.failureOrNull ?? const NotFoundFailure());
    if (issueDescription.trim().length < 10) {
      return const Failure(ValidationFailure({'issue': 'Describe the problem in a sentence or two'}));
    }

    final images = <Uint8List>[];
    for (final a in receipt.attachments) {
      final bytes = await _receipts.attachmentBytes(a);
      if (bytes != null) images.add(bytes);
    }

    try {
      final now = _clock();
      final pdf = await _renderer.render(
        ClaimPackRequest(
          receipt: receipt,
          images: images,
          issueDescription: issueDescription.trim(),
          claimantName: claimantName,
          claimantEmail: claimantEmail,
          generatedAt: now,
          itemId: itemId,
        ),
      );
      await _entitlements.recordUsage(QuotaKind.claimPack);
      final safeMerchant = receipt.merchant.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
      return Success(ClaimPack(fileName: 'Keepr-claim-$safeMerchant-${now.millisecondsSinceEpoch}.pdf', bytes: pdf));
    } catch (_) {
      return const Failure(UnexpectedFailure('Could not create the PDF.'));
    }
  }
}
