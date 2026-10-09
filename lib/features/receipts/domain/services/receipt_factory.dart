import '../../../../core/domain/clock.dart';
import '../../../../core/domain/money.dart';
import '../entities/receipt.dart';
import '../entities/receipt_draft.dart';

/// Builds or updates the aggregate from an extraction draft.
class ReceiptFactory {
  const ReceiptFactory._();

  static Receipt fromDraft(
    ReceiptDraft draft, {
    required String id,
    required String householdId,
    required String userId,
    required DateTime now,
    required String Function() newId,
    String? attachmentId,
  }) {
    final base = Receipt(
      id: id,
      householdId: householdId,
      createdBy: userId,
      merchant: '',
      purchaseDate: dateOnly(now),
      total: Money.zero(draft.currency),
      category: Category.other,
      status: draft.status,
      syncState: SyncState.localOnly,
      createdAt: now,
      updatedAt: now,
      attachments: [
        if (attachmentId != null && draft.image != null)
          Attachment(
            id: attachmentId,
            kind: AttachmentKind.receipt,
            mimeType: draft.imageMimeType ?? 'image/jpeg',
            sizeBytes: draft.image!.length,
          ),
      ],
    );
    return applyDraft(base, draft, newId: newId, now: now);
  }

  /// Copies extracted values onto [receipt]; existing values are kept where
  /// the draft has nothing.
  static Receipt applyDraft(
    Receipt receipt,
    ReceiptDraft draft, {
    required String Function() newId,
    required DateTime now,
  }) {
    final currency = draft.currency;
    final purchase = draft.purchaseDate == null ? receipt.purchaseDate : dateOnly(draft.purchaseDate!);
    final items = draft.items.isEmpty
        ? receipt.items
        : [
            for (final d in draft.items)
              LineItem(
                id: newId(),
                name: d.name,
                quantity: d.quantity < 1 ? 1 : d.quantity,
                unitPrice: Money(d.unitPriceMinor ?? 0, currency),
                serialNumber: d.serialNumber,
                warranty: _warrantyFor(d, draft.suggestedWarrantyMonths),
              ),
          ];
    return receipt.copyWith(
      merchant: draft.merchant?.trim().isNotEmpty == true ? draft.merchant!.trim() : receipt.merchant,
      purchaseDate: purchase.isAfter(dateOnly(now)) ? dateOnly(now) : purchase,
      total: Money(draft.totalMinor ?? receipt.total.minor, currency),
      category: draft.category ?? receipt.category,
      paymentMethod: draft.paymentMethod ?? receipt.paymentMethod,
      returnDays: draft.suggestedReturnDays ?? receipt.returnDays,
      items: [for (final i in items) i.copyWith(unitPrice: Money(i.unitPrice.minor, currency))],
      ocrText: draft.ocrText ?? receipt.ocrText,
      status: draft.status,
    );
  }

  static Warranty? _warrantyFor(DraftItem item, int? receiptWide) {
    final months = item.warrantyMonths ?? receiptWide ?? 0;
    if (months <= 0) return null;
    return Warranty(months: months.clamp(1, 120), isExtended: item.isExtendedWarranty);
  }
}
