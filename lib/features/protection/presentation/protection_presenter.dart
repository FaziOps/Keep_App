import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../receipts/domain/entities/receipt.dart';
import '../../receipts/domain/services/protection_rules.dart';
import '../domain/entities/reminder.dart';

class DeadlineVm {
  const DeadlineVm({
    required this.receiptId,
    required this.title,
    required this.subtitle,
    required this.deadline,
    required this.daysLeft,
    required this.category,
  });
  final String receiptId;
  final String title;
  final String subtitle;
  final DateTime deadline;
  final int daysLeft;
  final Category category;
}

class UpcomingReminderVm {
  const UpcomingReminderVm(this.reminder, this.merchant);
  final Reminder reminder;
  final String merchant;
}

class ProtectionUiState {
  const ProtectionUiState({
    required this.loading,
    this.returns = const [],
    this.expiring = const [],
    this.active = const [],
    this.recentlyExpired = const [],
    this.reminders = const [],
    this.notificationsSupported = true,
  });

  final bool loading;
  final List<DeadlineVm> returns;
  final List<DeadlineVm> expiring;
  final List<DeadlineVm> active;
  final List<DeadlineVm> recentlyExpired;
  final List<UpcomingReminderVm> reminders;
  final bool notificationsSupported;

  bool get isEmpty => returns.isEmpty && expiring.isEmpty && active.isEmpty && recentlyExpired.isEmpty;
}

/// Presenter for the Protection dashboard (FR-WAR-04, FR-REM-06).
class ProtectionPresenter extends Notifier<ProtectionUiState> {
  @override
  ProtectionUiState build() {
    final receipts = ref.watch(householdReceiptsProvider).value;
    final reminders = ref.watch(allRemindersProvider).value ?? const [];
    if (receipts == null) return const ProtectionUiState(loading: true);
    final now = ref.read(clockProvider)();

    final returns = <DeadlineVm>[];
    final expiring = <DeadlineVm>[];
    final active = <DeadlineVm>[];
    final expired = <DeadlineVm>[];
    final byId = {for (final r in receipts) r.id: r};

    for (final r in receipts.where((r) => r.status.isConfirmed)) {
      final deadline = r.returnDeadline;
      if (deadline != null && r.isReturnOpen(now)) {
        returns.add(
          DeadlineVm(
            receiptId: r.id,
            title: r.merchant,
            subtitle: r.items.isEmpty ? r.category.label : r.items.map((i) => i.name).join(', '),
            deadline: deadline,
            daysLeft: ProtectionRules.daysLeft(deadline, now),
            category: r.category,
          ),
        );
      }
      for (final item in r.items) {
        final end = r.warrantyEndFor(item);
        if (end == null) continue;
        final vm = DeadlineVm(
          receiptId: r.id,
          title: item.name,
          subtitle: r.merchant,
          deadline: end,
          daysLeft: ProtectionRules.daysLeft(end, now),
          category: r.category,
        );
        switch (r.warrantyStatusFor(item, now)) {
          case WarrantyStatus.expiringSoon:
            expiring.add(vm);
          case WarrantyStatus.active:
            active.add(vm);
          case WarrantyStatus.expired when vm.daysLeft > -90:
            expired.add(vm);
          default:
            break;
        }
      }
    }
    int byDeadline(DeadlineVm a, DeadlineVm b) => a.deadline.compareTo(b.deadline);

    return ProtectionUiState(
      loading: false,
      returns: returns..sort(byDeadline),
      expiring: expiring..sort(byDeadline),
      active: active..sort(byDeadline),
      recentlyExpired: expired..sort((a, b) => b.deadline.compareTo(a.deadline)),
      reminders: [
        for (final r in reminders)
          if (r.state == ReminderState.scheduled && r.fireAt.isAfter(now) && byId.containsKey(r.receiptId))
            UpcomingReminderVm(r, byId[r.receiptId]!.merchant),
      ].take(10).toList(),
      notificationsSupported: ref.read(reminderSchedulerProvider).isSupported,
    );
  }
}

final protectionPresenterProvider = NotifierProvider<ProtectionPresenter, ProtectionUiState>(ProtectionPresenter.new);
