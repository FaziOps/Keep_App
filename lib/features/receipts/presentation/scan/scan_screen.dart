import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/common.dart';
import '../review/review_presenter.dart';
import 'scan_presenter.dart';

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanPresenterProvider);
    final presenter = ref.read(scanPresenterProvider.notifier);

    ref.listen(scanPresenterProvider, (_, next) {
      if (next is ScanReady) {
        context.pushReplacement('/review', extra: ReviewArgs.fromDraft(next.draft));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Add a receipt')),
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 560,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (state) {
              ScanProcessing(:final image, :final step) => _Processing(image: image, step: step),
              ScanQuotaExceeded() => EmptyState(
                icon: Icons.workspace_premium_rounded,
                title: 'You’ve used this month’s AI scans',
                message: 'Upgrade to Premium for unlimited scans, or add this receipt by typing the details.',
                action: Column(
                  children: [
                    FilledButton(onPressed: () => context.push('/paywall'), child: const Text('See Premium')),
                    const SizedBox(height: 8),
                    TextButton(onPressed: presenter.enterManually, child: const Text('Enter manually')),
                  ],
                ),
              ),
              ScanError(:final message) => ErrorState(message: message, onRetry: presenter.reset),
              ScanIdle(:final aiAvailable, :final cloudAi, :final scansLeft) => _Options(
                aiAvailable: aiAvailable,
                scansLeft: cloudAi ? scansLeft : null,
              ),
              ScanReady() => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }
}

class _Options extends ConsumerWidget {
  const _Options({required this.aiAvailable, required this.scansLeft});
  final bool aiAvailable;
  final int? scansLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presenter = ref.read(scanPresenterProvider.notifier);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hasCamera = !kIsWeb;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 210,
          decoration: BoxDecoration(gradient: KeeprColors.heroGradient, borderRadius: BorderRadius.circular(28)),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _FramePainter())),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      aiAvailable ? 'AI reads it for you' : 'Keep every receipt safe',
                      style: text.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      aiAvailable ? 'Store, date, items and total in seconds' : 'Add a photo and the key details',
                      style: text.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (aiAvailable)
          Align(
            alignment: Alignment.centerLeft,
            child: scansLeft == null
                ? const Pill(
                    label: 'Unlimited scans · read on your phone',
                    color: KeeprColors.brand,
                    icon: Icons.offline_bolt_rounded,
                  )
                : Pill(
                    label: scansLeft! > 0
                        ? '$scansLeft cloud AI scans left this month'
                        : 'Cloud AI scans used up · reading on your phone',
                    color: scansLeft! > 3 ? KeeprColors.brand : KeeprColors.amber,
                    icon: Icons.auto_awesome_rounded,
                  ),
          ),
        const SizedBox(height: 16),
        _OptionTile(
          icon: Icons.photo_camera_rounded,
          title: hasCamera ? 'Take a photo' : 'Use camera',
          subtitle: 'Lay the receipt flat in good light',
          primary: true,
          onTap: () => presenter.capture(fromCamera: true),
        ),
        const SizedBox(height: 12),
        _OptionTile(
          icon: Icons.photo_library_rounded,
          title: kIsWeb ? 'Upload an image' : 'Choose from gallery',
          subtitle: 'Screenshots of e-receipts work too',
          onTap: () => presenter.capture(fromCamera: false),
        ),
        const SizedBox(height: 12),
        _OptionTile(
          icon: Icons.edit_note_rounded,
          title: 'Enter manually',
          subtitle: 'No receipt? Add the purchase yourself',
          onTap: presenter.enterManually,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.lock_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Images are stored privately and only used to read this receipt.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      color: primary ? scheme.primary.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primary ? scheme.primary : scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: primary ? scheme.onPrimary : scheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({required this.image, required this.step});
  final Uint8List image;
  final String step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(image, fit: BoxFit.cover),
                  Container(color: Colors.black.withValues(alpha: 0.35)),
                  const _ScanLine(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const SizedBox(
            width: 220,
            child: LinearProgressIndicator(borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
          const SizedBox(height: 16),
          Text(step, style: text.titleMedium),
          const SizedBox(height: 4),
          Text('This usually takes a few seconds', style: text.bodySmall),
        ],
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Align(
      alignment: Alignment(0, _controller.value * 2 - 1),
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: KeeprColors.brandBright,
          boxShadow: [BoxShadow(color: KeeprColors.brandBright.withValues(alpha: 0.8), blurRadius: 16)],
        ),
      ),
    ),
  );
}

/// Corner brackets suggesting a camera frame.
class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const inset = 22.0, len = 28.0;
    final r = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(corner, corner.translate(len * dx, 0), paint)
        ..drawLine(corner, corner.translate(0, len * dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
