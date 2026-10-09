import 'dart:math' as math;

import '../../../../core/domain/clock.dart';
import '../../../../core/domain/money.dart';
import '../entities/receipt.dart';

enum WarrantyStatus { none, active, expiringSoon, expired }

/// Pure business rules for return windows and warranties.
class ProtectionRules {
  const ProtectionRules._();

  /// BR-12 threshold.
  static const expiringSoonDays = 30;

  /// BR-01: calendar months; clamp to the last day when the day is missing.
  static DateTime addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + (monthIndex ~/ 12);
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, math.min(date.day, lastDay));
  }

  static DateTime? warrantyEnd(DateTime purchaseDate, Warranty? warranty) {
    if (warranty == null || warranty.months <= 0) return null;
    return addMonths(dateOnly(purchaseDate), warranty.months);
  }

  /// BR-02: end of day, purchase date + return window days.
  static DateTime? returnDeadline(DateTime purchaseDate, int? returnDays) {
    if (returnDays == null || returnDays <= 0) return null;
    return DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day + returnDays, 23, 59, 59);
  }

  static int daysLeft(DateTime deadline, DateTime now) => dateOnly(deadline).difference(dateOnly(now)).inDays;

  /// BR-12.
  static WarrantyStatus statusFor(DateTime? end, DateTime now) {
    if (end == null) return WarrantyStatus.none;
    final left = daysLeft(end, now);
    if (left < 0) return WarrantyStatus.expired;
    if (left <= expiringSoonDays) return WarrantyStatus.expiringSoon;
    return WarrantyStatus.active;
  }
}

/// Convenience read-model helpers on the aggregate.
extension ReceiptProtection on Receipt {
  DateTime? get returnDeadline => ProtectionRules.returnDeadline(purchaseDate, returnDays);

  bool isReturnOpen(DateTime now) {
    final d = returnDeadline;
    return d != null && !d.isBefore(now);
  }

  DateTime? warrantyEndFor(LineItem item) => ProtectionRules.warrantyEnd(purchaseDate, item.warranty);

  WarrantyStatus warrantyStatusFor(LineItem item, DateTime now) => ProtectionRules.statusFor(warrantyEndFor(item), now);

  /// The most relevant status across items, used for list badges.
  WarrantyStatus overallWarrantyStatus(DateTime now) {
    final statuses = items.map((i) => warrantyStatusFor(i, now)).toSet();
    for (final s in const [WarrantyStatus.expiringSoon, WarrantyStatus.active, WarrantyStatus.expired]) {
      if (statuses.contains(s)) return s;
    }
    return WarrantyStatus.none;
  }

  /// Latest warranty end across items still relevant to the user.
  DateTime? get latestWarrantyEnd {
    DateTime? latest;
    for (final item in items) {
      final end = warrantyEndFor(item);
      if (end != null && (latest == null || end.isAfter(latest))) latest = end;
    }
    return latest;
  }

  /// Value of items whose warranty is still running.
  Money protectedValue(DateTime now) {
    var sum = Money.zero(total.currency);
    for (final item in items) {
      final s = warrantyStatusFor(item, now);
      if ((s == WarrantyStatus.active || s == WarrantyStatus.expiringSoon) &&
          item.unitPrice.currency == total.currency) {
        sum = sum + item.total;
      }
    }
    return sum;
  }
}
