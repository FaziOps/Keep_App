import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di/providers.dart';
import '../../../app/theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/entities/entitlement.dart';

class PaywallUiState {
  const PaywallUiState({this.period = PlanPeriod.yearly, this.busy = false, this.error, this.done = false});
  final PlanPeriod period;
  final bool busy;
  final String? error;
  final bool done;

  PaywallUiState copyWith({PlanPeriod? period, bool? busy, String? error, bool? done}) =>
      PaywallUiState(period: period ?? this.period, busy: busy ?? this.busy, error: error, done: done ?? this.done);
}

/// Presenter for the Premium paywall (FR-SUB-01..04).
class PaywallPresenter extends Notifier<PaywallUiState> {
  @override
  PaywallUiState build() => const PaywallUiState();

  void select(PlanPeriod p) => state = state.copyWith(period: p);

  Future<void> purchase() async {
    state = state.copyWith(busy: true);
    final result = await ref.read(entitlementRepositoryProvider).purchase(state.period);
    if (!ref.mounted) return;
    state = result.fold(
      (f) => state.copyWith(busy: false, error: f.message),
      (_) => state.copyWith(busy: false, done: true),
    );
  }

  Future<void> restore() async {
    state = state.copyWith(busy: true);
    final result = await ref.read(entitlementRepositoryProvider).restore();
    if (!ref.mounted) return;
    state = result.fold(
      (f) => state.copyWith(busy: false, error: f.message),
      (_) => state.copyWith(busy: false, done: true),
    );
  }
}

final paywallPresenterProvider = NotifierProvider.autoDispose<PaywallPresenter, PaywallUiState>(PaywallPresenter.new);

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  static const _features = [
    ('AI receipt scans', '15 / month', 'Unlimited'),
    ('Claim pack PDFs', '3 / month', 'Unlimited'),
    ('Household members', 'Up to 2', 'Up to 6'),
    ('Reminders & cloud backup', 'Included', 'Included'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(paywallPresenterProvider);
    final presenter = ref.read(paywallPresenterProvider.notifier);
    final text = Theme.of(context).textTheme;

    ref.listen(paywallPresenterProvider, (_, next) {
      if (next.done) {
        showMessage(context, 'Welcome to Premium!');
        context.pop();
      } else if (next.error != null) {
        showMessage(context, next.error!, error: true);
      }
    });

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF4F46E5),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5), KeeprColors.brand],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 44),
                    const SizedBox(height: 12),
                    Text('Keepr Premium', style: text.headlineMedium?.copyWith(color: Colors.white)),
                    Text(
                      'Protect everything you own, without limits.',
                      style: text.bodyLarge?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: ContentWidth(
              maxWidth: 560,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SurfaceCard(
                      child: Table(
                        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)},
                        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            children: [
                              const SizedBox(),
                              Text('Free', style: text.labelLarge, textAlign: TextAlign.center),
                              Text(
                                'Premium',
                                style: text.labelLarge?.copyWith(color: const Color(0xFF7C3AED)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                          for (final (name, free, premium) in _features)
                            TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(name, style: text.bodyMedium),
                                ),
                                Text(free, style: text.bodySmall, textAlign: TextAlign.center),
                                Text(
                                  premium,
                                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PlanOption(
                      title: 'Yearly',
                      price: r'$19.99 / year',
                      badge: 'Save 45%',
                      selected: state.period == PlanPeriod.yearly,
                      onTap: () => presenter.select(PlanPeriod.yearly),
                    ),
                    const SizedBox(height: 10),
                    _PlanOption(
                      title: 'Monthly',
                      price: r'$2.99 / month',
                      selected: state.period == PlanPeriod.monthly,
                      onTap: () => presenter.select(PlanPeriod.monthly),
                    ),
                    const SizedBox(height: 20),
                    LoadingButton(label: 'Start Premium', loading: state.busy, onPressed: presenter.purchase),
                    TextButton(
                      onPressed: state.busy ? null : presenter.restore,
                      child: const Text('Restore purchases'),
                    ),
                    Text(
                      'Cancel anytime in your store account. Demo build: purchases are simulated and no payment is taken.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall,
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

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String title;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7C3AED);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? accent : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected ? accent.withValues(alpha: 0.06) : Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? accent : null,
            ),
            const SizedBox(width: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (badge != null) ...[const SizedBox(width: 8), Pill(label: badge!, color: accent, dense: true)],
            const Spacer(),
            Text(price, style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      ),
    );
  }
}
