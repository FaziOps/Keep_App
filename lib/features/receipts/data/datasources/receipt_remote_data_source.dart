import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class UpsertOutcome {
  const UpsertOutcome({required this.conflict, required this.row});

  /// True when the server kept a newer version (BR-13).
  final bool conflict;
  final Map<String, dynamic> row;
}

/// Supabase access for receipts. Rows are written through the
/// `upsert_receipt` database function so a receipt and its items are saved
/// atomically under Row-Level Security.
class ReceiptRemoteDataSource {
  const ReceiptRemoteDataSource(this._client);
  final SupabaseClient _client;

  static const bucket = 'receipts';

  Future<String> uploadAttachment({
    required String householdId,
    required String receiptId,
    required String attachmentId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final ext = mimeType.contains('png') ? 'png' : 'jpg';
    final path = '$householdId/$receiptId/$attachmentId.$ext';
    await _client.storage
        .from(bucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: true));
    return path;
  }

  Future<Uint8List> downloadAttachment(String path) => _client.storage.from(bucket).download(path);

  Future<UpsertOutcome> upsertReceipt(Map<String, dynamic> receipt) async {
    final res = await _client.rpc<dynamic>('upsert_receipt', params: {'p_receipt': receipt});
    final map = (res as Map).cast<String, dynamic>();
    return UpsertOutcome(conflict: map['conflict'] == true, row: (map['receipt'] as Map).cast<String, dynamic>());
  }

  Future<List<Map<String, dynamic>>> pullChanges(String householdId, DateTime? since) async {
    final res = await _client.rpc<dynamic>(
      'pull_changes',
      params: {'p_household_id': householdId, 'p_since': since?.toUtc().toIso8601String()},
    );
    return [for (final e in (res as List? ?? const [])) (e as Map).cast<String, dynamic>()];
  }
}
