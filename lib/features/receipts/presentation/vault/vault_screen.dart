import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/entities/receipt.dart';
import '../widgets/receipt_visuals.dart';
import 'vault_presenter.dart';

class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultPresenterProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (state) {
          VaultLoading() => const Center(child: CircularProgressIndicator()),
          VaultError(:final message) => ErrorState(
            message: message,
            onRetry: ref.read(vaultPresenterProvider.notifier).retry,
          ),
          VaultEmpty(:final greetingName, :final isLocal) => _EmptyVault(name: greetingName, isLocal: isLocal),
          VaultData() => _VaultList(data: state),
        },
      ),
    );
  }
}

class _EmptyVault extends ConsumerWidget {
  const _EmptyVault({required this.name, required this.isLocal});
  final String name;
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
    children: [
      _Greeting(name: name, subtitle: 'Let’s protect your first purchase'),
      const SizedBox(height: 40),
      EmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'Your vault is empty',
        message: 'Scan a receipt and Keepr will track its return window and warranty for you.',
        action: Column(
          children: [
            FilledButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(Icons.document_scanner_rounded),
              label: const Text('Scan your first receipt'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: ref.read(vaultPresenterProvider.notifier).loadSampleReceipts,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Explore with sample receipts'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.subtitle});
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? greeting : '$greeting, $name', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const KeeprLogo(size: 44),
      ],
    );
  }
}

class _VaultList extends ConsumerStatefulWidget {
  const _VaultList({required this.data});
  final VaultData data;

  @override
  ConsumerState<_VaultList> createState() => _VaultListState();
}

class _VaultListState extends ConsumerState<_VaultList> {
  late final _search = TextEditingController(text: widget.data.filter.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final presenter = ref.read(vaultPresenterProvider.notifier);

    return ContentWidth(
      maxWidth: 820,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverList.list(
              children: [
                _Greeting(name: data.greetingName, subtitle: data.householdName),
                const SizedBox(height: 20),
                _SummaryCard(summary: data.summary),
                const SizedBox(height: 20),
                TextField(
                  controller: _search,
                  onChanged: presenter.search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search store, item, serial or amount',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: data.filter.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              presenter.search('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final (status, label) in const [
                    (StatusFilter.all, 'All'),
                    (StatusFilter.protected, 'Protected'),
                    (StatusFilter.expiringSoon, 'Expiring soon'),
                    (StatusFilter.returnOpen, 'Returnable'),
                    (StatusFilter.drafts, 'Drafts'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: data.filter.status == status,
                        onSelected: (_) => presenter.selectStatus(status),
                      ),
                    ),
                  const SizedBox(width: 4),
                  _CategoryMenu(selected: data.filter.category, onSelected: presenter.selectCategory),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                data.filter.isActive ? '${data.cards.length} results' : 'Recent receipts',
                trailing: data.filter.isActive
                    ? TextButton(
                        onPressed: () {
                          _search.clear();
                          presenter.clearFilters();
                        },
                        child: const Text('Clear filters'),
                      )
                    : null,
              ),
            ),
          ),
          if (data.cards.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                message: 'Try another search term or clear the filters.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.separated(
                itemCount: data.cards.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => ReceiptCard(card: data.cards[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.selected, required this.onSelected});
  final Category? selected;
  final ValueChanged<Category?> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<Category?>(
    tooltip: 'Filter by category',
    onSelected: onSelected,
    itemBuilder: (_) => [
      const PopupMenuItem(value: null, child: Text('All categories')),
      for (final c in Category.values)
        PopupMenuItem(
          value: c,
          child: Row(
            children: [
              Icon(CategoryStyle.of(c).icon, color: CategoryStyle.of(c).color, size: 20),
              const SizedBox(width: 12),
              Text(c.label),
            ],
          ),
        ),
    ],
    child: Chip(
      avatar: Icon(selected == null ? Icons.tune_rounded : CategoryStyle.of(selected!).icon, size: 18),
      label: Text(selected?.label ?? 'Category'),
      backgroundColor: selected == null ? null : Theme.of(context).chipTheme.selectedColor,
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final VaultSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: KeeprColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: KeeprColors.brand.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: KeeprColors.brandBright, size: 18),
              const SizedBox(width: 6),
              Text('Protected value', style: text.labelLarge?.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 6),
          Text(summary.protectedValue, style: text.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(value: '${summary.receiptCount}', label: 'Receipts'),
              _Stat(value: '${summary.expiringSoon}', label: 'Expiring', highlight: summary.expiringSoon > 0),
              _Stat(value: '${summary.openReturns}', label: 'Returnable'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.highlight = false});
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlight ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: text.titleLarge?.copyWith(color: highlight ? const Color(0xFFFDE68A) : Colors.white)),
            Text(
              label,
              style: text.labelSmall?.copyWith(color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.card});
  final ReceiptCardVm card;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/receipt/${card.id}'),
      child: Row(
        children: [
          Hero(
            tag: 'receipt-${card.id}',
            child: ReceiptThumbnail(attachment: card.cover, category: card.category, size: 60),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(card.merchant, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(card.totalLabel, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(card.subtitle, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ReceiptStatusBadge(status: card.receiptStatus, syncState: card.syncState),
                    WarrantyBadge(card.warrantyStatus),
                    if (card.deadlineLabel != null)
                      Pill(
                        label: card.deadlineLabel!,
                        color: KeeprColors.amber,
                        icon: Icons.event_rounded,
                        dense: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
