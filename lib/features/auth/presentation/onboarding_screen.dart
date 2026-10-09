import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/common.dart';
import 'auth_presenter.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();

  static const _pages = [
    (
      Icons.document_scanner_rounded,
      'Snap it. Done.',
      'Take a photo of any receipt. Keepr reads the store, date, items and total for you.',
    ),
    (
      Icons.notifications_active_rounded,
      'Never miss a deadline',
      'Get reminded before return windows close and before warranties run out.',
    ),
    (
      Icons.picture_as_pdf_rounded,
      'Proof in one tap',
      'Something broke? Create a claim pack with your receipt, serial number and a ready letter.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(onboardingPresenterProvider);
    final presenter = ref.read(onboardingPresenterProvider.notifier);
    final isLast = page == _pages.length - 1;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 520,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Row(
                  children: [
                    const KeeprLogo(size: 40),
                    const SizedBox(width: 12),
                    Text('Keepr', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (!isLast) TextButton(onPressed: presenter.complete, child: const Text('Skip')),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: presenter.setPage,
                    itemBuilder: (context, i) {
                      final (icon, title, body) = _pages[i];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Illustration(icon: icon, index: i),
                          const SizedBox(height: 48),
                          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 14),
                          Text(
                            body,
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == page ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == page ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isLast
                        ? presenter.complete
                        : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Text(isLast ? 'Get started' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.icon, required this.index});
  final IconData icon;
  final int index;

  @override
  Widget build(BuildContext context) {
    final accents = [KeeprColors.brandBright, KeeprColors.amber, KeeprColors.sky];
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: accents[index].withValues(alpha: 0.12)),
          ),
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              gradient: KeeprColors.heroGradient,
              borderRadius: BorderRadius.circular(48),
              boxShadow: [
                BoxShadow(
                  color: KeeprColors.brand.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Icon(icon, size: 84, color: Colors.white),
          ),
          Positioned(
            right: 18,
            top: 26,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: accents[index], shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
