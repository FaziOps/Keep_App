import '../../../../core/domain/clock.dart';
import '../../../../core/domain/money.dart';
import '../entities/receipt.dart';
import 'receipt_usecases.dart';

/// Adds realistic sample receipts so a new user (or a reviewer) can explore
/// the vault, reminders, insights and claim packs immediately.
class SeedDemoReceipts {
  const SeedDemoReceipts(this._save, this._clock, this._newId);

  final SaveReceipt _save;
  final Clock _clock;
  final String Function() _newId;

  Future<int> call({required String householdId, required String userId, required String currency}) async {
    final now = _clock();
    Money m(num major) => Money.fromMajor(major, currency);
    DateTime ago(int days) => dateOnly(now.subtract(Duration(days: days)));

    LineItem item(String name, num price, {int months = 0, String? serial, int qty = 1}) => LineItem(
      id: _newId(),
      name: name,
      quantity: qty,
      unitPrice: m(price),
      serialNumber: serial,
      warranty: months > 0 ? Warranty(months: months) : null,
    );

    final samples = [
      (
        'Mega Electronics',
        ago(4),
        Category.electronics,
        14,
        'Card',
        [item('Wireless earbuds Pro', 18999, months: 12, serial: 'WEP-88213')],
      ),
      (
        'HomeStyle Appliances',
        ago(340),
        Category.appliances,
        7,
        'Bank transfer',
        [item('Air fryer 5.5L', 32500, months: 12, serial: 'AF55-10293')],
      ),
      (
        'City Mobiles',
        ago(700),
        Category.electronics,
        7,
        'Cash',
        [item('Smartphone 128GB', 89999, months: 24, serial: '356789104455120'), item('Phone case', 1500)],
      ),
      (
        'Urban Wear',
        ago(9),
        Category.clothing,
        30,
        'Card',
        [item('Denim jacket', 6500), item('Cotton t-shirt', 1800, qty: 2)],
      ),
      ('FreshMart', ago(2), Category.groceries, null, 'Card', [item('Weekly groceries', 11250)]),
      (
        'Comfort Furniture',
        ago(120),
        Category.furniture,
        14,
        'Card',
        [item('Office chair ergonomic', 45000, months: 36, serial: 'OC-ERG-7781')],
      ),
    ];

    var count = 0;
    for (final (merchant, date, category, returnDays, payment, items) in samples) {
      final total = items.fold(Money.zero(currency), (sum, i) => sum + i.total);
      final result = await _save.confirm(
        Receipt(
          id: _newId(),
          householdId: householdId,
          createdBy: userId,
          merchant: merchant,
          purchaseDate: date,
          total: total,
          category: category,
          status: ReceiptStatus.confirmed,
          syncState: SyncState.localOnly,
          createdAt: now,
          updatedAt: now,
          items: items,
          returnDays: returnDays,
          paymentMethod: payment,
        ),
      );
      if (result.isSuccess) count++;
    }
    return count;
  }
}
