import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class CapturedImage {
  const CapturedImage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
}

/// Port for capturing a photo, so presenters stay free of plugins.
abstract interface class ImageCapture {
  Future<CapturedImage?> capture({required bool fromCamera});
}

/// FR-CAP-01/02/04: camera or gallery, resized to 1600 px and compressed.
class ImagePickerCapture implements ImageCapture {
  ImagePickerCapture([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<CapturedImage?> capture({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    return CapturedImage(bytes, mime);
  }
}
