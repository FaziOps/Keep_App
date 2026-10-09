import '../../../../core/domain/money.dart';

enum ReceiptStatus {
  captured,
  queuedOffline,
  processing,
  needsReview,
  extractionFailed,
  manualEntry,
  confirmed,
  archived;

  bool get isConfirmed => this == confirmed;
  bool get isDraft => this != confirmed && this != archived;
}

enum SyncState { localOnly, pending, synced, failed }

enum AttachmentKind { receipt, product, serial }

enum Category {
  electronics('Electronics'),
  appliances('Appliances'),
  furniture('Furniture'),
  clothing('Clothing'),
  groceries('Groceries'),
  health('Health'),
  home('Home'),
  travel('Travel'),
  dining('Dining'),
  other('Other');

  const Category(this.label);
  final String label;

  static Category parse(String? value) =>
      Category.values.firstWhere((c) => c.name == value?.toLowerCase(), orElse: () => Category.other);
}

const _unset = Object();

class Warranty {
  const Warranty({required this.months, this.provider, this.isExtended = false});

  /// 0–120 months (BR-06). 0 means no warranty.
  final int months;
  final String? provider;
  final bool isExtended;

  Warranty copyWith({int? months, Object? provider = _unset, bool? isExtended}) => Warranty(
    months: months ?? this.months,
    provider: provider == _unset ? this.provider : provider as String?,
    isExtended: isExtended ?? this.isExtended,
  );
}

class LineItem {
  const LineItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.serialNumber,
    this.warranty,
  });

  final String id;
  final String name;
  final int quantity;
  final Money unitPrice;
  final String? serialNumber;
  final Warranty? warranty;

  Money get total => unitPrice * quantity;
  bool get hasWarranty => (warranty?.months ?? 0) > 0;

  LineItem copyWith({
    String? name,
    int? quantity,
    Money? unitPrice,
    Object? serialNumber = _unset,
    Object? warranty = _unset,
  }) => LineItem(
    id: id,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    serialNumber: serialNumber == _unset ? this.serialNumber : serialNumber as String?,
    warranty: warranty == _unset ? this.warranty : warranty as Warranty?,
  );
}

class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.remotePath,
  });

  final String id;
  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;

  /// Path in cloud storage once uploaded; null while local only.
  final String? remotePath;

  bool get isUploaded => remotePath != null;

  Attachment withRemotePath(String path) =>
      Attachment(id: id, kind: kind, mimeType: mimeType, sizeBytes: sizeBytes, remotePath: path);

  @override
  bool operator ==(Object other) => other is Attachment && other.id == id && other.remotePath == remotePath;

  @override
  int get hashCode => Object.hash(id, remotePath);
}

/// Aggregate root of the Vault context.
class Receipt {
  const Receipt({
    required this.id,
    required this.householdId,
    required this.createdBy,
    required this.merchant,
    required this.purchaseDate,
    required this.total,
    required this.category,
    required this.status,
    required this.syncState,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.attachments = const [],
    this.returnDays,
    this.paymentMethod,
    this.notes,
    this.ocrText,
    this.deletedAt,
  });

  final String id;
  final String householdId;
  final String createdBy;
  final String merchant;
  final DateTime purchaseDate;
  final Money total;
  final Category category;
  final ReceiptStatus status;
  final SyncState syncState;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LineItem> items;
  final List<Attachment> attachments;

  /// Return window in days (0–365), null when unknown.
  final int? returnDays;
  final String? paymentMethod;
  final String? notes;
  final String? ocrText;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  List<Attachment> get receiptImages => attachments.where((a) => a.kind == AttachmentKind.receipt).toList();

  Attachment? get coverImage => receiptImages.isNotEmpty ? receiptImages.first : attachments.firstOrNull;

  Receipt copyWith({
    String? householdId,
    String? merchant,
    DateTime? purchaseDate,
    Money? total,
    Category? category,
    ReceiptStatus? status,
    SyncState? syncState,
    DateTime? updatedAt,
    List<LineItem>? items,
    List<Attachment>? attachments,
    Object? returnDays = _unset,
    Object? paymentMethod = _unset,
    Object? notes = _unset,
    Object? ocrText = _unset,
    Object? deletedAt = _unset,
  }) => Receipt(
    id: id,
    householdId: householdId ?? this.householdId,
    createdBy: createdBy,
    merchant: merchant ?? this.merchant,
    purchaseDate: purchaseDate ?? this.purchaseDate,
    total: total ?? this.total,
    category: category ?? this.category,
    status: status ?? this.status,
    syncState: syncState ?? this.syncState,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    items: items ?? this.items,
    attachments: attachments ?? this.attachments,
    returnDays: returnDays == _unset ? this.returnDays : returnDays as int?,
    paymentMethod: paymentMethod == _unset ? this.paymentMethod : paymentMethod as String?,
    notes: notes == _unset ? this.notes : notes as String?,
    ocrText: ocrText == _unset ? this.ocrText : ocrText as String?,
    deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
  );
}
