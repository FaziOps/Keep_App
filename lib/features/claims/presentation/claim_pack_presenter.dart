import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../domain/claim_pack.dart';

sealed class ClaimPackUiState {
  const ClaimPackUiState();
}

final class ClaimIdle extends ClaimPackUiState {
  const ClaimIdle({this.issueError, this.claimsLeft});
  final String? issueError;
  final int? claimsLeft;
}

final class ClaimGenerating extends ClaimPackUiState {
  const ClaimGenerating();
}

final class ClaimReady extends ClaimPackUiState {
  const ClaimReady(this.pack);
  final ClaimPack pack;
}

final class ClaimPaywall extends ClaimPackUiState {
  const ClaimPaywall();
}

final class ClaimError extends ClaimPackUiState {
  const ClaimError(this.message);
  final String message;
}

/// Presenter for the claim pack screen (SSD-5).
class ClaimPackPresenter extends Notifier<ClaimPackUiState> {
  ClaimPackPresenter(this.receiptId);
  final String receiptId;

  @override
  ClaimPackUiState build() {
    // Listen rather than watch: using a claim pack updates the quota, which
    // must not reset the Ready state.
    ref.listen(entitlementProvider, (_, next) {
      if (state case ClaimIdle(:final issueError)) {
        state = ClaimIdle(issueError: issueError, claimsLeft: next.value?.claimPacksLeft);
      }
    });
    return ClaimIdle(claimsLeft: ref.read(entitlementProvider).value?.claimPacksLeft);
  }

  Future<void> generate({required String issue, String? itemId}) async {
    state = const ClaimGenerating();
    final user = ref.read(currentUserProvider).value;
    final result = await ref.read(generateClaimPackProvider)(
      receiptId: receiptId,
      issueDescription: issue,
      claimantName: user?.displayName ?? 'Customer',
      claimantEmail: user?.email,
      itemId: itemId,
    );
    if (!ref.mounted) return;
    state = switch (result) {
      Success(:final value) => ClaimReady(value),
      Failure(failure: QuotaExceeded()) => const ClaimPaywall(),
      Failure(failure: ValidationFailure(:final fieldErrors)) => ClaimIdle(issueError: fieldErrors['issue']),
      Failure(:final failure) => ClaimError(failure.message),
    };
    if (state is ClaimReady) await share();
  }

  Future<void> share() async {
    final current = state;
    if (current is! ClaimReady) return;
    try {
      await ref
          .read(fileExporterProvider)
          .share(
            bytes: current.pack.bytes,
            fileName: current.pack.fileName,
            mimeType: 'application/pdf',
            subject: 'Warranty claim',
          );
    } catch (_) {
      // The user can retry from the Ready state.
    }
  }

  void reset() => state = ClaimIdle(claimsLeft: ref.read(entitlementProvider).value?.claimPacksLeft);
}

final claimPackPresenterProvider = NotifierProvider.autoDispose.family<ClaimPackPresenter, ClaimPackUiState, String>(
  ClaimPackPresenter.new,
);
