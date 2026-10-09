import '../../../core/result.dart';

class SyncStatus {
  const SyncStatus({
    this.pendingOps = 0,
    this.isSyncing = false,
    this.lastSyncedAt,
    this.lastError,
    this.enabled = false,
  });

  final int pendingOps;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? lastError;

  /// False in local-only mode.
  final bool enabled;

  SyncStatus copyWith({
    int? pendingOps,
    bool? isSyncing,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
    bool? enabled,
  }) => SyncStatus(
    pendingOps: pendingOps ?? this.pendingOps,
    isSyncing: isSyncing ?? this.isSyncing,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    lastError: clearError ? null : lastError ?? this.lastError,
    enabled: enabled ?? this.enabled,
  );
}

class SyncReport {
  const SyncReport({this.pushed = 0, this.pulled = 0, this.conflicts = 0, this.skipped = false});
  final int pushed;
  final int pulled;
  final int conflicts;
  final bool skipped;
}

abstract interface class SyncRepository {
  Stream<SyncStatus> watchStatus();
  SyncStatus get status;
  Future<Result<SyncReport>> syncNow();

  /// Fire-and-forget request used after local writes.
  void requestSync();
}
