import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/domain/entities/app_settings.dart';
import 'di/providers.dart';
import 'router.dart';
import 'theme.dart';

class KeeprApp extends ConsumerStatefulWidget {
  const KeeprApp({super.key});

  @override
  ConsumerState<KeeprApp> createState() => _KeeprAppState();
}

class _KeeprAppState extends ConsumerState<KeeprApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Sync when the app comes back to the foreground (FR-SYN-03).
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(syncRepositoryProvider).requestSync());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(settingsProvider.select((s) => s.value?.themePreference ?? ThemePreference.system));
    return MaterialApp.router(
      title: 'Keepr',
      debugShowCheckedModeBanner: false,
      theme: buildKeeprTheme(Brightness.light),
      darkTheme: buildKeeprTheme(Brightness.dark),
      themeMode: switch (preference) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
