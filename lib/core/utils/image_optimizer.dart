import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Compresses images for RouterOS portal use.
/// 
/// With chunked uploading, we can handle images up to 150KB.
/// Compression is still applied to optimize portal loading performance
/// and reduce bandwidth usage.
class ImageOptimizer {
  /// Compresses an image for RouterOS portal use.
  /// 
  /// - [bytes]: Original image bytes
  /// - [isLogo]: If true, uses logo settings (200x200, PNG format for transparency).
  ///              If false, uses background settings (800x600, JPEG format).
  /// 
  /// Returns compressed image bytes (PNG for logos, JPEG for backgrounds).
  static Future<Uint8List> compressForRouter(
    Uint8List bytes, {
    required bool isLogo,
  }) async {
    // Compression settings optimized for portal performance
    final maxWidth = isLogo ? 200 : 800;
    final maxHeight = isLogo ? 200 : 600;
    final quality = isLogo ? 80 : 50; // Lower quality for background
    
    // Use PNG for logos (supports transparency), JPEG for backgrounds (smaller size)
    final format = isLogo ? CompressFormat.png : CompressFormat.jpeg;

    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
      format: format,
    );

    return Uint8List.fromList(result);
  }
  
  /// Returns the MIME type for the compressed image based on format.
  static String getMimeType({required bool isLogo}) {
    return isLogo ? 'image/png' : 'image/jpeg';
  }
}
