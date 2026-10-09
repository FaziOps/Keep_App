import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../auth/domain/entities/app_user.dart';
import '../../billing/domain/entities/entitlement.dart';
import '../../household/domain/entities/household.dart';
import '../../insights/domain/insights.dart';
import '../../receipts/domain/entities/receipt.dart';
import '../../sync/domain/sync_repository.dart';
import '../domain/entities/app_settings.dart';

class SettingsUiState {
  const SettingsUiState({
    required this.user,
    required this.settings,
    required this.entitlement,
    required this.sync,
    required this.household,
    required this.cloudAvailable,
  });

  final AppUser? user;
  final AppSettings settings;
  final Entitlement? entitlement;
  final SyncStatus sync;
  final Household? household;
  final bool cloudAvailable;
}

/// Presenter for Settings (FR-SET-01..04, FR-AUTH-06).
class SettingsPresenter extends Notifier<SettingsUiState> {
  @override
  SettingsUiState build() => SettingsUiState(
    user: ref.watch(currentUserProvider).value,
    settings: ref.watch(settingsProvider).value ?? ref.read(settingsRepositoryProvider).current,
    entitlement: ref.watch(entitlementProvider).value,
    sync: ref.watch(syncStatusProvider).value ?? const SyncStatus(),
    household: ref.watch(activeHouseholdProvider).value,
    cloudAvailable: ref.read(authRepositoryProvider).isCloudAvailable,
  );

  Future<void> _save(AppSettings Function(AppSettings s) change) {
    final repo = ref.read(settingsRepositoryProvider);
    return repo.save(change(repo.current));
  }

  Future<void> setTheme(ThemePreference p) => _save((s) => s.copyWith(themePreference: p));
  Future<void> setCurrency(String c) => _save((s) => s.copyWith(currency: c));

  /// Returns false when the OS refused notification permission.
  Future<bool> setNotifications(bool enabled) async {
    if (enabled) {
      final scheduler = ref.read(reminderSchedulerProvider);
      if (scheduler.isSupported && !await scheduler.requestPermission()) return false;
    }
    await _save((s) => s.copyWith(notificationsEnabled: enabled));
    // Re-plan so enabling schedules and disabling cancels OS notifications.
    final schedule = ref.read(scheduleRemindersProvider);
    for (final r in ref.read(householdReceiptsProvider).value ?? const <Receipt>[]) {
      enabled ? await schedule(r) : await schedule.cancelFor(r.id);
    }
    return true;
  }

  Future<String?> updateName(String name) async {
    if (name.trim().length < 2) return 'Enter your name';
    final result = await ref.read(authRepositoryProvider).updateDisplayName(name.trim());
    return result.failureOrNull?.message;
  }

  Future<String> syncNow() async {
    final result = await ref.read(syncRepositoryProvider).syncNow();
    return result.fold(
      (f) => f.message,
      (r) => r.skipped ? 'Sync is off in local mode' : 'Up to date · ${r.pushed} sent, ${r.pulled} received',
    );
  }

  Future<String?> exportAll() async {
    final receipts = ref.read(householdReceiptsProvider).value ?? const [];
    if (receipts.isEmpty) return 'There is nothing to export yet.';
    try {
      await ref
          .read(fileExporterProvider)
          .share(
            bytes: Uint8List.fromList(utf8.encode(ReceiptsCsv.build(receipts))),
            fileName: 'keepr-export.csv',
            mimeType: 'text/csv',
          );
      return null;
    } catch (_) {
      return 'Export failed.';
    }
  }

  Future<int> loadSamples() async {
    final household = ref.read(activeHouseholdProvider).value;
    final user = ref.read(currentUserProvider).value;
    if (household == null || user == null) return 0;
    return ref.read(seedDemoReceiptsProvider)(
      householdId: household.id,
      userId: user.id,
      currency: state.settings.currency,
    );
  }

  bool get hasUnsyncedChanges => state.sync.pendingOps > 0;

  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

  Future<String?> deleteAccount() async {
    final result = await ref.read(authRepositoryProvider).deleteAccount();
    return result.failureOrNull?.message;
  }

  Future<void> resetToFree() => ref.read(entitlementRepositoryProvider).resetToFree();
}

final settingsPresenterProvider = NotifierProvider<SettingsPresenter, SettingsUiState>(SettingsPresenter.new);
