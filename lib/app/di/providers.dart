import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/clock.dart';
import '../../core/services/file_exporter.dart';
import '../../core/services/image_capture.dart';
import '../../core/services/share_file_exporter.dart';
import '../../core/storage/local_store.dart';
import '../../features/auth/data/auth_repository_impl.dart';
import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/auth_usecases.dart';
import '../../features/billing/data/entitlement_repository_impl.dart';
import '../../features/billing/domain/entities/entitlement.dart';
import '../../features/billing/domain/repositories/entitlement_repository.dart';
import '../../features/claims/data/pdf_claim_pack_renderer.dart';
import '../../features/claims/domain/claim_pack.dart';
import '../../features/household/data/household_repository_impl.dart';
import '../../features/household/domain/entities/household.dart';
import '../../features/household/domain/repositories/household_repository.dart';
import '../../features/protection/data/local_notification_scheduler.dart';
import '../../features/protection/data/reminder_repository_impl.dart';
import '../../features/protection/domain/entities/reminder.dart';
import '../../features/protection/domain/repositories/reminder_repository.dart';
import '../../features/protection/domain/usecases/schedule_reminders.dart';
import '../../features/receipts/data/datasources/extraction_remote_data_source.dart';
import '../../features/receipts/data/datasources/on_device_ocr_data_source.dart';
import '../../features/receipts/data/datasources/receipt_local_data_source.dart';
import '../../features/receipts/data/datasources/receipt_remote_data_source.dart';
import '../../features/receipts/data/repositories/receipt_extractor_impl.dart';
import '../../features/receipts/data/repositories/receipt_repository_impl.dart';
import '../../features/receipts/domain/entities/receipt.dart';
import '../../features/receipts/domain/repositories/receipt_repository.dart';
import '../../features/receipts/domain/usecases/process_queued_receipts.dart';
import '../../features/receipts/domain/usecases/receipt_usecases.dart';
import '../../features/receipts/domain/usecases/seed_demo_receipts.dart';
import '../../features/settings/data/settings_repository_impl.dart';
import '../../features/settings/domain/entities/app_settings.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/sync/data/outbox.dart';
import '../../features/sync/data/sync_service.dart';
import '../../features/sync/domain/sync_repository.dart';

// ---------------------------------------------------------------------------
// Composition root. Every dependency is wired here; tests override any
// provider with a fake. Overridden in main(): store, client, scheduler.
// ---------------------------------------------------------------------------

final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError());
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);
final notificationSchedulerProvider = Provider<LocalNotificationScheduler>((ref) => throw UnimplementedError());

final clockProvider = Provider<Clock>((ref) => systemClock);
final idGeneratorProvider = Provider<String Function()>((ref) => const Uuid().v4);
final fileExporterProvider = Provider<FileExporter>((ref) => const ShareFileExporter());
final imageCaptureProvider = Provider<ImageCapture>((ref) => ImagePickerCapture());

// Settings ------------------------------------------------------------------
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepositoryImpl(ref.watch(localStoreProvider)),
);
final settingsProvider = StreamProvider<AppSettings>((ref) => ref.watch(settingsRepositoryProvider).watch());

// Auth ----------------------------------------------------------------------
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepositoryImpl(store: ref.watch(localStoreProvider), client: ref.watch(supabaseClientProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
final currentUserProvider = StreamProvider<AppUser?>((ref) => ref.watch(authRepositoryProvider).watchUser());
final signInProvider = Provider((ref) => SignIn(ref.watch(authRepositoryProvider)));
final signUpProvider = Provider((ref) => SignUp(ref.watch(authRepositoryProvider)));
final continueOfflineProvider = Provider((ref) => ContinueOffline(ref.watch(authRepositoryProvider)));

// Household -----------------------------------------------------------------
final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => HouseholdRepositoryImpl(store: ref.watch(localStoreProvider), client: ref.watch(supabaseClientProvider)),
);
final activeHouseholdProvider = FutureProvider<Household?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
  final preferred = ref.watch(settingsProvider.select((s) => s.value?.activeHouseholdId));
  final result = await ref.watch(householdRepositoryProvider).activeHousehold(user, preferredId: preferred);
  return result.fold((f) => throw f, (h) => h);
});

// Billing -------------------------------------------------------------------
final entitlementRepositoryProvider = Provider<EntitlementRepository>(
  (ref) => EntitlementRepositoryImpl(
    store: ref.watch(localStoreProvider),
    billing: DemoBillingGateway(ref.watch(clockProvider)),
    clock: ref.watch(clockProvider),
    client: ref.watch(supabaseClientProvider),
  ),
);
final entitlementProvider = StreamProvider<Entitlement>((ref) => ref.watch(entitlementRepositoryProvider).watch());

// Reminders -----------------------------------------------------------------
final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepositoryImpl(ref.watch(localStoreProvider)),
);
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => ref.watch(notificationSchedulerProvider));
final scheduleRemindersProvider = Provider(
  (ref) => ScheduleReminders(
    ref.watch(reminderRepositoryProvider),
    ref.watch(reminderSchedulerProvider),
    ref.watch(clockProvider),
    notificationsEnabled: () => ref.read(settingsRepositoryProvider).current.notificationsEnabled,
  ),
);
final allRemindersProvider = StreamProvider<List<Reminder>>((ref) => ref.watch(reminderRepositoryProvider).watchAll());

// Receipts ------------------------------------------------------------------
final outboxProvider = Provider((ref) => Outbox(ref.watch(localStoreProvider)));
final receiptLocalDataSourceProvider = Provider((ref) => ReceiptLocalDataSource(ref.watch(localStoreProvider)));
final receiptRemoteDataSourceProvider = Provider<ReceiptRemoteDataSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : ReceiptRemoteDataSource(client);
});
final Provider<ReceiptRepository> receiptRepositoryProvider = Provider(
  (ref) => ReceiptRepositoryImpl(
    local: ref.watch(receiptLocalDataSourceProvider),
    outbox: ref.watch(outboxProvider),
    clock: ref.watch(clockProvider),
    remote: ref.watch(receiptRemoteDataSourceProvider),
    onLocalChange: () => ref.read(syncRepositoryProvider).requestSync(),
  ),
);
final receiptExtractorProvider = Provider<ReceiptExtractor>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ReceiptExtractorImpl(
    remote: client == null ? null : ExtractionRemoteDataSource(client),
    onDevice: const OnDeviceOcrDataSource(),
    clock: ref.watch(clockProvider),
  );
});

final scanReceiptProvider = Provider(
  (ref) => ScanReceipt(ref.watch(receiptExtractorProvider), ref.watch(entitlementRepositoryProvider)),
);
final saveReceiptProvider = Provider(
  (ref) =>
      SaveReceipt(ref.watch(receiptRepositoryProvider), ref.watch(scheduleRemindersProvider), ref.watch(clockProvider)),
);
final deleteReceiptProvider = Provider(
  (ref) => DeleteReceipt(ref.watch(receiptRepositoryProvider), ref.watch(scheduleRemindersProvider)),
);
final archiveReceiptProvider = Provider(
  (ref) => ArchiveReceipt(
    ref.watch(receiptRepositoryProvider),
    ref.watch(scheduleRemindersProvider),
    ref.watch(clockProvider),
  ),
);
final findDuplicatesProvider = Provider((ref) => FindDuplicates(ref.watch(receiptRepositoryProvider)));
final Provider<ProcessQueuedReceipts> processQueuedReceiptsProvider = Provider(
  (ref) => ProcessQueuedReceipts(
    ref.watch(receiptRepositoryProvider),
    ref.watch(receiptExtractorProvider),
    ref.watch(entitlementRepositoryProvider),
    ref.watch(clockProvider),
    ref.watch(idGeneratorProvider),
  ),
);
final seedDemoReceiptsProvider = Provider(
  (ref) => SeedDemoReceipts(ref.watch(saveReceiptProvider), ref.watch(clockProvider), ref.watch(idGeneratorProvider)),
);

/// Live receipts of the active household.
final householdReceiptsProvider = StreamProvider<List<Receipt>>((ref) async* {
  final household = await ref.watch(activeHouseholdProvider.future);
  if (household == null) {
    yield const [];
    return;
  }
  yield* ref.watch(receiptRepositoryProvider).watchReceipts(household.id);
});

final attachmentBytesProvider = FutureProvider.family<Uint8List?, Attachment>(
  (ref, attachment) => ref.watch(receiptRepositoryProvider).attachmentBytes(attachment),
);

// Claims --------------------------------------------------------------------
final generateClaimPackProvider = Provider(
  (ref) => GenerateClaimPack(
    ref.watch(receiptRepositoryProvider),
    ref.watch(entitlementRepositoryProvider),
    const PdfClaimPackRenderer(),
    ref.watch(clockProvider),
  ),
);

// Sync ----------------------------------------------------------------------
final Provider<SyncService> syncServiceProvider = Provider((ref) {
  final service = SyncService(
    store: ref.watch(localStoreProvider),
    local: ref.watch(receiptLocalDataSourceProvider),
    outbox: ref.watch(outboxProvider),
    clock: ref.watch(clockProvider),
    scheduleReminders: ref.watch(scheduleRemindersProvider),
    remote: ref.watch(receiptRemoteDataSourceProvider),
    activeCloudHouseholdId: () {
      final household = ref.read(activeHouseholdProvider).value;
      return household == null || household.isLocal ? null : household.id;
    },
    afterSync: () async {
      await ref.read(entitlementRepositoryProvider).refresh();
      await ref.read(processQueuedReceiptsProvider)(ref.read(receiptLocalDataSourceProvider).all());
    },
  );
  ref.onDispose(service.dispose);
  return service;
});
final Provider<SyncRepository> syncRepositoryProvider = Provider((ref) => ref.watch(syncServiceProvider));
final syncStatusProvider = StreamProvider<SyncStatus>((ref) => ref.watch(syncRepositoryProvider).watchStatus());
