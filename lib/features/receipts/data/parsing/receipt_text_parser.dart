import 'dart:math' as math;

import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_draft.dart';

/// One line of recognised text. Coordinates are normalised (0–1) with the
/// origin at the top-left of the upright image.
class OcrLine {
  const OcrLine({
    required this.text,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
    this.confidence = 1,
  });

  factory OcrLine.fromMap(Map<Object?, Object?> m) => OcrLine(
    text: (m['text'] as String?) ?? '',
    left: (m['left'] as num?)?.toDouble() ?? 0,
    top: (m['top'] as num?)?.toDouble() ?? 0,
    width: (m['width'] as num?)?.toDouble() ?? 0,
    height: (m['height'] as num?)?.toDouble() ?? 0,
    confidence: (m['confidence'] as num?)?.toDouble() ?? 1,
  );

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
  final double confidence;

  double get centerY => top + height / 2;
}

class _Amount {
  const _Amount(this.minor, this.start, this.end, {required this.hasSymbol});
  final int minor;
  final int start;
  final int end;
  final bool hasSymbol;
}

/// Turns recognised receipt text into a [ReceiptDraft] using layout and
/// keyword rules. Runs on the device, so it works offline and costs nothing.
class ReceiptTextParser {
  const ReceiptTextParser._();

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  /// Groups recognised lines into visual rows, so a product name and its
  /// price on the right end up on the same row.
  static List<String> assembleRows(List<OcrLine> lines) {
    final sorted = [...lines.where((l) => l.text.trim().isNotEmpty)]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final hasGeometry = sorted.any((l) => l.height > 0);
    if (!hasGeometry) return [for (final l in sorted) l.text.trim()];

    final rows = <List<OcrLine>>[];
    for (final line in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final rowCenter = row.map((l) => l.centerY).reduce((a, b) => a + b) / row.length;
        final rowHeight = row.map((l) => l.height).reduce(math.max);
        final tolerance = 0.55 * math.min(rowHeight, line.height > 0 ? line.height : rowHeight);
        if ((line.centerY - rowCenter).abs() <= tolerance) {
          row.add(line);
          continue;
        }
      }
      rows.add([line]);
    }
    return [
      for (final row in rows) (row..sort((a, b) => a.left.compareTo(b.left))).map((l) => l.text.trim()).join('  '),
    ];
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  static ReceiptDraft parse(List<OcrLine> lines, {required String currencyHint, required DateTime now}) =>
      parseRows(assembleRows(lines), currencyHint: currencyHint, now: now);

  static ReceiptDraft parseRows(List<String> rows, {required String currencyHint, required DateTime now}) {
    final text = rows.join('\n');
    final lower = text.toLowerCase();
    final currency = _currency(text, currencyHint);

    final totals = _totals(rows);
    final items = _items(rows, totals.firstSummaryRow);
    final itemsSum = items.fold<int>(0, (s, i) => s + (i.unitPriceMinor ?? 0) * i.quantity);
    final date = _date(rows, now, currency);
    final merchant = _merchant(rows);
    final category = _category(lower);
    final generalWarranty = _generalWarrantyMonths(rows);

    final totalConfidence = switch (totals) {
      _Totals(total: final t?, subtotal: final s?, tax: final x) when s + (x ?? 0) == t => 0.97,
      _Totals(total: final t?) when itemsSum > 0 && itemsSum == t => 0.95,
      _Totals(total: _?, fromKeyword: true) => 0.85,
      _Totals(total: _?) => 0.55,
      _ => 0.0,
    };
    final itemsConfidence = items.isEmpty
        ? 0.0
        : (totals.subtotal != null && itemsSum == totals.subtotal) || (totals.total != null && itemsSum == totals.total)
        ? 0.92
        : 0.72;

    return ReceiptDraft(
      currency: currency,
      status: ReceiptStatus.needsReview,
      engine: ExtractionEngine.onDevice,
      merchant: merchant?.$1,
      purchaseDate: date?.$1,
      totalMinor: totals.total ?? (itemsSum > 0 ? itemsSum : null),
      category: category.$1,
      paymentMethod: _payment(text),
      items: [
        for (final item in items)
          DraftItem(
            name: item.name,
            quantity: item.quantity,
            unitPriceMinor: item.unitPriceMinor,
            serialNumber: item.serialNumber,
            warrantyMonths: item.warrantyMonths,
            isExtendedWarranty: item.isExtendedWarranty,
            confidence: itemsConfidence,
          ),
      ],
      suggestedWarrantyMonths: generalWarranty,
      suggestedReturnDays: _returnDays(rows),
      ocrText: text,
      confidence: {
        'merchant': merchant?.$2 ?? 0,
        'purchaseDate': date?.$2 ?? 0,
        'total': totals.total == null && itemsSum > 0 ? 0.5 : totalConfidence,
        'category': category.$2,
        if (items.isNotEmpty) 'items': itemsConfidence,
      },
    );
  }

  /// Whether the text looks like a receipt at all.
  static bool looksLikeReceipt(ReceiptDraft draft) =>
      draft.totalMinor != null || draft.items.isNotEmpty || draft.merchant != null && draft.purchaseDate != null;

  // ---------------------------------------------------------------------------
  // Money
  // ---------------------------------------------------------------------------

  static final _money = RegExp(
    r'(-)?\s?([$€£₹]|(?<![A-Za-z])(?:rs\.?|pkr|usd|eur|gbp|aed|sar|inr|cad|aud))?\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+\.\d{2}|\d+,\d{2}|\d+)(?![\d%]|[.,]\d)',
    caseSensitive: false,
  );

  static List<_Amount> _amounts(String row) {
    final out = <_Amount>[];
    for (final m in _money.allMatches(row)) {
      final number = m.group(3)!;
      final hasSymbol = m.group(2) != null;
      final hasDecimalsOrGroups = number.contains('.') || number.contains(',');
      if (!hasSymbol && !hasDecimalsOrGroups) continue;
      // Skip numbers glued to letters, e.g. model numbers like WH-1000XM5.
      final numberStart = m.start + m.group(0)!.lastIndexOf(number);
      if (!hasSymbol && numberStart > 0 && RegExp(r'[A-Za-z]').hasMatch(row[numberStart - 1])) continue;
      final normalized = RegExp(r'^\d+,\d{2}$').hasMatch(number)
          ? number.replaceAll(',', '.')
          : number.replaceAll(',', '');
      final value = double.tryParse(normalized);
      if (value == null) continue;
      final minor = (value * 100).round() * (m.group(1) != null ? -1 : 1);
      out.add(_Amount(minor, m.start, m.end, hasSymbol: hasSymbol));
    }
    return out;
  }

  static String _currency(String text, String hint) {
    final upper = text.toUpperCase();
    for (final code in ['PKR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'INR', 'CAD', 'AUD', 'BDT', 'TRY']) {
      if (RegExp('\\b$code\\b').hasMatch(upper)) return code;
    }
    if (text.contains('€')) return 'EUR';
    if (text.contains('£')) return 'GBP';
    if (text.contains('₹')) return 'INR';
    if (RegExp(r'\bRs\.?\s?\d', caseSensitive: false).hasMatch(text)) return 'PKR';
    if (text.contains(r'$')) return const {'USD', 'CAD', 'AUD'}.contains(hint) ? hint : 'USD';
    return hint;
  }

  // ---------------------------------------------------------------------------
  // Totals
  // ---------------------------------------------------------------------------

  static final _subtotalKw = RegExp(r'sub\s*-?\s*total', caseSensitive: false);
  static final _taxKw = RegExp(r'\b(tax|vat|gst|hst|pst|fed|service charge)\b', caseSensitive: false);
  static final _totalKw = RegExp(
    r'\b(grand\s*total|total(\s*(due|amount|payable|paid))?|amount\s*(due|payable|paid)|balance\s*due|net\s*(total|amount)|to\s*pay)\b',
    caseSensitive: false,
  );
  static final _notTotal = RegExp(r'total\s*(items?|qty|quantity|savings|discount)', caseSensitive: false);

  static _Totals _totals(List<String> rows) {
    int? subtotal, tax, total;
    int? firstSummary;
    var fromKeyword = false;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final amounts = _amounts(row);
      if (amounts.isEmpty) continue;
      final value = amounts.last.minor;
      if (_subtotalKw.hasMatch(row)) {
        subtotal ??= value;
        firstSummary ??= i;
      } else if (_taxKw.hasMatch(row) && !_totalKw.hasMatch(row)) {
        tax = (tax ?? 0) + value;
        firstSummary ??= i;
      } else if (_totalKw.hasMatch(row) && !_notTotal.hasMatch(row)) {
        firstSummary ??= i;
        if (total == null) {
          total = value;
          fromKeyword = true;
        }
      }
    }
    if (total == null) {
      // No "total" keyword: use the largest amount on the receipt.
      final all = [for (final r in rows) ..._amounts(r).map((a) => a.minor)].where((v) => v > 0);
      if (all.isNotEmpty) total = all.reduce(math.max);
    }
    return _Totals(subtotal: subtotal, tax: tax, total: total, firstSummaryRow: firstSummary, fromKeyword: fromKeyword);
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  static final _nonItem = RegExp(
    r'\b(sub\s*-?\s*total|total|tax|vat|gst|change|cash|tender|card|visa|master\s*card|amex|debit|credit|balance|paid|payment|auth|approval|tip|gratuity|you saved|savings|rounding|points|loyalty|invoice|receipt|tel|phone|www|http|thank)\b',
    caseSensitive: false,
  );
  static final _qtyPrefix = RegExp(r'^(\d{1,3})\s*[x×]\s*', caseSensitive: false);
  static final _qtySuffix = RegExp(r'\s[x×]\s*(\d{1,3})\b', caseSensitive: false);
  static final _qtyWord = RegExp(r'\bqty[:.\s]*(\d{1,3})\b', caseSensitive: false);
  static final _serial = RegExp(
    r'\b(?:s/?n|serial(?:\s*no\.?)?|imei)[:#\s]*([A-Z0-9][A-Z0-9-]{4,})',
    caseSensitive: false,
  );
  static final _durationRx = RegExp(
    r'\b(\d{1,2}|one|two|three|four|five)\s*-?\s*(years?|yrs?|months?|mos?)\b',
    caseSensitive: false,
  );

  static List<_ParsedItem> _items(List<String> rows, int? stopAt) {
    final items = <_ParsedItem>[];
    final end = stopAt ?? rows.length;
    for (var i = 0; i < end; i++) {
      final row = rows[i];
      final serial = _serial.firstMatch(row);
      if (serial != null && items.isNotEmpty && _amounts(row).isEmpty) {
        items.last.serialNumber = serial.group(1);
        continue;
      }
      final amounts = _amounts(row);
      if (amounts.isEmpty || _nonItem.hasMatch(row)) continue;
      final last = amounts.last;
      if (last.minor <= 0) continue;

      var name = row.substring(0, amounts.first.start).trim();
      var quantity = 1;
      final prefix = _qtyPrefix.firstMatch(name);
      if (prefix != null) {
        quantity = int.parse(prefix.group(1)!);
        name = name.substring(prefix.end);
      } else if (_qtySuffix.firstMatch(name) case final m?) {
        quantity = int.parse(m.group(1)!);
        name = name.replaceRange(m.start, m.end, '');
      } else if (_qtyWord.firstMatch(name) case final m?) {
        quantity = int.parse(m.group(1)!);
        name = name.replaceRange(m.start, m.end, '');
      }
      name = name.replaceAll(RegExp(r'[.\s]+$'), '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      if (RegExp(r'[A-Za-z]').allMatches(name).length < 3) continue;
      quantity = quantity.clamp(1, 999);

      // "2 x 4.99  9.98": the first amount is the unit price.
      final unit = amounts.length > 1 && quantity > 1 && amounts.first.minor * quantity == last.minor
          ? amounts.first.minor
          : (last.minor / quantity).round();

      final coverage = _itemCoverage(name);
      items.add(
        _ParsedItem(
          name: name,
          quantity: quantity,
          unitPriceMinor: unit,
          serialNumber: serial?.group(1),
          warrantyMonths: coverage,
          isExtendedWarranty: coverage != null,
        ),
      );
    }
    return items;
  }

  /// "2-Yr Hardware Protection Plan", "AppleCare+ 24 months".
  static int? _itemCoverage(String name) {
    if (!RegExp(r'protection|warranty|applecare|care\s*plan|extended|guarantee', caseSensitive: false).hasMatch(name)) {
      return null;
    }
    final m = _durationRx.firstMatch(name);
    return m == null ? null : _months(m);
  }

  // ---------------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------------

  static const _monthNames = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  static const _mon = r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?';

  static (DateTime, double)? _date(List<String> rows, DateTime now, String currency) {
    final candidates = <(DateTime, double, bool)>[];
    for (final row in rows) {
      final dateRow = RegExp(r'\bdate\b', caseSensitive: false).hasMatch(row);
      void add(int y, int m, int d, double confidence) {
        if (y < 100) y += 2000;
        if (m < 1 || m > 12 || d < 1 || d > 31) return;
        final date = DateTime(y, m, d);
        if (date.month != m || date.year < 2000) return;
        if (date.isAfter(DateTime(now.year, now.month, now.day))) return;
        candidates.add((date, confidence, dateRow));
      }

      for (final m in RegExp(
        '\\b$_mon\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b',
        caseSensitive: false,
      ).allMatches(row)) {
        add(int.parse(m.group(3)!), _monthNames[m.group(1)!.toLowerCase()]!, int.parse(m.group(2)!), 0.93);
      }
      for (final m in RegExp(
        '\\b(\\d{1,2})(?:st|nd|rd|th)?[\\s-]+$_mon[\\s,-]+(\\d{2,4})\\b',
        caseSensitive: false,
      ).allMatches(row)) {
        add(int.parse(m.group(3)!), _monthNames[m.group(2)!.toLowerCase()]!, int.parse(m.group(1)!), 0.93);
      }
      for (final m in RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b').allMatches(row)) {
        add(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), 0.93);
      }
      for (final m in RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b').allMatches(row)) {
        final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
        if (a > 12) {
          add(y, b, a, 0.88);
        } else if (b > 12) {
          add(y, a, b, 0.88);
        } else {
          // Ambiguous day/month: US receipts use month first.
          currency == 'USD' ? add(y, a, b, 0.65) : add(y, b, a, 0.65);
        }
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((x, y) => (y.$3 ? 1 : 0).compareTo(x.$3 ? 1 : 0));
    final best = candidates.first;
    return (best.$1, best.$2);
  }

  // ---------------------------------------------------------------------------
  // Merchant
  // ---------------------------------------------------------------------------

  static final _notMerchant = RegExp(
    r'\b(st|street|rd|road|ave|avenue|blvd|suite|floor|plaza|block|sector|tel|phone|ph|fax|www|http|invoice|receipt|date|time|cashier|order|table|welcome|ntn|strn|gst|vat|reg|tran)\b|\.com|@',
    caseSensitive: false,
  );

  static (String, double)? _merchant(List<String> rows) {
    bool good(String row) {
      final letters = RegExp(r'[A-Za-z]').allMatches(row).length;
      final digits = RegExp(r'\d').allMatches(row).length;
      return letters >= 2 && digits <= letters * 0.3 && !_notMerchant.hasMatch(row) && _amounts(row).isEmpty;
    }

    for (var i = 0; i < math.min(rows.length, 6); i++) {
      if (!good(rows[i])) continue;
      var name = rows[i].trim();
      // Brand split over two lines: "TECHZONE" / "ELECTRONICS".
      if (i + 1 < rows.length && good(rows[i + 1])) {
        final next = rows[i + 1].trim();
        final words = next.split(RegExp(r'\s+')).length;
        if (words <= 2 && next == next.toUpperCase() && name == name.toUpperCase()) name = '$name $next';
      }
      name = name.replaceAll(RegExp(r'[*#=_~|]+'), ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
      if (name.isEmpty) continue;
      return (_titleCase(name), i <= 2 ? 0.8 : 0.6);
    }
    return null;
  }

  static String _titleCase(String s) {
    if (s != s.toUpperCase()) return s;
    return s.split(' ').map((w) => w.length <= 1 ? w : '${w[0]}${w.substring(1).toLowerCase()}').join(' ');
  }

  // ---------------------------------------------------------------------------
  // Payment, returns, warranty, category
  // ---------------------------------------------------------------------------

  static String? _payment(String text) {
    const brands = {
      'visa': 'Visa',
      'mastercard': 'Mastercard',
      'master card': 'Mastercard',
      'amex': 'Amex',
      'american express': 'Amex',
      'discover': 'Discover',
      'unionpay': 'UnionPay',
      'apple pay': 'Apple Pay',
      'google pay': 'Google Pay',
      'jazzcash': 'JazzCash',
      'easypaisa': 'Easypaisa',
      'paypal': 'PayPal',
    };
    final lower = text.toLowerCase();
    for (final entry in brands.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) {
        final last4 = RegExp(
          r'(?:\*{2,}|x{3,}|#{2,}|ending(?:\s+in)?)\s*(\d{4})\b',
          caseSensitive: false,
        ).firstMatch(text);
        return last4 == null ? entry.value : '${entry.value} •••• ${last4.group(1)}';
      }
    }
    if (RegExp(r'\b(debit|credit)\s*card\b').hasMatch(lower)) return 'Card';
    if (RegExp(r'\bcash\b').hasMatch(lower)) return 'Cash';
    return null;
  }

  static int? _returnDays(List<String> rows) {
    for (final row in rows) {
      if (!RegExp(r'return|refund|exchange', caseSensitive: false).hasMatch(row)) continue;
      final m = RegExp(r'(\d{1,3})\s*-?\s*(?:calendar\s+|business\s+)?days?\b', caseSensitive: false).firstMatch(row);
      if (m != null) {
        final days = int.parse(m.group(1)!);
        if (days > 0 && days <= 365) return days;
      }
    }
    return null;
  }

  static int? _generalWarrantyMonths(List<String> rows) {
    for (final row in rows) {
      if (!RegExp(r'warranty|guarantee', caseSensitive: false).hasMatch(row)) continue;
      if (RegExp(r'no\s+warranty|without\s+warranty', caseSensitive: false).hasMatch(row)) return null;
      final m = _durationRx.firstMatch(row);
      if (m != null) return _months(m);
    }
    return null;
  }

  static int _months(RegExpMatch m) {
    const words = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5};
    final raw = m.group(1)!.toLowerCase();
    final n = int.tryParse(raw) ?? words[raw] ?? 0;
    final unit = m.group(2)!.toLowerCase();
    return (unit.startsWith('y') ? n * 12 : n).clamp(0, 120);
  }

  static const _categoryWords = <Category, List<String>>{
    Category.electronics: [
      'electronic',
      'sony',
      'samsung',
      'apple',
      'iphone',
      'laptop',
      'phone',
      'mobile',
      'charger',
      'headphone',
      'earbud',
      'airpods',
      'usb',
      'hdmi',
      'cable',
      'tv',
      'led',
      'monitor',
      'camera',
      'anker',
      'gan',
      'tablet pc',
      'keyboard',
      'mouse',
      'speaker',
      'xiaomi',
      'dell',
      'hp ',
      'lenovo',
      'jbl',
    ],
    Category.appliances: [
      'fridge',
      'refrigerator',
      'washer',
      'washing',
      'microwave',
      'oven',
      'air fryer',
      'blender',
      'iron',
      'kettle',
      'vacuum',
      'air condition',
      'heater',
      'dishwasher',
      'dawlance',
      'haier',
      'appliance',
    ],
    Category.furniture: ['sofa', 'chair', 'table', 'desk', 'bed', 'mattress', 'wardrobe', 'furniture', 'shelf'],
    Category.clothing: [
      'shirt',
      't-shirt',
      'jeans',
      'jacket',
      'dress',
      'shoes',
      'kurta',
      'apparel',
      'fashion',
      'denim',
    ],
    Category.groceries: [
      'grocery',
      'mart',
      'milk',
      'bread',
      'eggs',
      'rice',
      'sugar',
      'flour',
      'atta',
      'oil',
      'vegetable',
      'fruit',
      'supermarket',
      'kg',
    ],
    Category.health: ['pharmacy', 'clinic', 'hospital', 'medicine', 'tablet', 'capsule', 'syrup', 'mg', 'chemist'],
    Category.home: ['hardware', 'paint', 'decor', 'kitchenware', 'bedding', 'curtain', 'tools'],
    Category.travel: ['airline', 'flight', 'hotel', 'booking', 'fuel', 'petrol', 'ticket', 'boarding'],
    Category.dining: ['restaurant', 'cafe', 'coffee', 'burger', 'pizza', 'dine', 'server', 'waiter', 'tip', 'gratuity'],
  };

  static (Category, double) _category(String lower) {
    var best = Category.other;
    var bestScore = 0;
    for (final entry in _categoryWords.entries) {
      var score = 0;
      for (final word in entry.value) {
        if (RegExp('\\b${RegExp.escape(word.trim())}', caseSensitive: false).hasMatch(lower)) score++;
      }
      if (score > bestScore) {
        best = entry.key;
        bestScore = score;
      }
    }
    final confidence = bestScore >= 3
        ? 0.85
        : bestScore == 2
        ? 0.75
        : bestScore == 1
        ? 0.6
        : 0.4;
    return (best, confidence);
  }
}

class _Totals {
  const _Totals({this.subtotal, this.tax, this.total, this.firstSummaryRow, this.fromKeyword = false});
  final int? subtotal;
  final int? tax;
  final int? total;
  final int? firstSummaryRow;
  final bool fromKeyword;
}

class _ParsedItem {
  _ParsedItem({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    this.serialNumber,
    this.warrantyMonths,
    this.isExtendedWarranty = false,
  });
  final String name;
  final int quantity;
  final int? unitPriceMinor;
  String? serialNumber;
  final int? warrantyMonths;
  final bool isExtendedWarranty;
}
