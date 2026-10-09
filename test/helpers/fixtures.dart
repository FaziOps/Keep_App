import 'package:keepr/core/domain/money.dart';
import 'package:keepr/features/receipts/domain/entities/receipt.dart';

final fixedNow = DateTime(2026, 10, 6, 9);

Receipt receipt({
  String id = 'r1',
  String householdId = 'local-u1',
  String merchant = 'Mega Electronics',
  DateTime? purchaseDate,
  int totalMinor = 1899900,
  String currency = 'PKR',
  Category category = Category.electronics,
  ReceiptStatus status = ReceiptStatus.confirmed,
  int? returnDays,
  List<LineItem>? items,
  DateTime? deletedAt,
}) => Receipt(
  id: id,
  householdId: householdId,
  createdBy: 'u1',
  merchant: merchant,
  purchaseDate: purchaseDate ?? DateTime(2026, 10, 1),
  total: Money(totalMinor, currency),
  category: category,
  status: status,
  syncState: SyncState.localOnly,
  createdAt: fixedNow,
  updatedAt: fixedNow,
  returnDays: returnDays,
  items: items ?? const [],
  deletedAt: deletedAt,
);

LineItem item({
  String id = 'i1',
  String name = 'Earbuds',
  int priceMinor = 1899900,
  int? months,
  String currency = 'PKR',
}) => LineItem(
  id: id,
  name: name,
  quantity: 1,
  unitPrice: Money(priceMinor, currency),
  warranty: months == null ? null : Warranty(months: months),
);
