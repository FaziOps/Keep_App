import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../domain/entities/receipt.dart';
import 'widgets/receipt_visuals.dart';

/// Presenter for Recently deleted (FR-VLT-06).
class TrashPresenter extends Notifier<AsyncValue<List<Receipt>>> {
  @override
  AsyncValue<List<Receipt>> build() {
    final household = ref.watch(activeHouseholdProvider).value;
    if (household == null) return const AsyncLoading();
    return ref.watch(_trashProvider(household.id));
  }

  Future<String?> restore(String id) async =>
      (await ref.read(receiptRepositoryProvider).restore(id)).fold((f) => f.message, (r) {
        ref.read(scheduleRemindersProvider)(r);
        return null;
      });
}

final _trashProvider = StreamProvider.autoDispose.family<List<Receipt>, String>(
  (ref, householdId) => ref.watch(receiptRepositoryProvider).watchTrash(householdId),
);
final trashPresenterProvider = NotifierProvider.autoDispose<TrashPresenter, AsyncValue<List<Receipt>>>(
  TrashPresenter.new,
);

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trashPresenterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recently deleted')),
      body: switch (state) {
        AsyncData(:final value) when value.isEmpty => const EmptyState(
          icon: Icons.delete_outline_rounded,
          title: 'Nothing here',
          message: 'Deleted receipts stay here for 30 days before they are removed for good.',
        ),
        AsyncData(:final value) => ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = value[i];
            final daysLeft = 30 - DateTime.now().difference(r.deletedAt!).inDays;
            return SurfaceCard(
              child: Row(
                children: [
                  CategoryAvatar(r.category),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.merchant, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${formatMoney(r.total)} · removed in $daysLeft days',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final error = await ref.read(trashPresenterProvider.notifier).restore(r.id);
                      if (context.mounted) showMessage(context, error ?? 'Restored', error: error != null);
                    },
                    child: const Text('Restore'),
                  ),
                ],
              ),
            );
          },
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
