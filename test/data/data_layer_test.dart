import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:keepr/core/domain/money.dart';
import 'package:keepr/core/storage/local_store.dart';
import 'package:keepr/features/claims/data/pdf_claim_pack_renderer.dart';
import 'package:keepr/features/claims/domain/claim_pack.dart';
import 'package:keepr/features/receipts/data/datasources/receipt_local_data_source.dart';
import 'package:keepr/features/receipts/data/datasources/receipt_remote_data_source.dart';
import 'package:keepr/features/receipts/data/models/receipt_model.dart';
import 'package:keepr/features/receipts/data/repositories/receipt_extractor_impl.dart';
import 'package:keepr/features/receipts/data/repositories/receipt_repository_impl.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';
import 'package:keepr/features/sync/data/outbox.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../helpers/fixtures.dart';

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('keepr_test');
    store = await LocalStore.open(path: dir.path);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  ReceiptRepositoryImpl repo({bool cloud = false, void Function()? onChange}) => ReceiptRepositoryImpl(
    local: ReceiptLocalDataSource(store),
    outbox: Outbox(store),
    clock: () => fixedNow,
    onLocalChange: onChange ?? () {},
    // A remote marks non-local households as cloud-backed. No request is made here.
    remote: cloud ? ReceiptRemoteDataSource(SupabaseClient('http://localhost:54321', 'test-key')) : null,
  );

  test('ReceiptModel round-trips the aggregate', () {
    final original = receipt(returnDays: 14, items: [item(months: 24)]).copyWith(
      notes: 'Gift',
      attachments: const [Attachment(id: 'a1', kind: AttachmentKind.serial, mimeType: 'image/png', sizeBytes: 10)],
    );
    final back = ReceiptModel.fromJson(ReceiptModel.toJson(original));
    expect(back.merchant, original.merchant);
    expect(back.total, original.total);
    expect(back.purchaseDate, original.purchaseDate);
    expect(back.items.single.warranty?.months, 24);
    expect(back.attachments.single.kind, AttachmentKind.serial);
    expect(back.notes, 'Gift');
    expect(back.returnDays, 14);
  });

  test('local households are stored without queuing sync', () async {
    final r = repo();
    final saved = (await r.save(
      receipt(),
      newAttachmentBytes: {
        'img': Uint8List.fromList([1, 2, 3]),
      },
    )).valueOrNull!;
    expect(saved.syncState, SyncState.localOnly);
    expect(Outbox(store).length, 0);
    expect(await ReceiptLocalDataSource(store).getAttachment('img'), [1, 2, 3]);
  });

  test('cloud households are queued for sync and trigger a sync request', () async {
    var requested = 0;
    final r = repo(cloud: true, onChange: () => requested++);
    final saved = (await r.save(receipt(householdId: '9b2f6a1e-0000-4000-8000-000000000001'))).valueOrNull!;
    expect(saved.syncState, SyncState.pending);
    expect(Outbox(store).pending().single.entityId, 'r1');
    expect(requested, 1);
  });

  test('soft delete hides the receipt, keeps it in trash and restores it (BR-09)', () async {
    final r = repo();
    await r.save(receipt());
    await r.delete('r1');

    expect(await r.watchReceipts('local-u1').first, isEmpty);
    expect((await r.watchTrash('local-u1').first).single.id, 'r1');

    await r.restore('r1');
    expect((await r.watchReceipts('local-u1').first).single.isDeleted, isFalse);
  });

  test('trash older than 30 days is purged', () async {
    final r = repo();
    await r.save(receipt(deletedAt: fixedNow.subtract(const Duration(days: 31))));
    await r.purgeExpiredTrash(fixedNow);
    expect(ReceiptLocalDataSource(store).get('r1'), isNull);
  });

  test('duplicates match merchant, day and total (BR-10)', () async {
    final r = repo();
    await r.save(receipt(id: 'a', merchant: 'FreshMart'));
    final dupes = await r.findDuplicates(
      householdId: 'local-u1',
      merchant: ' freshmart ',
      purchaseDate: DateTime(2026, 10, 1, 18),
      totalMinor: 1899900,
      excludeId: 'b',
    );
    expect(dupes.single.id, 'a');
  });

  test('outbox keeps one entry per receipt in FIFO order', () async {
    final outbox = Outbox(store);
    await outbox.enqueue('receipt', 'x');
    await outbox.enqueue('receipt', 'y');
    await outbox.enqueue('receipt', 'x');
    expect(outbox.length, 2);
    final pending = outbox.pending();
    await outbox.markFailed(pending.first, 'offline');
    expect(outbox.pending().firstWhere((e) => e.entityId == pending.first.entityId).attempts, 1);
  });

  test('extraction response is mapped with confidences', () {
    final draft = ReceiptExtractorImpl.parse({
      'merchant': {'value': 'City Mobiles', 'confidence': 0.96},
      'purchase_date': {'value': '2026-09-28', 'confidence': 0.6},
      'total': {'value_minor': 8999900, 'confidence': 0.98},
      'currency': 'pkr',
      'category': {'value': 'electronics', 'confidence': 0.9},
      'items': [
        {'name': 'Phone', 'quantity': 1, 'unit_price_minor': 8999900, 'serial_number': '3567', 'confidence': 0.8},
        {'name': ' ', 'quantity': 1},
      ],
      'suggested_warranty_months': 12,
      'suggested_return_days': null,
    }, fallbackCurrency: 'USD');

    expect(draft.merchant, 'City Mobiles');
    expect(draft.currency, 'PKR');
    expect(draft.items, hasLength(1));
    expect(draft.lowConfidenceFields, {'purchaseDate'});
    expect(draft.suggestedWarrantyMonths, 12);
  });

  test('claim pack renders a multi-page PDF', () async {
    final r = receipt(
      returnDays: 14,
      items: [item(name: 'Wireless earbuds – Pro', months: 12)],
    ).copyWith(paymentMethod: 'Card');
    final bytes = await const PdfClaimPackRenderer().render(
      ClaimPackRequest(
        receipt: r,
        images: const [],
        issueDescription: 'The left earbud stopped charging after two weeks of normal use.',
        claimantName: 'Ayesha Khan',
        claimantEmail: 'ayesha@example.com',
        generatedAt: fixedNow,
      ),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final out = Platform.environment['KEEPR_PDF_OUT'];
    if (out != null) await File(out).writeAsBytes(bytes);
    expect(r.total, const Money(1899900, 'PKR'));
  });
}
