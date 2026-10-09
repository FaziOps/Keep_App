import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/clock.dart';
import '../../../core/failures.dart';
import '../../../core/result.dart';
import '../../../core/storage/local_store.dart';
import '../domain/entities/entitlement.dart';
import '../domain/repositories/entitlement_repository.dart';

/// Port to the store billing SDK.
abstract interface class BillingGateway {
  Future<DateTime> purchase(PlanPeriod period);
  Future<DateTime?> restore();
}

/// Development gateway that grants Premium without a real payment. Swap it
/// for a RevenueCat-backed gateway before releasing to the stores.
class DemoBillingGateway implements BillingGateway {
  const DemoBillingGateway(this._clock);
  final Clock _clock;

  @override
  Future<DateTime> purchase(PlanPeriod period) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final now = _clock();
    return period == PlanPeriod.monthly
        ? DateTime(now.year, now.month + 1, now.day)
        : DateTime(now.year + 1, now.month, now.day);
  }

  @override
  Future<DateTime?> restore() async => null;
}

class EntitlementRepositoryImpl implements EntitlementRepository {
  EntitlementRepositoryImpl({
    required LocalStore store,
    required BillingGateway billing,
    required Clock clock,
    SupabaseClient? client,
  }) : _store = store,
       _billing = billing,
       _clock = clock,
       _client = client;

  final LocalStore _store;
  final BillingGateway _billing;
  final Clock _clock;
  final SupabaseClient? _client;

  static const _key = 'entitlement';

  Entitlement _read() {
    final raw = _store.meta.get(_key);
    final now = _clock();
    if (raw == null) return Entitlement.free(now);
    final j = LocalStore.decode(raw);
    return Entitlement(
      tier: PlanTier.values.byName(j['tier'] as String),
      scansUsed: (j['scans_used'] as num).toInt(),
      claimPacksUsed: (j['claim_packs_used'] as num).toInt(),
      periodStart: DateTime.parse(j['period_start'] as String),
      expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
    ).rolledOver(now);
  }

  Future<void> _write(Entitlement e) => _store.meta.put(
    _key,
    LocalStore.encode({
      'tier': e.tier.name,
      'scans_used': e.scansUsed,
      'claim_packs_used': e.claimPacksUsed,
      'period_start': e.periodStart.toIso8601String(),
      'expires_at': e.expiresAt?.toIso8601String(),
    }),
  );

  @override
  Stream<Entitlement> watch() => watchBox(_store.meta, _read);

  @override
  Future<Entitlement> current() async => _read();

  @override
  Future<void> recordUsage(QuotaKind kind) => _write(_read().consumed(kind));

  @override
  Future<void> refresh() async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;
    try {
      final row = await client.from('entitlements').select().eq('user_id', userId).maybeSingle();
      if (row == null) return;
      final local = _read();
      final server = Entitlement(
        tier: PlanTier.values.byName(row['tier'] as String),
        scansUsed: (row['scans_used'] as num).toInt(),
        claimPacksUsed: (row['claim_packs_used'] as num).toInt(),
        periodStart: DateTime.parse(row['period_start'] as String),
        expiresAt: row['expires_at'] == null ? null : DateTime.parse(row['expires_at'] as String),
      ).rolledOver(_clock());
      // The server counts AI scans; claim packs are generated on device.
      await _write(
        server.copyWith(
          tier: local.isPremium ? PlanTier.premium : server.tier,
          expiresAt: local.isPremium ? local.expiresAt : server.expiresAt,
          claimPacksUsed: local.claimPacksUsed > server.claimPacksUsed ? local.claimPacksUsed : server.claimPacksUsed,
        ),
      );
    } catch (_) {
      // Offline: keep the cached entitlement.
    }
  }

  @override
  Future<Result<Entitlement>> purchase(PlanPeriod period) async {
    try {
      final expiresAt = await _billing.purchase(period);
      final updated = _read().copyWith(tier: PlanTier.premium, expiresAt: expiresAt);
      await _write(updated);
      return Success(updated);
    } catch (_) {
      return const Failure(UnexpectedFailure('The purchase did not complete.'));
    }
  }

  @override
  Future<Result<Entitlement>> restore() async {
    final expiresAt = await _billing.restore();
    if (expiresAt == null) {
      return const Failure(NotFoundFailure('No previous purchase found for this account.'));
    }
    final updated = _read().copyWith(tier: PlanTier.premium, expiresAt: expiresAt);
    await _write(updated);
    return Success(updated);
  }

  @override
  Future<void> resetToFree() async {
    await _store.meta.delete(_key);
  }
}
