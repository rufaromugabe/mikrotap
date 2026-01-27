import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Aggressively compresses images to stay under RouterOS API limits.
/// 
/// RouterOS API has a strict 64KB limit per "word" (parameter).
/// Base64 encoding increases size by ~33%, so we need to keep binary
/// images under ~45KB to ensure the final HTML stays under 64KB.
class ImageOptimizer {
  /// Compresses an image for RouterOS portal use.
  /// 
  /// - [bytes]: Original image bytes
  /// - [isLogo]: If true, uses logo settings (200x200, 80% quality).
  ///              If false, uses background settings (800x600, 50% quality).
  /// 
  /// Returns compressed JPEG bytes.
  static Future<Uint8List> compressForRouter(
    Uint8List bytes, {
    required bool isLogo,
  }) async {
    // Aggressive settings to stay under RouterOS API limits
    final maxWidth = isLogo ? 200 : 800;
    final maxHeight = isLogo ? 200 : 600;
    final quality = isLogo ? 80 : 50; // Lower quality for background

    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
      format: CompressFormat.jpeg,
    );

    return Uint8List.fromList(result);
  }
}
