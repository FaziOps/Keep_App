import 'dart:typed_data';

import '../../../../core/storage/local_store.dart';
import '../../domain/entities/receipt.dart';
import '../models/receipt_model.dart';

class ReceiptLocalDataSource {
  const ReceiptLocalDataSource(this._store);
  final LocalStore _store;

  List<Receipt> all() => [for (final raw in _store.receipts.values) ReceiptModel.fromJson(LocalStore.decode(raw))];

  List<Receipt> forHousehold(String householdId) {
    final list = all().where((r) => r.householdId == householdId && !r.isDeleted).toList()
      ..sort((a, b) {
        final byDate = b.purchaseDate.compareTo(a.purchaseDate);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  Stream<List<Receipt>> watchHousehold(String householdId) =>
      watchBox(_store.receipts, () => forHousehold(householdId));

  Stream<Receipt?> watchOne(String id) => watchBox(_store.receipts, () => get(id));

  Receipt? get(String id) {
    final raw = _store.receipts.get(id);
    return raw == null ? null : ReceiptModel.fromJson(LocalStore.decode(raw));
  }

  Future<void> put(Receipt receipt) => _store.receipts.put(receipt.id, LocalStore.encode(ReceiptModel.toJson(receipt)));

  Future<void> remove(String id) => _store.receipts.delete(id);

  Future<void> putAttachment(String id, Uint8List bytes) => _store.attachments.put(id, bytes);

  Future<Uint8List?> getAttachment(String id) => _store.attachments.get(id);

  Future<void> removeAttachment(String id) => _store.attachments.delete(id);
}
