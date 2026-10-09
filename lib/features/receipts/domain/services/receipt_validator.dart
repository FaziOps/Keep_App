import '../../../../core/domain/clock.dart';
import '../../../../core/domain/money.dart';
import '../entities/receipt.dart';

/// Enforces BR-05, BR-06 and BR-11 before a receipt can be confirmed.
class ReceiptValidator {
  const ReceiptValidator._();

  static Map<String, String> validate(
    Receipt receipt, {
    required DateTime now,
    Set<String> unconfirmedLowConfidence = const {},
  }) {
    final errors = <String, String>{};

    if (receipt.merchant.trim().isEmpty) {
      errors['merchant'] = 'Enter the store or seller name';
    }
    if (dateOnly(receipt.purchaseDate).isAfter(dateOnly(now))) {
      errors['purchaseDate'] = 'Purchase date cannot be in the future';
    }
    if (receipt.total.isNegative) {
      errors['total'] = 'Total cannot be negative';
    }
    if (!isValidCurrencyCode(receipt.total.currency)) {
      errors['currency'] = 'Use a 3-letter currency code';
    }
    final days = receipt.returnDays;
    if (days != null && (days < 0 || days > 365)) {
      errors['returnDays'] = 'Return window must be 0–365 days';
    }
    for (var i = 0; i < receipt.items.length; i++) {
      final item = receipt.items[i];
      if (item.name.trim().isEmpty) {
        errors['items.$i.name'] = 'Item name is required';
      }
      if (item.quantity < 1) {
        errors['items.$i.quantity'] = 'Quantity must be at least 1';
      }
      if (item.unitPrice.isNegative) {
        errors['items.$i.price'] = 'Price cannot be negative';
      }
      final months = item.warranty?.months ?? 0;
      if (months < 0 || months > 120) {
        errors['items.$i.warranty'] = 'Warranty must be 0–120 months';
      }
    }
    for (final field in unconfirmedLowConfidence) {
      errors.putIfAbsent(field, () => 'Please check this value');
    }
    return errors;
  }
}
