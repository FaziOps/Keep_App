import 'package:intl/intl.dart';

import '../domain/money.dart';

const _symbols = {
  'USD': r'$',
  'CAD': r'CA$',
  'AUD': r'A$',
  'EUR': '€',
  'GBP': '£',
  'INR': '₹',
  'PKR': 'Rs',
  'BDT': '৳',
  'TRY': '₺',
};

String currencySymbol(String code) => _symbols[code] ?? code;

String formatMoney(Money money, {bool compact = false}) {
  final symbol = currencySymbol(money.currency);
  final separator = symbol.length > 1 ? ' ' : '';
  if (compact && money.major.abs() >= 10000) {
    return '$symbol$separator${NumberFormat.compact().format(money.major)}';
  }
  final digits = money.minor % 100 == 0 ? 0 : 2;
  final number = NumberFormat.decimalPatternDigits(decimalDigits: digits).format(money.major);
  return '$symbol$separator$number';
}

String formatDate(DateTime d) => DateFormat('d MMM yyyy').format(d);
String formatShortDate(DateTime d) => DateFormat('d MMM').format(d);
String formatMonth(DateTime d) => DateFormat('MMM').format(d);
String formatDateTime(DateTime d) => DateFormat('d MMM, h:mm a').format(d);

String relativeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  if (days < 0) return '${-days} days ago';
  if (days < 60) return 'in $days days';
  final months = (days / 30).round();
  if (months < 24) return 'in $months months';
  return 'in ${(months / 12).round()} years';
}

String timeAgo(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return formatShortDate(d);
}

/// Parses user input like "1,299.50" into minor units.
int? parseMoneyInput(String input) {
  final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  return value == null ? null : (value * 100).round();
}

String moneyInputText(int minor) {
  if (minor == 0) return '';
  final major = minor / 100;
  return minor % 100 == 0 ? major.toStringAsFixed(0) : major.toStringAsFixed(2);
}

/// Human-friendly short id, e.g. for claim letters.
String shortReference(String id) {
  final compact = id.replaceAll('-', '');
  return (compact.length > 8 ? compact.substring(0, 8) : compact).toUpperCase();
}
