import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls the `extract-receipt` Edge Function. The LLM key never leaves the
/// server; the user's JWT is attached automatically by the client.
class ExtractionRemoteDataSource {
  const ExtractionRemoteDataSource(this._client);
  final SupabaseClient _client;

  bool get hasSession => _client.auth.currentSession != null;

  Future<Map<String, dynamic>> extract({
    required Uint8List image,
    required String mimeType,
    required String currency,
    String? locale,
  }) async {
    final res = await _client.functions.invoke(
      'extract-receipt',
      body: {'image_base64': base64Encode(image), 'mime_type': mimeType, 'currency': currency, 'locale': locale},
    );
    return (res.data as Map).cast<String, dynamic>();
  }
}
