/// Money as integer minor units plus an ISO-4217 currency code.
/// Doubles are never used to store amounts.
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  factory Money.fromMajor(num major, String currency) => Money((major * 100).round(), currency);

  const Money.zero(this.currency) : minor = 0;

  final int minor;
  final String currency;

  double get major => minor / 100;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator *(int factor) => Money(minor * factor, currency);

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Cannot combine $currency with ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency ${major.toStringAsFixed(2)}';
}

/// Currencies offered in the app. Any valid ISO-4217 code is accepted by the
/// domain; this list only drives pickers.
const kSupportedCurrencies = ['PKR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'INR', 'CAD', 'AUD', 'BDT', 'TRY'];

bool isValidCurrencyCode(String code) => RegExp(r'^[A-Z]{3}$').hasMatch(code);
