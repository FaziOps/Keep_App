/// Domain failures. Data sources throw; repositories convert exceptions into
/// one of these so that no exception ever crosses a layer boundary.
sealed class AppFailure {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'You appear to be offline. Your changes are saved and will sync later.']);
}

final class AuthFailure extends AppFailure {
  const AuthFailure(super.message);
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(this.fieldErrors) : super('Please fix the highlighted fields.');

  /// Field key -> human readable error.
  final Map<String, String> fieldErrors;
}

final class ExtractionFailure extends AppFailure {
  const ExtractionFailure([super.message = 'We could not read this receipt. Please fill in the details.']);
}

enum QuotaKind { aiScan, claimPack, householdMember }

final class QuotaExceeded extends AppFailure {
  const QuotaExceeded(this.kind) : super('You have reached the limit of your Free plan.');

  final QuotaKind kind;
}

final class CloudUnavailableFailure extends AppFailure {
  const CloudUnavailableFailure([super.message = 'This feature needs a Keepr cloud account.']);
}

final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message);
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'Not found.']);
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([super.message = 'Something went wrong. Please try again.']);
}
