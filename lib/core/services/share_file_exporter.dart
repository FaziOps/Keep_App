import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'file_exporter.dart';

/// Share sheet on Android/iOS; Web Share API or a download in the browser.
class ShareFileExporter implements FileExporter {
  const ShareFileExporter();

  @override
  Future<void> share({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        fileNameOverrides: [fileName],
        subject: subject,
        downloadFallbackEnabled: true,
      ),
    );
  }
}
