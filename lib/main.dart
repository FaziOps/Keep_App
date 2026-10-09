import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/di/providers.dart';
import 'core/env.dart';
import 'core/storage/local_store.dart';
import 'features/protection/data/local_notification_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  SupabaseClient? client;
  if (Env.isCloudConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
    client = Supabase.instance.client;
  }
  final scheduler = await LocalNotificationScheduler.create();

  final container = ProviderContainer(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      supabaseClientProvider.overrideWithValue(client),
      notificationSchedulerProvider.overrideWithValue(scheduler),
    ],
  );

  // Background work: trash purge (BR-09), sync triggers (FR-SYN-03).
  unawaited(container.read(receiptRepositoryProvider).purgeExpiredTrash(DateTime.now()));
  if (client != null) {
    final online = Connectivity().onConnectivityChanged.map(
      (results) => results.any((r) => r != ConnectivityResult.none),
    );
    container.read(syncServiceProvider).start(online);
    container.listen(activeHouseholdProvider, (_, next) {
      if (next.value != null) container.read(syncRepositoryProvider).requestSync();
    }, fireImmediately: true);
  }

  runApp(UncontrolledProviderScope(container: container, child: const KeeprApp()));
}
