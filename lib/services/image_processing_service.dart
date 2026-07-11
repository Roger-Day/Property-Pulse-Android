import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Mirrors iOS `PropertyListingImageEncoding` / `jpegDataUnderLimit`:
/// resize long edge to [maxDimension], then JPEG-encode starting at
/// [initialQuality] and stepping down by 10 until bytes ≤ [maxBytes].
///
/// Returns the processed bytes, or null if the file cannot be decoded.
class ImageProcessingService {
  static const int maxDimension = 2048;
  static const int initialQuality = 70; // matches iOS 0.7
  static const int minQuality = 30;
  static const int maxBytes = 2 * 1024 * 1024; // 2 MB ceiling

  /// Process a single [XFile] from the image picker.
  static Future<Uint8List?> processForUpload(XFile xFile) async {
    try {
      final raw = await xFile.readAsBytes();
      return _process(raw);
    } catch (_) {
      return null;
    }
  }

  /// Process a raw bytes (e.g. from camera or file).
  static Future<Uint8List?> processBytes(Uint8List raw) async {
    return _process(raw);
  }

  static Uint8List? _process(Uint8List raw) {
    // Decode image — handles JPEG, PNG, WebP, HEIC (via platform layer)
    img.Image? decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    // Resize so the long edge ≤ maxDimension (preserves aspect ratio)
    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(decoded, width: maxDimension);
      } else {
        decoded = img.copyResize(decoded, height: maxDimension);
      }
    }

    // JPEG encode, iterating quality down until bytes ≤ maxBytes
    int quality = initialQuality;
    Uint8List encoded = Uint8List.fromList(
        img.encodeJpg(decoded, quality: quality));

    while (encoded.length > maxBytes && quality > minQuality) {
      quality -= 10;
      encoded = Uint8List.fromList(
          img.encodeJpg(decoded, quality: quality));
    }

    return encoded;
  }

  /// Write processed bytes to a temp file for Firebase Storage upload.
  static Future<File> writeTempFile(
      Uint8List bytes, String name) async {
    final dir = Directory.systemTemp;
    final file = File(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }
}
