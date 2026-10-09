import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/failures.dart';
import '../../../../core/utils/format.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/protection_rules.dart';

enum StatusFilter { all, protected, expiringSoon, returnOpen, drafts }

class VaultFilter {
  const VaultFilter({this.query = '', this.category, this.status = StatusFilter.all});
  final String query;
  final Category? category;
  final StatusFilter status;

  bool get isActive => query.isNotEmpty || category != null || status != StatusFilter.all;

  VaultFilter copyWith({String? query, Category? category, bool clearCategory = false, StatusFilter? status}) =>
      VaultFilter(
        query: query ?? this.query,
        category: clearCategory ? null : category ?? this.category,
        status: status ?? this.status,
      );
}

/// View model for one row in the vault list.
class ReceiptCardVm {
  const ReceiptCardVm({
    required this.id,
    required this.merchant,
    required this.subtitle,
    required this.totalLabel,
    required this.category,
    required this.warrantyStatus,
    required this.receiptStatus,
    required this.syncState,
    required this.cover,
    this.deadlineLabel,
  });

  final String id;
  final String merchant;
  final String subtitle;
  final String totalLabel;
  final Category category;
  final WarrantyStatus warrantyStatus;
  final ReceiptStatus receiptStatus;
  final SyncState syncState;
  final Attachment? cover;
  final String? deadlineLabel;
}

class VaultSummary {
  const VaultSummary({
    required this.receiptCount,
    required this.protectedValue,
    required this.expiringSoon,
    required this.openReturns,
  });
  final int receiptCount;
  final String protectedValue;
  final int expiringSoon;
  final int openReturns;
}

sealed class VaultUiState {
  const VaultUiState();
}

final class VaultLoading extends VaultUiState {
  const VaultLoading();
}

final class VaultError extends VaultUiState {
  const VaultError(this.message);
  final String message;
}

final class VaultEmpty extends VaultUiState {
  const VaultEmpty(this.greetingName, {required this.isLocal});
  final String greetingName;
  final bool isLocal;
}

final class VaultData extends VaultUiState {
  const VaultData({
    required this.greetingName,
    required this.householdName,
    required this.cards,
    required this.filter,
    required this.summary,
  });
  final String greetingName;
  final String householdName;
  final List<ReceiptCardVm> cards;
  final VaultFilter filter;
  final VaultSummary summary;
}

class VaultFilterNotifier extends Notifier<VaultFilter> {
  @override
  VaultFilter build() => const VaultFilter();
  void update(VaultFilter filter) => state = filter;
}

final vaultFilterProvider = NotifierProvider<VaultFilterNotifier, VaultFilter>(VaultFilterNotifier.new);

/// Presenter for the Vault screen (FR-VLT-01..03).
class VaultPresenter extends Notifier<VaultUiState> {
  @override
  VaultUiState build() {
    final receiptsAsync = ref.watch(householdReceiptsProvider);
    final household = ref.watch(activeHouseholdProvider);
    final user = ref.watch(currentUserProvider).value;
    final filter = ref.watch(vaultFilterProvider);
    final currency = ref.watch(settingsProvider.select((s) => s.value?.currency ?? 'PKR'));
    final now = ref.read(clockProvider)();
    final firstName = (user?.displayName ?? '').split(' ').first;

    if (household.hasError) {
      final e = household.error;
      return VaultError(e is AppFailure ? e.message : 'Could not open your vault.');
    }
    final receipts = receiptsAsync.value;
    if (receipts == null) return const VaultLoading();
    if (receipts.isEmpty) return VaultEmpty(firstName, isLocal: user?.isLocal ?? true);

    return VaultData(
      greetingName: firstName,
      householdName: household.value?.name ?? 'My vault',
      cards: [for (final r in receipts.where((r) => _matches(r, filter, now))) _toCard(r, now)],
      filter: filter,
      summary: _summary(receipts, currency, now),
    );
  }

  void search(String query) =>
      ref.read(vaultFilterProvider.notifier).update(ref.read(vaultFilterProvider).copyWith(query: query));

  void selectCategory(Category? category) => ref
      .read(vaultFilterProvider.notifier)
      .update(ref.read(vaultFilterProvider).copyWith(category: category, clearCategory: category == null));

  void selectStatus(StatusFilter status) =>
      ref.read(vaultFilterProvider.notifier).update(ref.read(vaultFilterProvider).copyWith(status: status));

  void clearFilters() => ref.read(vaultFilterProvider.notifier).update(const VaultFilter());

  void retry() => ref.invalidate(activeHouseholdProvider);

  /// Fills an empty vault with sample data so new users can explore.
  Future<void> loadSampleReceipts() async {
    final household = ref.read(activeHouseholdProvider).value;
    final user = ref.read(currentUserProvider).value;
    if (household == null || user == null) return;
    final scheduler = ref.read(reminderSchedulerProvider);
    if (scheduler.isSupported) await scheduler.requestPermission();
    await ref.read(seedDemoReceiptsProvider)(
      householdId: household.id,
      userId: user.id,
      currency: ref.read(settingsRepositoryProvider).current.currency,
    );
  }

  static bool _matches(Receipt r, VaultFilter f, DateTime now) {
    if (f.category != null && r.category != f.category) return false;
    final ok = switch (f.status) {
      StatusFilter.all => true,
      StatusFilter.protected =>
        r.overallWarrantyStatus(now) == WarrantyStatus.active ||
            r.overallWarrantyStatus(now) == WarrantyStatus.expiringSoon,
      StatusFilter.expiringSoon => r.overallWarrantyStatus(now) == WarrantyStatus.expiringSoon,
      StatusFilter.returnOpen => r.isReturnOpen(now),
      StatusFilter.drafts => r.status.isDraft,
    };
    if (!ok) return false;
    final q = f.query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final amount = parseMoneyInput(q);
    return r.merchant.toLowerCase().contains(q) ||
        (r.notes?.toLowerCase().contains(q) ?? false) ||
        r.category.label.toLowerCase().contains(q) ||
        r.items.any((i) => i.name.toLowerCase().contains(q) || (i.serialNumber?.toLowerCase().contains(q) ?? false)) ||
        (amount != null && amount > 0 && r.total.minor == amount);
  }

  static ReceiptCardVm _toCard(Receipt r, DateTime now) {
    final itemCount = r.items.length;
    final deadline = r.returnDeadline;
    String? deadlineLabel;
    if (deadline != null && r.isReturnOpen(now)) {
      deadlineLabel = 'Return ${relativeDays(ProtectionRules.daysLeft(deadline, now))}';
    } else if (r.overallWarrantyStatus(now) == WarrantyStatus.expiringSoon && r.latestWarrantyEnd != null) {
      deadlineLabel = 'Warranty ends ${relativeDays(ProtectionRules.daysLeft(r.latestWarrantyEnd!, now))}';
    }
    return ReceiptCardVm(
      id: r.id,
      merchant: r.merchant.isEmpty ? 'Untitled receipt' : r.merchant,
      subtitle: [
        formatDate(r.purchaseDate),
        if (itemCount > 0) '$itemCount item${itemCount == 1 ? '' : 's'}',
      ].join(' · '),
      totalLabel: formatMoney(r.total),
      category: r.category,
      warrantyStatus: r.overallWarrantyStatus(now),
      receiptStatus: r.status,
      syncState: r.syncState,
      cover: r.coverImage,
      deadlineLabel: deadlineLabel,
    );
  }

  static VaultSummary _summary(List<Receipt> receipts, String currency, DateTime now) {
    var protectedValue = Money.zero(currency);
    var soon = 0, returns = 0;
    for (final r in receipts.where((r) => r.status.isConfirmed)) {
      if (r.total.currency == currency) protectedValue = protectedValue + r.protectedValue(now);
      if (r.overallWarrantyStatus(now) == WarrantyStatus.expiringSoon) soon++;
      if (r.isReturnOpen(now)) returns++;
    }
    return VaultSummary(
      receiptCount: receipts.length,
      protectedValue: formatMoney(protectedValue, compact: true),
      expiringSoon: soon,
      openReturns: returns,
    );
  }
}

final vaultPresenterProvider = NotifierProvider<VaultPresenter, VaultUiState>(VaultPresenter.new);
