import 'dart:async';
import 'dart:typed_data';

import 'package:keepr/core/failures.dart';
import 'package:keepr/core/result.dart';
import 'package:keepr/core/services/image_capture.dart';
import 'package:keepr/features/billing/domain/entities/entitlement.dart';
import 'package:keepr/features/billing/domain/repositories/entitlement_repository.dart';
import 'package:keepr/features/protection/domain/entities/reminder.dart';
import 'package:keepr/features/protection/domain/repositories/reminder_repository.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/domain/entities/receipt_draft.dart';
import 'package:keepr/features/receipts/domain/repositories/receipt_repository.dart';
import 'package:keepr/features/settings/domain/entities/app_settings.dart';
import 'package:keepr/features/settings/domain/repositories/settings_repository.dart';

import 'fixtures.dart';

class FakeReceiptRepository implements ReceiptRepository {
  final items = <String, Receipt>{};
  final bytes = <String, Uint8List>{};
  final _changes = StreamController<void>.broadcast();

  List<Receipt> _household(String id) => items.values.where((r) => r.householdId == id && !r.isDeleted).toList();

  @override
  Stream<List<Receipt>> watchReceipts(String householdId) async* {
    yield _household(householdId);
    yield* _changes.stream.map((_) => _household(householdId));
  }

  @override
  Stream<Receipt?> watchReceipt(String id) async* {
    yield items[id];
    yield* _changes.stream.map((_) => items[id]);
  }

  @override
  Future<Result<Receipt>> getReceipt(String id) async =>
      items[id] == null ? const Failure(NotFoundFailure()) : Success(items[id]!);

  @override
  Future<Result<Receipt>> save(Receipt receipt, {Map<String, Uint8List> newAttachmentBytes = const {}}) async {
    items[receipt.id] = receipt;
    bytes.addAll(newAttachmentBytes);
    _changes.add(null);
    return Success(receipt);
  }

  @override
  Future<Result<void>> delete(String id) async {
    items[id] = items[id]!.copyWith(deletedAt: fixedNow);
    _changes.add(null);
    return const Success(null);
  }

  @override
  Stream<List<Receipt>> watchTrash(String householdId) => const Stream.empty();

  @override
  Future<Result<Receipt>> restore(String id) async => Success(items[id]!);

  @override
  Future<Uint8List?> attachmentBytes(Attachment attachment) async => bytes[attachment.id];

  @override
  Future<List<Receipt>> findDuplicates({
    required String householdId,
    required String merchant,
    required DateTime purchaseDate,
    required int totalMinor,
    String? excludeId,
  }) async => const [];

  @override
  Future<void> purgeExpiredTrash(DateTime now) async {}
}

class FakeExtractor implements ReceiptExtractor {
  FakeExtractor({this.cloud = true, this.onDevice = false, this.result});
  bool cloud;
  bool onDevice;
  Result<ReceiptDraft>? result;
  int calls = 0;
  bool? lastAllowCloud;

  @override
  bool get isCloudAvailable => cloud;

  @override
  bool get isOnDeviceAvailable => onDevice;

  @override
  Future<Result<ReceiptDraft>> extract({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
    bool allowCloud = true,
  }) async {
    calls++;
    lastAllowCloud = allowCloud;
    final engine = allowCloud && cloud ? ExtractionEngine.cloudAi : ExtractionEngine.onDevice;
    return result ??
        Success(ReceiptDraft(currency: currency, status: ReceiptStatus.needsReview, merchant: 'Shop', engine: engine));
  }
}

class FakeEntitlements implements EntitlementRepository {
  FakeEntitlements([Entitlement? e]) : value = e ?? Entitlement.free(fixedNow);
  Entitlement value;

  @override
  Future<Entitlement> current() async => value;

  @override
  Stream<Entitlement> watch() => Stream.value(value);

  @override
  Future<void> recordUsage(QuotaKind kind) async => value = value.consumed(kind);

  @override
  Future<void> refresh() async {}

  @override
  Future<Result<Entitlement>> purchase(PlanPeriod period) async =>
      Success(value = value.copyWith(tier: PlanTier.premium));

  @override
  Future<Result<Entitlement>> restore() async => const Failure(NotFoundFailure());

  @override
  Future<void> resetToFree() async => value = Entitlement.free(fixedNow);
}

class FakeReminderRepository implements ReminderRepository {
  final byReceipt = <String, List<Reminder>>{};

  @override
  Future<List<Reminder>> forReceipt(String receiptId) async => byReceipt[receiptId] ?? const [];

  @override
  Future<void> replaceForReceipt(String receiptId, List<Reminder> reminders) async => byReceipt[receiptId] = reminders;

  @override
  Future<void> dismiss(String reminderId) async {}

  @override
  Stream<List<Reminder>> watchAll() => Stream.value(byReceipt.values.expand((e) => e).toList());

  @override
  Stream<List<Reminder>> watchForReceipt(String receiptId) => Stream.value(byReceipt[receiptId] ?? const []);
}

class FakeScheduler implements ReminderScheduler {
  final scheduled = <String>{};

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(Reminder reminder) async => scheduled.add(reminder.id);

  @override
  Future<void> cancel(String reminderId) async => scheduled.remove(reminderId);
}

class FakeSettingsRepository implements SettingsRepository {
  AppSettings value = const AppSettings(onboardingDone: true);

  @override
  AppSettings get current => value;

  @override
  Future<void> save(AppSettings settings) async => value = settings;

  @override
  Stream<AppSettings> watch() => Stream.value(value);
}

class FakeImageCapture implements ImageCapture {
  FakeImageCapture([this.image]);
  CapturedImage? image;

  @override
  Future<CapturedImage?> capture({required bool fromCamera}) async => image;
}
