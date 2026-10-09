import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../../../core/services/image_capture.dart';
import '../../domain/entities/receipt_draft.dart';

sealed class ScanUiState {
  const ScanUiState();
}

final class ScanIdle extends ScanUiState {
  const ScanIdle({required this.aiAvailable, this.cloudAi = false, this.scansLeft});
  final bool aiAvailable;

  /// Cloud AI is in use, so the monthly quota applies.
  final bool cloudAi;

  /// Null when unlimited (Premium).
  final int? scansLeft;
}

final class ScanProcessing extends ScanUiState {
  const ScanProcessing(this.image, this.step);
  final Uint8List image;
  final String step;
}

/// Extraction finished; the View navigates to the review form.
final class ScanReady extends ScanUiState {
  const ScanReady(this.draft);
  final ReceiptDraft draft;
}

final class ScanQuotaExceeded extends ScanUiState {
  const ScanQuotaExceeded();
}

final class ScanError extends ScanUiState {
  const ScanError(this.message);
  final String message;
}

/// Presenter for the Scan screen (SSD-2).
class ScanPresenter extends Notifier<ScanUiState> {
  @override
  ScanUiState build() {
    // Listen rather than watch: a quota update mid-scan must not reset the flow.
    ref.listen(entitlementProvider, (_, next) {
      final current = state;
      if (current is ScanIdle) {
        state = ScanIdle(aiAvailable: current.aiAvailable, cloudAi: current.cloudAi, scansLeft: next.value?.scansLeft);
      }
    });
    return ScanIdle(
      aiAvailable: ref.read(scanReceiptProvider).isAiAvailable,
      cloudAi: ref.read(scanReceiptProvider).isCloudAvailable,
      scansLeft: ref.read(entitlementProvider).value?.scansLeft,
    );
  }

  String get _currency => ref.read(settingsRepositoryProvider).current.currency;

  Future<void> capture({required bool fromCamera}) async {
    final CapturedImage? image;
    try {
      image = await ref.read(imageCaptureProvider).capture(fromCamera: fromCamera);
    } catch (_) {
      state = ScanError(
        fromCamera
            ? 'Keepr needs camera access to scan receipts. You can allow it in Settings.'
            : 'Could not open your photos.',
      );
      return;
    }
    if (image == null || !ref.mounted) return;

    final scan = ref.read(scanReceiptProvider);
    state = ScanProcessing(image.bytes, scan.isAiAvailable ? 'Reading your receipt…' : 'Preparing your receipt…');
    final result = await scan(image: image.bytes, mimeType: image.mimeType, currency: _currency);
    if (!ref.mounted) return;
    state = switch (result) {
      Success(:final value) => ScanReady(value),
      Failure(failure: QuotaExceeded()) => const ScanQuotaExceeded(),
      Failure(:final failure) => ScanError(failure.message),
    };
  }

  void enterManually() => state = ScanReady(ReceiptDraft.manual(currency: _currency));

  void reset() => ref.invalidateSelf();
}

final scanPresenterProvider = NotifierProvider.autoDispose<ScanPresenter, ScanUiState>(ScanPresenter.new);
