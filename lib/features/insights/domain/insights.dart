import '../../../core/domain/money.dart';
import '../../receipts/domain/entities/receipt.dart';
import '../../receipts/domain/services/protection_rules.dart';

class MonthTotal {
  const MonthTotal(this.month, this.total);
  final DateTime month;
  final Money total;
}

class Insights {
  const Insights({
    required this.currency,
    required this.totalSpent,
    required this.byCategory,
    required this.monthly,
    required this.protectedValue,
    required this.receiptCount,
    required this.activeWarranties,
    required this.expiringSoon,
    required this.otherCurrencyCount,
  });

  final String currency;
  final Money totalSpent;
  final Map<Category, Money> byCategory;
  final List<MonthTotal> monthly;
  final Money protectedValue;
  final int receiptCount;
  final int activeWarranties;
  final int expiringSoon;

  /// Receipts in other currencies, excluded from totals.
  final int otherCurrencyCount;

  bool get isEmpty => receiptCount == 0;
}

/// Pure computation over confirmed receipts (BR-04).
class ComputeInsights {
  const ComputeInsights._();

  static Insights compute(
    List<Receipt> receipts, {
    required String currency,
    required int months,
    required DateTime now,
  }) {
    final from = DateTime(now.year, now.month - months + 1);
    final confirmed = receipts.where((r) => r.status.isConfirmed && !r.isDeleted);
    var other = 0;
    var total = Money.zero(currency);
    var protectedValue = Money.zero(currency);
    final byCategory = <Category, Money>{};
    final monthly = {for (var i = 0; i < months; i++) DateTime(from.year, from.month + i): Money.zero(currency)};
    var active = 0;
    var soon = 0;

    for (final r in confirmed) {
      for (final item in r.items) {
        switch (r.warrantyStatusFor(item, now)) {
          case WarrantyStatus.active:
            active++;
          case WarrantyStatus.expiringSoon:
            active++;
            soon++;
          case WarrantyStatus.expired:
          case WarrantyStatus.none:
            break;
        }
      }
      if (r.total.currency != currency) {
        other++;
        continue;
      }
      protectedValue = protectedValue + r.protectedValue(now);
      if (r.purchaseDate.isBefore(from)) continue;
      total = total + r.total;
      byCategory[r.category] = (byCategory[r.category] ?? Money.zero(currency)) + r.total;
      final key = DateTime(r.purchaseDate.year, r.purchaseDate.month);
      if (monthly.containsKey(key)) monthly[key] = monthly[key]! + r.total;
    }

    final sortedCategories = Map.fromEntries(
      byCategory.entries.toList()..sort((a, b) => b.value.minor.compareTo(a.value.minor)),
    );
    return Insights(
      currency: currency,
      totalSpent: total,
      byCategory: sortedCategories,
      monthly: [for (final e in monthly.entries) MonthTotal(e.key, e.value)],
      protectedValue: protectedValue,
      receiptCount: confirmed.length,
      activeWarranties: active,
      expiringSoon: soon,
      otherCurrencyCount: other,
    );
  }
}

/// FR-INS-03 / FR-SET-03.
class ReceiptsCsv {
  const ReceiptsCsv._();

  static String build(List<Receipt> receipts) {
    final rows = <List<String>>[
      [
        'Merchant',
        'Purchase date',
        'Total',
        'Currency',
        'Category',
        'Items',
        'Warranty ends',
        'Return deadline',
        'Notes',
      ],
    ];
    for (final r in receipts.where((r) => !r.isDeleted)) {
      rows.add([
        r.merchant,
        _date(r.purchaseDate),
        r.total.major.toStringAsFixed(2),
        r.total.currency,
        r.category.label,
        r.items.map((i) => '${i.quantity}x ${i.name}').join('; '),
        r.latestWarrantyEnd == null ? '' : _date(r.latestWarrantyEnd!),
        r.returnDeadline == null ? '' : _date(r.returnDeadline!),
        r.notes ?? '',
      ]);
    }
    return rows.map((row) => row.map(_escape).join(',')).join('\n');
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _escape(String v) => v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
}
