import 'dart:math' as math;

import '../../../../core/failures.dart';

enum PlanTier { free, premium }

enum PlanPeriod { monthly, yearly }

/// BR-07.
class PlanLimits {
  const PlanLimits._();
  static const freeScansPerMonth = 15;
  static const freeClaimPacksPerMonth = 3;
  static const freeHouseholdMembers = 2;
  static const premiumHouseholdMembers = 6;
}

class Entitlement {
  const Entitlement({
    required this.tier,
    required this.scansUsed,
    required this.claimPacksUsed,
    required this.periodStart,
    this.expiresAt,
  });

  factory Entitlement.free(DateTime now) =>
      Entitlement(tier: PlanTier.free, scansUsed: 0, claimPacksUsed: 0, periodStart: DateTime(now.year, now.month));

  final PlanTier tier;
  final int scansUsed;
  final int claimPacksUsed;

  /// First day of the current quota month.
  final DateTime periodStart;
  final DateTime? expiresAt;

  bool get isPremium => tier == PlanTier.premium;

  int? get scansLeft => isPremium ? null : math.max(0, PlanLimits.freeScansPerMonth - scansUsed);

  int? get claimPacksLeft => isPremium ? null : math.max(0, PlanLimits.freeClaimPacksPerMonth - claimPacksUsed);

  int get maxHouseholdMembers => isPremium ? PlanLimits.premiumHouseholdMembers : PlanLimits.freeHouseholdMembers;

  bool allows(QuotaKind kind) => switch (kind) {
    QuotaKind.aiScan => isPremium || scansLeft! > 0,
    QuotaKind.claimPack => isPremium || claimPacksLeft! > 0,
    QuotaKind.householdMember => true,
  };

  /// Counters reset on the first day of each month.
  Entitlement rolledOver(DateTime now) {
    final month = DateTime(now.year, now.month);
    var current = this;
    if (isPremium && expiresAt != null && expiresAt!.isBefore(now)) {
      current = current.copyWith(tier: PlanTier.free);
    }
    if (month.isAfter(periodStart)) {
      current = current.copyWith(scansUsed: 0, claimPacksUsed: 0, periodStart: month);
    }
    return current;
  }

  Entitlement consumed(QuotaKind kind) => switch (kind) {
    QuotaKind.aiScan => copyWith(scansUsed: scansUsed + 1),
    QuotaKind.claimPack => copyWith(claimPacksUsed: claimPacksUsed + 1),
    QuotaKind.householdMember => this,
  };

  Entitlement copyWith({
    PlanTier? tier,
    int? scansUsed,
    int? claimPacksUsed,
    DateTime? periodStart,
    DateTime? expiresAt,
  }) => Entitlement(
    tier: tier ?? this.tier,
    scansUsed: scansUsed ?? this.scansUsed,
    claimPacksUsed: claimPacksUsed ?? this.claimPacksUsed,
    periodStart: periodStart ?? this.periodStart,
    expiresAt: expiresAt ?? this.expiresAt,
  );
}
