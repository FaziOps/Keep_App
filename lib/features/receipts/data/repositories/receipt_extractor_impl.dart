import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/failures.dart';
import '../../../../core/result.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_draft.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../datasources/extraction_remote_data_source.dart';
import '../datasources/on_device_ocr_data_source.dart';
import '../parsing/receipt_text_parser.dart';

/// Reads receipts with cloud AI when allowed (most accurate) and falls back
/// to on-device text recognition, so scanning works offline and without an
/// account.
class ReceiptExtractorImpl implements ReceiptExtractor {
  const ReceiptExtractorImpl({
    ExtractionRemoteDataSource? remote,
    OnDeviceOcrDataSource? onDevice,
    DateTime Function()? clock,
  }) : _remote = remote,
       _onDevice = onDevice,
       _clock = clock ?? DateTime.now;

  /// Null in local-only mode.
  final ExtractionRemoteDataSource? _remote;
  final OnDeviceOcrDataSource? _onDevice;
  final DateTime Function() _clock;

  @override
  bool get isCloudAvailable => _remote?.hasSession ?? false;

  @override
  bool get isOnDeviceAvailable => _onDevice?.isSupported ?? false;

  @override
  Future<Result<ReceiptDraft>> extract({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
    bool allowCloud = true,
  }) async {
    if (allowCloud && isCloudAvailable) {
      final cloud = await _extractInCloud(image: image, mimeType: mimeType, currency: currency, locale: locale);
      // Device reading rescues offline and service errors, not auth/quota/unreadable photos.
      final fallBack = switch (cloud) {
        Failure(failure: NetworkFailure()) => true,
        Failure(failure: ExtractionFailure()) => true,
        _ => false,
      };
      if (!fallBack || !isOnDeviceAvailable) return cloud;
    }
    if (isOnDeviceAvailable) return _extractOnDevice(image, currency);
    return const Failure(CloudUnavailableFailure());
  }

  Future<Result<ReceiptDraft>> _extractOnDevice(Uint8List image, String currency) async {
    try {
      final lines = await _onDevice!.recognize(image);
      if (lines.isEmpty) {
        return const Failure(ExtractionFailure('No text found. Try again in better light with the receipt flat.'));
      }
      final draft = ReceiptTextParser.parse(lines, currencyHint: currency, now: _clock());
      if (!ReceiptTextParser.looksLikeReceipt(draft)) {
        return const Failure(ExtractionFailure('This does not look like a receipt. Please fill in the details.'));
      }
      return Success(draft.copyWith(message: 'Filled in from your photo. Check the highlighted fields.'));
    } catch (_) {
      return const Failure(ExtractionFailure('Could not read this photo. Please fill in the details.'));
    }
  }

  Future<Result<ReceiptDraft>> _extractInCloud({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
  }) async {
    final remote = _remote!;
    try {
      final json = await remote
          .extract(image: image, mimeType: mimeType, currency: currency, locale: locale)
          .timeout(const Duration(seconds: 30));
      return Success(parse(json, fallbackCurrency: currency));
    } on FunctionException catch (e) {
      return Failure(switch (e.status) {
        401 => const AuthFailure('Your session expired. Please sign in again.'),
        402 => const QuotaExceeded(QuotaKind.aiScan),
        413 => const ExtractionFailure('This image is too large. Try cropping it.'),
        422 => const ExtractionFailure('We could not read this receipt. Please fill in the details.'),
        429 => const ExtractionFailure('Too many scans in a short time. Please wait a moment.'),
        _ => const ExtractionFailure(),
      });
    } on FormatException {
      return const Failure(ExtractionFailure());
    } on TypeError {
      return const Failure(ExtractionFailure());
    } catch (_) {
      // Socket/client errors and timeouts: treat as offline (FR-AI-07).
      return const Failure(NetworkFailure());
    }
  }

  /// Maps the Edge Function response (see supabase/functions/extract-receipt).
  static ReceiptDraft parse(Map<String, dynamic> j, {required String fallbackCurrency}) {
    Map<String, dynamic> field(String key) => (j[key] as Map?)?.cast<String, dynamic>() ?? const {};
    double conf(String key) => (field(key)['confidence'] as num?)?.toDouble() ?? 0;

    final dateRaw = field('purchase_date')['value'] as String?;
    final items = [
      for (final raw in (j['items'] as List? ?? const []))
        if (raw is Map)
          DraftItem(
            name: (raw['name'] as String?)?.trim() ?? '',
            quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
            unitPriceMinor: (raw['unit_price_minor'] as num?)?.toInt(),
            serialNumber: raw['serial_number'] as String?,
            confidence: (raw['confidence'] as num?)?.toDouble() ?? 0.5,
          ),
    ].where((i) => i.name.isNotEmpty).toList();

    return ReceiptDraft(
      status: ReceiptStatus.needsReview,
      engine: ExtractionEngine.cloudAi,
      merchant: field('merchant')['value'] as String?,
      purchaseDate: dateRaw == null ? null : DateTime.tryParse(dateRaw),
      totalMinor: (field('total')['value_minor'] as num?)?.toInt(),
      currency: (j['currency'] as String?)?.toUpperCase() ?? fallbackCurrency,
      category: field('category')['value'] == null ? null : Category.parse(field('category')['value'] as String?),
      paymentMethod: j['payment_method'] as String?,
      items: items,
      suggestedWarrantyMonths: (j['suggested_warranty_months'] as num?)?.toInt(),
      suggestedReturnDays: (j['suggested_return_days'] as num?)?.toInt(),
      confidence: {
        'merchant': conf('merchant'),
        'purchaseDate': conf('purchase_date'),
        'total': conf('total'),
        'category': conf('category'),
        if (items.isNotEmpty) 'items': items.map((i) => i.confidence).reduce((a, b) => a < b ? a : b),
      },
    );
  }
}
