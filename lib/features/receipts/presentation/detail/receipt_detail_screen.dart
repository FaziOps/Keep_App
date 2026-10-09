import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/common.dart';
import '../../../protection/domain/entities/reminder.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/services/protection_rules.dart';
import '../widgets/receipt_visuals.dart';
import 'receipt_detail_presenter.dart';

class ReceiptDetailScreen extends ConsumerWidget {
  const ReceiptDetailScreen({super.key, required this.receiptId});
  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiptDetailPresenterProvider(receiptId));
    return switch (state) {
      DetailLoading() => const Scaffold(body: Center(child: CircularProgressIndicator())),
      DetailNotFound() => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Receipt not found',
          message: 'It may have been deleted on another device.',
          action: FilledButton(onPressed: () => context.go('/vault'), child: const Text('Back to vault')),
        ),
      ),
      DetailData() => _Detail(data: state),
    };
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.data});
  final DetailData data;

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String action) async {
    final presenter = ref.read(receiptDetailPresenterProvider(data.receipt.id).notifier);
    switch (action) {
      case 'archive':
      case 'unarchive':
        final error = await presenter.setArchived(action == 'archive');
        if (context.mounted) {
          showMessage(context, error ?? (action == 'archive' ? 'Archived' : 'Restored'), error: error != null);
        }
      case 'delete':
        final ok = await confirmDialog(
          context,
          title: 'Delete this receipt?',
          message: 'It moves to Recently deleted for 30 days and its reminders are cancelled.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        final error = await presenter.delete();
        if (!context.mounted) return;
        if (error != null) {
          showMessage(context, error, error: true);
        } else {
          showMessage(context, 'Moved to Recently deleted');
          context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = data.receipt;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hasImage = r.attachments.isNotEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: hasImage ? 300 : 180,
            backgroundColor: KeeprColors.brandDeep,
            foregroundColor: Colors.white,
            actions: [
              if (data.canEdit)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => context.push('/receipt/${r.id}/edit'),
                  icon: const Icon(Icons.edit_rounded),
                ),
              if (data.canEdit)
                PopupMenuButton<String>(
                  onSelected: (a) => _onMenu(context, ref, a),
                  itemBuilder: (_) => [
                    if (r.status == ReceiptStatus.archived)
                      const PopupMenuItem(value: 'unarchive', child: Text('Restore from archive'))
                    else
                      const PopupMenuItem(value: 'archive', child: Text('Archive')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: hasImage
                  ? _ImageCarousel(receipt: r)
                  : Container(
                      decoration: const BoxDecoration(gradient: KeeprColors.heroGradient),
                      alignment: Alignment.center,
                      child: Hero(tag: 'receipt-${r.id}', child: CategoryAvatar(r.category, size: 72)),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.merchant.isEmpty ? 'Untitled receipt' : r.merchant, style: text.headlineSmall),
                              const SizedBox(height: 4),
                              Text(
                                '${formatDate(r.purchaseDate)} · ${r.category.label}',
                                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Text(formatMoney(r.total), style: text.headlineSmall?.copyWith(color: scheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ReceiptStatusBadge(status: r.status, syncState: r.syncState),
                        WarrantyBadge(r.overallWarrantyStatus(data.now), dense: false),
                        if (r.syncState == SyncState.synced)
                          const Pill(label: 'Backed up', color: KeeprColors.sky, icon: Icons.cloud_done_rounded),
                      ],
                    ),
                    if (r.status.isDraft && data.canEdit) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => context.push('/receipt/${r.id}/edit'),
                        icon: const Icon(Icons.rate_review_rounded),
                        label: const Text('Review and confirm'),
                      ),
                    ],
                    const SectionHeader('Protection'),
                    _ProtectionCard(data: data),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/receipt/${r.id}/claim'),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Create claim pack'),
                    ),
                    if (r.items.isNotEmpty) ...[
                      const SectionHeader('Items'),
                      SurfaceCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (final (i, item) in r.items.indexed) ...[
                              if (i > 0) const Divider(indent: 16, endIndent: 16),
                              ListTile(
                                title: Text(item.name, style: text.titleSmall),
                                subtitle: Text(
                                  [
                                    '${item.quantity} × ${formatMoney(item.unitPrice)}',
                                    if (item.serialNumber != null) 'S/N ${item.serialNumber}',
                                  ].join(' · '),
                                ),
                                trailing: Text(formatMoney(item.total), style: text.titleSmall),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (data.reminders.isNotEmpty) ...[
                      const SectionHeader('Upcoming reminders'),
                      for (final reminder in data.reminders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ReminderTile(
                            reminder: reminder,
                            onDismiss: () =>
                                ref.read(receiptDetailPresenterProvider(r.id).notifier).dismissReminder(reminder.id),
                          ),
                        ),
                    ],
                    const SectionHeader('Details'),
                    SurfaceCard(
                      child: Column(
                        children: [
                          _InfoRow(label: 'Payment', value: r.paymentMethod ?? 'Not recorded'),
                          _InfoRow(label: 'Added', value: formatDate(r.createdAt)),
                          _InfoRow(label: 'Reference', value: shortReference(r.id)),
                          if (r.notes != null) _InfoRow(label: 'Notes', value: r.notes!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageCarousel extends ConsumerWidget {
  const _ImageCarousel({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PageView(
    children: [
      for (final (i, a) in receipt.attachments.indexed)
        GestureDetector(
          onTap: () => _openViewer(context, ref, a),
          child: Hero(
            tag: i == 0 ? 'receipt-${receipt.id}' : 'att-${a.id}',
            child: Consumer(
              builder: (context, ref, _) {
                final bytes = ref.watch(attachmentBytesProvider(a)).value;
                return Container(
                  color: Colors.black,
                  child: bytes == null
                      ? const Center(child: CircularProgressIndicator())
                      : Image.memory(bytes, fit: BoxFit.cover, width: double.infinity),
                );
              },
            ),
          ),
        ),
    ],
  );

  void _openViewer(BuildContext context, WidgetRef ref, Attachment a) {
    final bytes = ref.read(attachmentBytesProvider(a)).value;
    if (bytes == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes))),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard({required this.data});
  final DetailData data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final deadline = data.returnDeadline;
    final rows = <Widget>[];

    if (deadline != null) {
      final open = data.returnOpen;
      rows.add(
        _ProtectionRow(
          icon: Icons.assignment_return_rounded,
          color: open ? KeeprColors.amber : scheme.onSurfaceVariant,
          title: open ? 'Return window open' : 'Return window closed',
          subtitle: open
              ? 'Until ${formatDate(deadline)} (${relativeDays(data.returnDaysLeft!)})'
              : 'Closed on ${formatDate(deadline)}',
        ),
      );
    }
    for (final w in data.warranties) {
      final (label, color, _) = WarrantyBadge.describe(w.status)!;
      rows.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProtectionRow(
              icon: Icons.verified_user_rounded,
              color: color,
              title: w.item.name,
              subtitle: w.status == WarrantyStatus.expired
                  ? 'Warranty ended ${formatDate(w.end)}'
                  : '$label · until ${formatDate(w.end)} (${relativeDays(w.daysLeft)})',
            ),
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: w.elapsed,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return SurfaceCard(
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No return window or warranty recorded. Edit the receipt to add them and get reminders.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[if (i > 0) const SizedBox(height: 16), row],
        ],
      ),
    );
  }
}

class _ProtectionRow extends StatelessWidget {
  const _ProtectionRow({required this.icon, required this.color, required this.title, required this.subtitle});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: color, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.onDismiss});
  final Reminder reminder;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
    child: Row(
      children: [
        Icon(
          reminder.type == ReminderType.returnWindow
              ? Icons.assignment_return_rounded
              : Icons.notifications_active_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reminder.title, style: Theme.of(context).textTheme.titleSmall),
              Text(formatDateTime(reminder.fireAt), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Dismiss reminder',
          onPressed: onDismiss,
          icon: const Icon(Icons.notifications_off_outlined),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}
