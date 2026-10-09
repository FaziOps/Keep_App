import '../../../../core/domain/money.dart';
import '../../domain/entities/receipt.dart';

/// Maps the Receipt aggregate to JSON for the local store and for the
/// `upsert_receipt` / `pull_changes` database functions.
class ReceiptModel {
  const ReceiptModel._();

  static Map<String, dynamic> toJson(Receipt r) => {
    'id': r.id,
    'household_id': r.householdId,
    'created_by': r.createdBy,
    'merchant': r.merchant,
    'purchase_date': _date(r.purchaseDate),
    'total_minor': r.total.minor,
    'currency': r.total.currency,
    'category': r.category.name,
    'status': r.status.name,
    'sync_state': r.syncState.name,
    'return_days': r.returnDays,
    'payment_method': r.paymentMethod,
    'notes': r.notes,
    'ocr_text': r.ocrText,
    'created_at': r.createdAt.toUtc().toIso8601String(),
    'updated_at': r.updatedAt.toUtc().toIso8601String(),
    'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
    'items': [
      for (final i in r.items)
        {
          'id': i.id,
          'name': i.name,
          'quantity': i.quantity,
          'unit_price_minor': i.unitPrice.minor,
          'serial_number': i.serialNumber,
          'warranty_months': i.warranty?.months,
          'warranty_provider': i.warranty?.provider,
          'warranty_extended': i.warranty?.isExtended ?? false,
        },
    ],
    'attachments': [
      for (final a in r.attachments)
        {
          'id': a.id,
          'kind': a.kind.name,
          'mime_type': a.mimeType,
          'size_bytes': a.sizeBytes,
          'storage_path': a.remotePath,
        },
    ],
  };

  static Receipt fromJson(Map<String, dynamic> j, {SyncState? syncState}) {
    final currency = j['currency'] as String;
    return Receipt(
      id: j['id'] as String,
      householdId: j['household_id'] as String,
      createdBy: j['created_by'] as String? ?? '',
      merchant: j['merchant'] as String? ?? '',
      purchaseDate: DateTime.parse(j['purchase_date'] as String),
      total: Money((j['total_minor'] as num).toInt(), currency),
      category: Category.parse(j['category'] as String?),
      status: ReceiptStatus.values.byName(j['status'] as String? ?? 'confirmed'),
      syncState: syncState ?? SyncState.values.byName(j['sync_state'] as String? ?? 'synced'),
      returnDays: (j['return_days'] as num?)?.toInt(),
      paymentMethod: j['payment_method'] as String?,
      notes: j['notes'] as String?,
      ocrText: j['ocr_text'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      deletedAt: j['deleted_at'] == null ? null : DateTime.parse(j['deleted_at'] as String).toLocal(),
      items: [
        for (final raw in (j['items'] as List? ?? const [])) _item((raw as Map).cast<String, dynamic>(), currency),
      ],
      attachments: [
        for (final raw in (j['attachments'] as List? ?? const [])) _attachment((raw as Map).cast<String, dynamic>()),
      ],
    );
  }

  static LineItem _item(Map<String, dynamic> j, String currency) {
    final months = (j['warranty_months'] as num?)?.toInt();
    return LineItem(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: Money((j['unit_price_minor'] as num?)?.toInt() ?? 0, currency),
      serialNumber: j['serial_number'] as String?,
      warranty: months == null
          ? null
          : Warranty(
              months: months,
              provider: j['warranty_provider'] as String?,
              isExtended: j['warranty_extended'] as bool? ?? false,
            ),
    );
  }

  static Attachment _attachment(Map<String, dynamic> j) => Attachment(
    id: j['id'] as String,
    kind: AttachmentKind.values.byName(j['kind'] as String? ?? 'receipt'),
    mimeType: j['mime_type'] as String? ?? 'image/jpeg',
    sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
    remotePath: j['storage_path'] as String?,
  );

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
