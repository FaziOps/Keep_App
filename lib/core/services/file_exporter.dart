import 'dart:typed_data';

/// Port for handing a generated file to the user (share sheet on mobile,
/// download on web).
abstract interface class FileExporter {
  Future<void> share({required Uint8List bytes, required String fileName, required String mimeType, String? subject});
}
