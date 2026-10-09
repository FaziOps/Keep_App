import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/onboarding_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/billing/presentation/paywall_screen.dart';
import '../features/claims/presentation/claim_pack_screen.dart';
import '../features/household/presentation/household_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/protection/presentation/protection_screen.dart';
import '../features/receipts/presentation/detail/receipt_detail_screen.dart';
import '../features/receipts/presentation/review/review_presenter.dart';
import '../features/receipts/presentation/review/review_screen.dart';
import '../features/receipts/presentation/scan/scan_screen.dart';
import '../features/receipts/presentation/trash_screen.dart';
import '../features/receipts/presentation/vault/vault_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'di/providers.dart';
import 'shell.dart';

/// Re-evaluates redirects when the user or settings change.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(List<Stream<Object?>> streams) {
    for (final s in streams) {
      _subs.add(s.listen((_) => notifyListeners()));
    }
  }
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  final refresh = _RouterRefresh([
    auth.watchUser().map((u) => u?.id).distinct(),
    settings.watch().map((s) => s.onboardingDone).distinct(),
  ]);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: '/vault',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!settings.current.onboardingDone) return loc == '/onboarding' ? null : '/onboarding';
      if (auth.currentUser == null) return loc == '/sign-in' ? null : '/sign-in';
      if (loc == '/onboarding' || loc == '/sign-in') return '/vault';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/vault', builder: (_, _) => const VaultScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/protection', builder: (_, _) => const ProtectionScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())],
          ),
        ],
      ),
      GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(
        path: '/review',
        redirect: (_, state) => state.extra is ReviewArgs ? null : '/vault',
        builder: (_, state) => ReviewScreen(args: state.extra! as ReviewArgs),
      ),
      GoRoute(
        path: '/receipt/:id',
        builder: (_, state) => ReceiptDetailScreen(receiptId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) => ReviewScreen(args: ReviewArgs.edit(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'claim',
            builder: (_, state) =>
                ClaimPackScreen(receiptId: state.pathParameters['id']!, itemId: state.uri.queryParameters['item']),
          ),
        ],
      ),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
      GoRoute(path: '/household', builder: (_, _) => const HouseholdScreen()),
      GoRoute(path: '/trash', builder: (_, _) => const TrashScreen()),
    ],
  );

  // FR-REM-03: notification taps deep-link to the receipt.
  final scheduler = ref.watch(notificationSchedulerProvider);
  final tapSub = scheduler.taps.listen(router.push);
  final launch = scheduler.launchLink;
  if (launch != null) {
    scheduler.launchLink = null;
    Future.microtask(() => router.push(launch));
  }
  ref.onDispose(() {
    tapSub.cancel();
    router.dispose();
  });
  return router;
});
