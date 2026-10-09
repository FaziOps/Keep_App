import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/result.dart';
import '../../../protection/domain/entities/reminder.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/protection_rules.dart';

class WarrantyRowVm {
  const WarrantyRowVm({
    required this.item,
    required this.end,
    required this.status,
    required this.daysLeft,
    required this.elapsed,
  });
  final LineItem item;
  final DateTime end;
  final WarrantyStatus status;
  final int daysLeft;

  /// 0..1 portion of the warranty period already used.
  final double elapsed;
}

sealed class ReceiptDetailUiState {
  const ReceiptDetailUiState();
}

final class DetailLoading extends ReceiptDetailUiState {
  const DetailLoading();
}

final class DetailNotFound extends ReceiptDetailUiState {
  const DetailNotFound();
}

final class DetailData extends ReceiptDetailUiState {
  const DetailData({
    required this.receipt,
    required this.warranties,
    required this.reminders,
    required this.canEdit,
    required this.now,
  });
  final Receipt receipt;
  final List<WarrantyRowVm> warranties;
  final List<Reminder> reminders;
  final bool canEdit;
  final DateTime now;

  DateTime? get returnDeadline => receipt.returnDeadline;
  bool get returnOpen => receipt.isReturnOpen(now);
  int? get returnDaysLeft => returnDeadline == null ? null : ProtectionRules.daysLeft(returnDeadline!, now);
}

final _receiptStreamProvider = StreamProvider.autoDispose.family<Receipt?, String>(
  (ref, id) => ref.watch(receiptRepositoryProvider).watchReceipt(id),
);
final _receiptRemindersProvider = StreamProvider.autoDispose.family<List<Reminder>, String>(
  (ref, id) => ref.watch(reminderRepositoryProvider).watchForReceipt(id),
);

/// Presenter for the receipt detail screen.
class ReceiptDetailPresenter extends Notifier<ReceiptDetailUiState> {
  ReceiptDetailPresenter(this.receiptId);
  final String receiptId;

  @override
  ReceiptDetailUiState build() {
    final receiptAsync = ref.watch(_receiptStreamProvider(receiptId));
    final reminders = ref.watch(_receiptRemindersProvider(receiptId)).value ?? const [];
    final canEdit = ref.watch(activeHouseholdProvider).value?.role.canEdit ?? false;
    if (!receiptAsync.hasValue) return const DetailLoading();
    final receipt = receiptAsync.value;
    if (receipt == null || receipt.isDeleted) return const DetailNotFound();

    final now = ref.read(clockProvider)();
    final warranties = <WarrantyRowVm>[];
    for (final item in receipt.items) {
      final end = receipt.warrantyEndFor(item);
      if (end == null) continue;
      final total = end.difference(receipt.purchaseDate).inDays;
      final used = now.difference(receipt.purchaseDate).inDays;
      warranties.add(
        WarrantyRowVm(
          item: item,
          end: end,
          status: receipt.warrantyStatusFor(item, now),
          daysLeft: ProtectionRules.daysLeft(end, now),
          elapsed: total <= 0 ? 1 : (used / total).clamp(0, 1).toDouble(),
        ),
      );
    }
    return DetailData(
      receipt: receipt,
      warranties: warranties,
      reminders: reminders.where((r) => r.state == ReminderState.scheduled && r.fireAt.isAfter(now)).toList(),
      canEdit: canEdit,
      now: now,
    );
  }

  Future<String?> delete() async {
    final result = await ref.read(deleteReceiptProvider)(receiptId);
    return result.failureOrNull?.message;
  }

  Future<String?> setArchived(bool archived) async {
    final current = state;
    if (current is! DetailData) return null;
    final result = await ref.read(archiveReceiptProvider)(current.receipt, archived: archived);
    return result is Failure ? result.failureOrNull!.message : null;
  }

  Future<void> dismissReminder(String reminderId) async {
    await ref.read(reminderSchedulerProvider).cancel(reminderId);
    await ref.read(reminderRepositoryProvider).dismiss(reminderId);
  }
}

final receiptDetailPresenterProvider = NotifierProvider.autoDispose
    .family<ReceiptDetailPresenter, ReceiptDetailUiState, String>(ReceiptDetailPresenter.new);
