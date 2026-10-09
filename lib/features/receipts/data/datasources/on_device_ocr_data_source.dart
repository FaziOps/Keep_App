import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../parsing/receipt_text_parser.dart';

/// Text recognition on the device: Apple Vision on iOS and Google ML Kit on
/// Android (see AppDelegate.swift and MainActivity.kt). Free, private and
/// works offline. Not available on the web.
class OnDeviceOcrDataSource {
  const OnDeviceOcrDataSource();

  static const _channel = MethodChannel('io.keepr.app/ocr');

  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  /// Throws [PlatformException] when the image cannot be read.
  Future<List<OcrLine>> recognize(Uint8List image) async {
    final raw = await _channel.invokeListMethod<Object?>('recognizeText', {'bytes': image});
    return [
      for (final entry in raw ?? const <Object?>[])
        if (entry is Map) OcrLine.fromMap(entry),
    ];
  }
}
