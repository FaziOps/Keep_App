import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/common.dart';
import 'claim_pack_presenter.dart';

class ClaimPackScreen extends ConsumerStatefulWidget {
  const ClaimPackScreen({super.key, required this.receiptId, this.itemId});
  final String receiptId;
  final String? itemId;

  @override
  ConsumerState<ClaimPackScreen> createState() => _ClaimPackScreenState();
}

class _ClaimPackScreenState extends ConsumerState<ClaimPackScreen> {
  final _issue = TextEditingController();

  @override
  void dispose() {
    _issue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = claimPackPresenterProvider(widget.receiptId);
    final state = ref.watch(provider);
    final presenter = ref.read(provider.notifier);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Claim pack')),
      body: ContentWidth(
        maxWidth: 600,
        child: switch (state) {
          ClaimPaywall() => EmptyState(
            icon: Icons.workspace_premium_rounded,
            title: 'Claim pack limit reached',
            message: 'Free plans include 3 claim packs a month. Upgrade for unlimited claim packs.',
            action: FilledButton(onPressed: () => context.push('/paywall'), child: const Text('See Premium')),
          ),
          ClaimError(:final message) => ErrorState(message: message, onRetry: presenter.reset),
          ClaimReady(:final pack) => EmptyState(
            icon: Icons.task_alt_rounded,
            title: 'Your claim pack is ready',
            message: '${pack.fileName}\nSend it to the store or manufacturer by email or WhatsApp.',
            action: Column(
              children: [
                FilledButton.icon(
                  onPressed: presenter.share,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share PDF'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => context.pop(), child: const Text('Done')),
              ],
            ),
          ),
          ClaimGenerating() || ClaimIdle() => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(gradient: KeeprColors.heroGradient, borderRadius: BorderRadius.circular(24)),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Everything the shop needs', style: text.titleMedium?.copyWith(color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(
                            'Receipt image, item and serial details, warranty status and a ready-to-send claim letter.',
                            style: text.bodySmall?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('What went wrong?', style: text.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _issue,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. The left earbud stopped charging after two weeks of normal use.',
                  errorText: state is ClaimIdle ? state.issueError : null,
                ),
              ),
              const SizedBox(height: 12),
              if (state is ClaimIdle && state.claimsLeft != null)
                Text(
                  '${state.claimsLeft} free claim packs left this month',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: 24),
              LoadingButton(
                label: 'Create and share PDF',
                icon: Icons.picture_as_pdf_rounded,
                loading: state is ClaimGenerating,
                onPressed: () => presenter.generate(issue: _issue.text, itemId: widget.itemId),
              ),
            ],
          ),
        },
      ),
    );
  }
}
