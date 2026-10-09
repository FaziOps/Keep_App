import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/domain/clock.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../../../core/services/image_capture.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_draft.dart';
import '../../domain/services/receipt_factory.dart';

/// Route argument: either a fresh draft from the scanner or an existing id.
class ReviewArgs {
  const ReviewArgs.fromDraft(ReceiptDraft this.draft) : receiptId = null;
  const ReviewArgs.edit(String this.receiptId) : draft = null;

  final ReceiptDraft? draft;
  final String? receiptId;

  @override
  bool operator ==(Object other) =>
      other is ReviewArgs && other.receiptId == receiptId && identical(other.draft, draft);

  @override
  int get hashCode => Object.hash(receiptId, draft == null ? 0 : identityHashCode(draft));
}

enum BannerKind { aiFilled, offline, failed, manual }

class ReviewForm {
  const ReviewForm({
    required this.receipt,
    required this.isNew,
    required this.canEdit,
    this.newImages = const {},
    this.unconfirmed = const {},
    this.errors = const {},
    this.banner,
    this.bannerKind,
    this.saving = false,
    this.duplicates = const [],
    this.duplicatesAcknowledged = false,
    this.savedId,
    this.error,
  });

  final Receipt receipt;
  final bool isNew;
  final bool canEdit;
  final Map<String, Uint8List> newImages;

  /// Low-confidence fields the user has not checked yet (BR-11).
  final Set<String> unconfirmed;
  final Map<String, String> errors;
  final String? banner;
  final BannerKind? bannerKind;
  final bool saving;
  final List<Receipt> duplicates;
  final bool duplicatesAcknowledged;

  /// Set once saved; the View navigates away.
  final String? savedId;
  final String? error;

  bool get canSaveForLater => isNew && receipt.status == ReceiptStatus.queuedOffline;

  Money get itemsTotal => receipt.items.fold(Money.zero(receipt.total.currency), (s, i) => s + i.total);

  ReviewForm copyWith({
    Receipt? receipt,
    Map<String, Uint8List>? newImages,
    Set<String>? unconfirmed,
    Map<String, String>? errors,
    bool? saving,
    List<Receipt>? duplicates,
    bool? duplicatesAcknowledged,
    String? savedId,
    String? error,
  }) => ReviewForm(
    receipt: receipt ?? this.receipt,
    isNew: isNew,
    canEdit: canEdit,
    newImages: newImages ?? this.newImages,
    unconfirmed: unconfirmed ?? this.unconfirmed,
    errors: errors ?? this.errors,
    banner: banner,
    bannerKind: bannerKind,
    saving: saving ?? this.saving,
    duplicates: duplicates ?? this.duplicates,
    duplicatesAcknowledged: duplicatesAcknowledged ?? this.duplicatesAcknowledged,
    savedId: savedId ?? this.savedId,
    error: error,
  );
}

/// Presenter for the review / edit form (SSD-3).
class ReviewPresenter extends AsyncNotifier<ReviewForm> {
  ReviewPresenter(this.args);
  final ReviewArgs args;

  String _newId() => ref.read(idGeneratorProvider)();
  DateTime _now() => ref.read(clockProvider)();

  @override
  Future<ReviewForm> build() async {
    final household = await ref.read(activeHouseholdProvider.future);
    final user = ref.read(currentUserProvider).value;
    if (household == null || user == null) throw const AuthFailure('Not signed in.');
    final canEdit = household.role.canEdit;

    final draft = args.draft;
    if (draft != null) {
      final attachmentId = draft.image == null ? null : _newId();
      final receipt = ReceiptFactory.fromDraft(
        draft,
        id: _newId(),
        householdId: household.id,
        userId: user.id,
        now: _now(),
        newId: _newId,
        attachmentId: attachmentId,
      );
      final kind = switch (draft.status) {
        ReceiptStatus.needsReview => BannerKind.aiFilled,
        ReceiptStatus.queuedOffline => BannerKind.offline,
        ReceiptStatus.extractionFailed => BannerKind.failed,
        _ => BannerKind.manual,
      };
      return ReviewForm(
        receipt: receipt,
        isNew: true,
        canEdit: canEdit,
        newImages: {?attachmentId: draft.image!},
        unconfirmed: draft.lowConfidenceFields.where((f) => f != 'items').toSet(),
        banner:
            draft.message ??
            (kind == BannerKind.aiFilled ? 'We filled in what we found. Check the highlighted fields.' : null),
        bannerKind: kind,
      );
    }

    final result = await ref.read(receiptRepositoryProvider).getReceipt(args.receiptId!);
    return switch (result) {
      Success(:final value) => ReviewForm(
        receipt: value,
        isNew: false,
        canEdit: canEdit,
        banner: value.status == ReceiptStatus.needsReview
            ? 'Keepr read this receipt while you were away. Check the details and save.'
            : null,
        bannerKind: value.status == ReceiptStatus.needsReview ? BannerKind.aiFilled : null,
      ),
      Failure(:final failure) => throw failure,
    };
  }

  void _edit(Receipt Function(Receipt r) change, {String? field}) {
    final form = state.value;
    if (form == null) return;
    state = AsyncData(
      form.copyWith(
        receipt: change(form.receipt),
        unconfirmed: field == null ? null : ({...form.unconfirmed}..remove(field)),
        errors: field == null ? null : ({...form.errors}..remove(field)),
        duplicatesAcknowledged: false,
        duplicates: const [],
      ),
    );
  }

  void setMerchant(String v) => _edit((r) => r.copyWith(merchant: v), field: 'merchant');
  void setPurchaseDate(DateTime v) => _edit((r) => r.copyWith(purchaseDate: dateOnly(v)), field: 'purchaseDate');
  void setTotal(int? minor) => _edit((r) => r.copyWith(total: Money(minor ?? 0, r.total.currency)), field: 'total');
  void setCategory(Category c) => _edit((r) => r.copyWith(category: c), field: 'category');
  void setPaymentMethod(String v) => _edit((r) => r.copyWith(paymentMethod: v.trim().isEmpty ? null : v.trim()));
  void setNotes(String v) => _edit((r) => r.copyWith(notes: v.trim().isEmpty ? null : v));
  void setReturnDays(int? days) => _edit((r) => r.copyWith(returnDays: days), field: 'returnDays');

  void setCurrency(String code) => _edit(
    (r) => r.copyWith(
      total: Money(r.total.minor, code),
      items: [for (final i in r.items) i.copyWith(unitPrice: Money(i.unitPrice.minor, code))],
    ),
    field: 'currency',
  );

  void confirmField(String field) {
    final form = state.value;
    if (form == null) return;
    state = AsyncData(form.copyWith(unconfirmed: {...form.unconfirmed}..remove(field)));
  }

  LineItem newItem() => LineItem(
    id: _newId(),
    name: '',
    quantity: 1,
    unitPrice: Money.zero(state.value?.receipt.total.currency ?? 'PKR'),
  );

  void upsertItem(LineItem item) => _edit((r) {
    final items = [...r.items];
    final index = items.indexWhere((i) => i.id == item.id);
    index == -1 ? items.add(item) : items[index] = item;
    final itemsTotal = items.fold(Money.zero(r.total.currency), (s, i) => s + i.total);
    return r.copyWith(items: items, total: r.total.minor == 0 ? itemsTotal : r.total);
  });

  void removeItem(String itemId) => _edit((r) => r.copyWith(items: r.items.where((i) => i.id != itemId).toList()));

  void useItemsTotal() => _edit((r) => r.copyWith(total: state.value!.itemsTotal), field: 'total');

  Future<void> addPhoto(AttachmentKind kind, {required bool fromCamera}) async {
    final CapturedImage? image;
    try {
      image = await ref.read(imageCaptureProvider).capture(fromCamera: fromCamera);
    } catch (_) {
      return;
    }
    final form = state.value;
    if (image == null || form == null || !ref.mounted) return;
    final id = _newId();
    state = AsyncData(
      form.copyWith(
        newImages: {...form.newImages, id: image.bytes},
        receipt: form.receipt.copyWith(
          attachments: [
            ...form.receipt.attachments,
            Attachment(id: id, kind: kind, mimeType: image.mimeType, sizeBytes: image.bytes.length),
          ],
        ),
      ),
    );
  }

  void removeAttachment(String id) {
    final form = state.value;
    if (form == null) return;
    state = AsyncData(
      form.copyWith(
        newImages: {...form.newImages}..remove(id),
        receipt: form.receipt.copyWith(attachments: form.receipt.attachments.where((a) => a.id != id).toList()),
      ),
    );
  }

  /// Confirms the receipt (BR-05, BR-06, BR-10, BR-11).
  Future<void> save() async {
    final form = state.value;
    if (form == null || form.saving) return;

    if (!form.duplicatesAcknowledged) {
      final duplicates = await ref.read(findDuplicatesProvider)(form.receipt);
      if (duplicates.isNotEmpty) {
        state = AsyncData(form.copyWith(duplicates: duplicates));
        return;
      }
    }
    state = AsyncData(form.copyWith(saving: true));
    await _ensureNotificationPermission();
    final result = await ref
        .read(saveReceiptProvider)
        .confirm(form.receipt, newAttachmentBytes: form.newImages, unconfirmedLowConfidence: form.unconfirmed);
    if (!ref.mounted) return;
    state = AsyncData(switch (result) {
      Success(:final value) => form.copyWith(saving: false, savedId: value.id),
      Failure(failure: ValidationFailure(:final fieldErrors)) => form.copyWith(
        saving: false,
        errors: fieldErrors,
        error: 'Please fix the highlighted fields.',
      ),
      Failure(:final failure) => form.copyWith(saving: false, error: failure.message),
    });
  }

  /// Asks for notification permission in context, the first time a receipt
  /// with reminders is saved. The OS shows the prompt only once.
  Future<void> _ensureNotificationPermission() async {
    final scheduler = ref.read(reminderSchedulerProvider);
    final enabled = ref.read(settingsRepositoryProvider).current.notificationsEnabled;
    if (!enabled || !scheduler.isSupported) return;
    try {
      await scheduler.requestPermission();
    } catch (_) {}
  }

  void acknowledgeDuplicates() {
    final form = state.value;
    if (form == null) return;
    state = AsyncData(form.copyWith(duplicatesAcknowledged: true, duplicates: const []));
    save();
  }

  /// FR-AI-07: keep the capture and extract it when back online.
  Future<void> saveForLater() async {
    final form = state.value;
    if (form == null) return;
    state = AsyncData(form.copyWith(saving: true));
    final result = await ref
        .read(saveReceiptProvider)
        .saveDraft(form.receipt.copyWith(status: ReceiptStatus.queuedOffline), newAttachmentBytes: form.newImages);
    if (!ref.mounted) return;
    state = AsyncData(
      result.fold(
        (f) => form.copyWith(saving: false, error: f.message),
        (r) => form.copyWith(saving: false, savedId: r.id),
      ),
    );
  }
}

final reviewPresenterProvider = AsyncNotifierProvider.autoDispose.family<ReviewPresenter, ReviewForm, ReviewArgs>(
  ReviewPresenter.new,
);
