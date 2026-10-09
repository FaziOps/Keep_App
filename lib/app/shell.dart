import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Tab scaffold: bottom bar with a central Scan button on phones, a
/// navigation rail on tablets and desktop web.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Vault'),
    (Icons.shield_outlined, Icons.shield_rounded, 'Protection'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Insights'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final scheme = Theme.of(context).colorScheme;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: FloatingActionButton(
                  heroTag: 'scan-rail',
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  onPressed: () => context.push('/scan'),
                  tooltip: 'Scan receipt',
                  child: const Icon(Icons.document_scanner_rounded),
                ),
              ),
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: Text(t.$3)),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'scan-fab',
        onPressed: () => context.push('/scan'),
        tooltip: 'Scan receipt',
        elevation: 4,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.document_scanner_rounded, size: 32),
      ),
      bottomNavigationBar: BottomAppBar(
        height: 72,
        padding: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) ...[
              if (i == 2) const SizedBox(width: 84),
              Expanded(
                child: _TabButton(tab: _tabs[i], selected: shell.currentIndex == i, onTap: () => _go(i)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.tab, required this.selected, required this.onTap});
  final (IconData, IconData, String) tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: tab.$3,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(selected ? tab.$2 : tab.$1, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              tab.$3,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color, fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
