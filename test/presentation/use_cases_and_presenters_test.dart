import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepr/app/di/providers.dart';
import 'package:keepr/core/failures.dart';
import 'package:keepr/core/result.dart';
import 'package:keepr/core/services/image_capture.dart';
import 'package:keepr/features/auth/domain/entities/app_user.dart';
import 'package:keepr/features/billing/domain/entities/entitlement.dart';
import 'package:keepr/features/claims/domain/claim_pack.dart';
import 'package:keepr/features/claims/presentation/claim_pack_presenter.dart';
import 'package:keepr/core/services/file_exporter.dart';
import 'package:keepr/features/household/domain/entities/household.dart';
import 'package:keepr/features/protection/domain/usecases/schedule_reminders.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/receipts/domain/entities/receipt_draft.dart';
import 'package:keepr/features/receipts/domain/usecases/receipt_usecases.dart';
import 'package:keepr/features/receipts/presentation/scan/scan_presenter.dart';
import 'package:keepr/features/receipts/presentation/vault/vault_presenter.dart';
import 'package:keepr/features/settings/domain/entities/app_settings.dart';

import '../helpers/fakes.dart';
import '../helpers/fixtures.dart';

void main() {
  group('SaveReceipt (SSD-3)', () {
    late FakeReceiptRepository repo;
    late FakeReminderRepository reminders;
    late FakeScheduler scheduler;
    late SaveReceipt save;

    setUp(() {
      repo = FakeReceiptRepository();
      reminders = FakeReminderRepository();
      scheduler = FakeScheduler();
      save = SaveReceipt(
        repo,
        ScheduleReminders(reminders, scheduler, () => fixedNow, notificationsEnabled: () => true),
        () => fixedNow,
      );
    });

    test('invalid receipts are rejected and not stored', () async {
      final result = await save.confirm(receipt(merchant: ''));
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo.items, isEmpty);
    });

    test('valid receipts are confirmed and reminders scheduled', () async {
      final result = await save.confirm(
        receipt(status: ReceiptStatus.needsReview, returnDays: 14, items: [item(months: 12)]),
      );
      expect(result.valueOrNull?.status, ReceiptStatus.confirmed);
      expect(reminders.byReceipt['r1'], hasLength(3));
      expect(scheduler.scheduled, hasLength(3));
    });

    test('deleting cancels reminders', () async {
      await save.confirm(receipt(returnDays: 14));
      await DeleteReceipt(
        repo,
        ScheduleReminders(reminders, scheduler, () => fixedNow, notificationsEnabled: () => true),
      )('r1');
      expect(scheduler.scheduled, isEmpty);
      expect(repo.items['r1']!.isDeleted, isTrue);
    });
  });

  group('ScanReceipt (SSD-2)', () {
    final image = Uint8List.fromList([1, 2, 3]);

    test('without cloud AI, returns a manual draft that keeps the image', () async {
      final scan = ScanReceipt(FakeExtractor(cloud: false), FakeEntitlements());
      final draft = (await scan(image: image, mimeType: 'image/jpeg', currency: 'PKR')).valueOrNull!;
      expect(draft.status, ReceiptStatus.manualEntry);
      expect(draft.image, image);
    });

    test('offline extraction is queued for later (FR-AI-07)', () async {
      final scan = ScanReceipt(FakeExtractor(result: const Failure(NetworkFailure())), FakeEntitlements());
      final draft = (await scan(image: image, mimeType: 'image/jpeg', currency: 'PKR')).valueOrNull!;
      expect(draft.status, ReceiptStatus.queuedOffline);
    });

    test('quota is enforced and consumed for cloud scans (BR-07)', () async {
      final entitlements = FakeEntitlements(Entitlement.free(fixedNow).copyWith(scansUsed: 14));
      final extractor = FakeExtractor();
      final scan = ScanReceipt(extractor, entitlements);

      expect((await scan(image: image, mimeType: 'image/jpeg', currency: 'PKR')).isSuccess, isTrue);
      final second = await scan(image: image, mimeType: 'image/jpeg', currency: 'PKR');
      expect(second.failureOrNull, isA<QuotaExceeded>());
      expect(extractor.calls, 1);
    });

    test('when cloud quota is used up, the device reads the receipt for free', () async {
      final entitlements = FakeEntitlements(Entitlement.free(fixedNow).copyWith(scansUsed: 15));
      final extractor = FakeExtractor(onDevice: true);
      final draft = (await ScanReceipt(extractor, entitlements)(
        image: image,
        mimeType: 'image/jpeg',
        currency: 'PKR',
      )).valueOrNull!;
      expect(extractor.lastAllowCloud, isFalse);
      expect(draft.engine, ExtractionEngine.onDevice);
      expect(entitlements.value.scansUsed, 15);
    });

    test('local mode reads on the device without an account', () async {
      final extractor = FakeExtractor(cloud: false, onDevice: true);
      final scan = ScanReceipt(extractor, FakeEntitlements());
      expect(scan.isAiAvailable, isTrue);
      final draft = (await scan(image: image, mimeType: 'image/jpeg', currency: 'PKR')).valueOrNull!;
      expect(draft.merchant, 'Shop');
      expect(draft.image, image);
    });
  });

  group('Presenters (MVP)', () {
    const user = AppUser(id: 'u1', displayName: 'Ayesha Khan', isLocal: true);
    const household = Household(id: 'local-u1', name: 'My vault', role: MemberRole.owner, isLocal: true);

    ProviderContainer container(List<Receipt> receipts, {List<dynamic> extra = const []}) {
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => fixedNow),
          currentUserProvider.overrideWith((ref) => Stream.value(user)),
          activeHouseholdProvider.overrideWith((ref) async => household),
          householdReceiptsProvider.overrideWith((ref) => Stream.value(receipts)),
          settingsProvider.overrideWith((ref) => Stream.value(const AppSettings(onboardingDone: true))),
          ...extra.cast(),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<VaultUiState> settle(ProviderContainer c) async {
      c.listen(vaultPresenterProvider, (_, _) {});
      await c.read(householdReceiptsProvider.future);
      await c.read(activeHouseholdProvider.future);
      await c.read(currentUserProvider.future);
      await Future<void>.delayed(Duration.zero);
      return c.read(vaultPresenterProvider);
    }

    test('VaultPresenter shows the empty state for a new vault', () async {
      final state = await settle(container(const []));
      expect(state, isA<VaultEmpty>());
      expect((state as VaultEmpty).greetingName, 'Ayesha');
    });

    test('VaultPresenter filters by search and status', () async {
      final c = container([
        receipt(
          id: 'a',
          merchant: 'Mega Electronics',
          items: [item(name: 'Earbuds', months: 12)],
        ),
        receipt(id: 'b', merchant: 'FreshMart', category: Category.groceries, totalMinor: 1125000),
        receipt(id: 'c', merchant: 'Urban Wear', status: ReceiptStatus.needsReview),
      ]);
      final state = await settle(c) as VaultData;
      expect(state.cards, hasLength(3));
      expect(state.summary.receiptCount, 3);

      final presenter = c.read(vaultPresenterProvider.notifier);
      presenter.search('earbuds');
      expect((c.read(vaultPresenterProvider) as VaultData).cards.single.id, 'a');

      presenter.clearFilters();
      presenter.selectStatus(StatusFilter.drafts);
      expect((c.read(vaultPresenterProvider) as VaultData).cards.single.id, 'c');

      presenter.clearFilters();
      presenter.search('11250');
      expect((c.read(vaultPresenterProvider) as VaultData).cards.single.id, 'b');
    });

    test('ScanPresenter turns a captured photo into a draft', () async {
      final settings = FakeSettingsRepository();
      final c = container(
        const [],
        extra: [
          settingsRepositoryProvider.overrideWithValue(settings),
          entitlementProvider.overrideWith((ref) => Stream.value(Entitlement.free(fixedNow))),
          imageCaptureProvider.overrideWithValue(
            FakeImageCapture(CapturedImage(Uint8List.fromList([9, 9]), 'image/jpeg')),
          ),
          scanReceiptProvider.overrideWithValue(ScanReceipt(FakeExtractor(), FakeEntitlements())),
        ],
      );
      c.listen(scanPresenterProvider, (_, _) {});

      expect(c.read(scanPresenterProvider), isA<ScanIdle>());
      await c.read(scanPresenterProvider.notifier).capture(fromCamera: true);
      final state = c.read(scanPresenterProvider);
      expect(state, isA<ScanReady>());
      expect((state as ScanReady).draft.merchant, 'Shop');
      expect(state.draft.image, [9, 9]);
    });

    test('ClaimPackPresenter stays Ready after the quota updates', () async {
      final repo = FakeReceiptRepository();
      await repo.save(receipt(items: [item(months: 12)]));
      final entitlements = FakeEntitlements();
      final c = container(
        const [],
        extra: [
          entitlementProvider.overrideWith((ref) => entitlements.watch()),
          generateClaimPackProvider.overrideWithValue(
            GenerateClaimPack(repo, entitlements, _FakeRenderer(), () => fixedNow),
          ),
          fileExporterProvider.overrideWithValue(_NoopExporter()),
        ],
      );
      final provider = claimPackPresenterProvider('r1');
      c.listen(provider, (_, _) {});
      await c.read(provider.notifier).generate(issue: 'Screen flickers after two weeks of use.');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(provider), isA<ClaimReady>());
      expect(entitlements.value.claimPacksUsed, 1);
    });
  });
}

class _FakeRenderer implements ClaimPackRenderer {
  @override
  Future<Uint8List> render(ClaimPackRequest request) async => Uint8List.fromList('%PDF'.codeUnits);
}

class _NoopExporter implements FileExporter {
  @override
  Future<void> share({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
  }) async {}
}
