import 'dart:typed_data';

import 'receipt.dart';

/// Fields below this confidence must be confirmed by the user (BR-11).
const kLowConfidenceThreshold = 0.7;

/// Which reader produced a draft. Only cloud AI scans count against the
/// monthly quota (BR-07); on-device reading is unlimited.
enum ExtractionEngine { none, onDevice, cloudAi }

class DraftItem {
  const DraftItem({
    required this.name,
    this.quantity = 1,
    this.unitPriceMinor,
    this.serialNumber,
    this.warrantyMonths,
    this.isExtendedWarranty = false,
    this.confidence = 1,
  });

  final String name;
  final int quantity;
  final int? unitPriceMinor;
  final String? serialNumber;

  /// Item-specific coverage (e.g. a "2-Yr Protection Plan" line); falls back
  /// to the receipt-wide suggestion when null.
  final int? warrantyMonths;
  final bool isExtendedWarranty;
  final double confidence;
}

/// Result of extraction (or an empty shell for manual entry). Values are
/// nullable because the reader may not find them.
class ReceiptDraft {
  const ReceiptDraft({
    required this.currency,
    required this.status,
    this.merchant,
    this.purchaseDate,
    this.totalMinor,
    this.category,
    this.paymentMethod,
    this.items = const [],
    this.suggestedWarrantyMonths,
    this.suggestedReturnDays,
    this.confidence = const {},
    this.engine = ExtractionEngine.none,
    this.ocrText,
    this.image,
    this.imageMimeType,
    this.message,
  });

  factory ReceiptDraft.manual({
    required String currency,
    Uint8List? image,
    String? imageMimeType,
    String? message,
    ReceiptStatus status = ReceiptStatus.manualEntry,
  }) => ReceiptDraft(
    currency: currency,
    status: status,
    purchaseDate: DateTime.now(),
    image: image,
    imageMimeType: imageMimeType,
    message: message,
  );

  final String? merchant;
  final DateTime? purchaseDate;
  final int? totalMinor;
  final String currency;
  final Category? category;
  final String? paymentMethod;
  final List<DraftItem> items;
  final int? suggestedWarrantyMonths;
  final int? suggestedReturnDays;

  /// Field key -> confidence 0.0–1.0. Keys: merchant, purchaseDate, total,
  /// category, items.
  final Map<String, double> confidence;
  final ExtractionEngine engine;

  /// Raw recognised text, kept for search and troubleshooting.
  final String? ocrText;
  final Uint8List? image;
  final String? imageMimeType;
  final ReceiptStatus status;

  /// Optional explanation shown to the user (e.g. why extraction failed).
  final String? message;

  bool isLowConfidence(String field) => confidence.containsKey(field) && confidence[field]! < kLowConfidenceThreshold;

  Set<String> get lowConfidenceFields => {
    for (final e in confidence.entries)
      if (e.value < kLowConfidenceThreshold) e.key,
  };

  ReceiptDraft copyWith({Uint8List? image, String? imageMimeType, String? message, ExtractionEngine? engine}) =>
      ReceiptDraft(
        currency: currency,
        status: status,
        merchant: merchant,
        purchaseDate: purchaseDate,
        totalMinor: totalMinor,
        category: category,
        paymentMethod: paymentMethod,
        items: items,
        suggestedWarrantyMonths: suggestedWarrantyMonths,
        suggestedReturnDays: suggestedReturnDays,
        confidence: confidence,
        engine: engine ?? this.engine,
        ocrText: ocrText,
        image: image ?? this.image,
        imageMimeType: imageMimeType ?? this.imageMimeType,
        message: message ?? this.message,
      );

  ReceiptDraft withImage(Uint8List bytes, String mimeType) => copyWith(image: bytes, imageMimeType: mimeType);
}
