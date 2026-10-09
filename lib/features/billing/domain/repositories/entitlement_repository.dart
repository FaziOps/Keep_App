import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../entities/entitlement.dart';

abstract interface class EntitlementRepository {
  Stream<Entitlement> watch();
  Future<Entitlement> current();
  Future<void> recordUsage(QuotaKind kind);

  /// Pulls the authoritative entitlement from the server when available.
  Future<void> refresh();

  Future<Result<Entitlement>> purchase(PlanPeriod period);
  Future<Result<Entitlement>> restore();
  Future<void> resetToFree();
}
