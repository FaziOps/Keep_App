import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/common.dart';
import '../../receipts/presentation/widgets/receipt_visuals.dart';
import 'protection_presenter.dart';

class ProtectionScreen extends ConsumerWidget {
  const ProtectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(protectionPresenterProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Protection')),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.isEmpty
          ? const EmptyState(
              icon: Icons.shield_outlined,
              title: 'Nothing to watch yet',
              message: 'Add return windows and warranties to your receipts and Keepr will keep an eye on them.',
            )
          : ContentWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                children: [
                  Row(
                    children: [
                      _CountTile(
                        value: state.returns.length,
                        label: 'Returnable',
                        color: KeeprColors.amber,
                        icon: Icons.assignment_return_rounded,
                      ),
                      const SizedBox(width: 10),
                      _CountTile(
                        value: state.expiring.length,
                        label: 'Expiring soon',
                        color: KeeprColors.danger,
                        icon: Icons.timelapse_rounded,
                      ),
                      const SizedBox(width: 10),
                      _CountTile(
                        value: state.active.length + state.expiring.length,
                        label: 'Protected',
                        color: KeeprColors.success,
                        icon: Icons.verified_user_rounded,
                      ),
                    ],
                  ),
                  if (!state.notificationsSupported)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Pill(
                        label: 'Push reminders work in the Android and iOS apps',
                        color: KeeprColors.sky,
                        icon: Icons.info_outline_rounded,
                      ),
                    ),
                  if (state.returns.isNotEmpty) ...[
                    const SectionHeader('Return windows closing'),
                    for (final d in state.returns) _DeadlineTile(vm: d, verb: 'Return'),
                  ],
                  if (state.expiring.isNotEmpty) ...[
                    const SectionHeader('Warranties expiring soon'),
                    for (final d in state.expiring) _DeadlineTile(vm: d, verb: 'Ends'),
                  ],
                  if (state.reminders.isNotEmpty) ...[
                    const SectionHeader('Upcoming reminders'),
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, r) in state.reminders.indexed) ...[
                            if (i > 0) const Divider(indent: 56),
                            ListTile(
                              leading: const Icon(Icons.notifications_active_rounded),
                              title: Text(r.reminder.title, style: text.titleSmall),
                              subtitle: Text('${r.merchant} · ${formatDateTime(r.reminder.fireAt)}'),
                              onTap: () => context.push('/receipt/${r.reminder.receiptId}'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (state.active.isNotEmpty) ...[
                    const SectionHeader('Under warranty'),
                    for (final d in state.active) _DeadlineTile(vm: d, verb: 'Until'),
                  ],
                  if (state.recentlyExpired.isNotEmpty) ...[
                    const SectionHeader('Recently expired'),
                    for (final d in state.recentlyExpired) _DeadlineTile(vm: d, verb: 'Ended', muted: true),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.value, required this.label, required this.color, required this.icon});
  final int value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({required this.vm, required this.verb, this.muted = false});
  final DeadlineVm vm;
  final String verb;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final urgent = vm.daysLeft <= 7 && !muted;
    final color = muted
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : urgent
        ? KeeprColors.danger
        : KeeprColors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        onTap: () => context.push('/receipt/${vm.receiptId}'),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CategoryAvatar(vm.category, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    vm.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  muted ? formatShortDate(vm.deadline) : relativeDays(vm.daysLeft),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
                ),
                Text('$verb ${formatShortDate(vm.deadline)}', style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
