import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Image format detection and compression for RouterOS portal use.
class ImageOptimizer {
  /// Detects image format from file bytes by checking magic numbers.
  /// Returns the format extension (e.g., 'png', 'jpg', 'gif', 'webp').
  static String? detectImageFormat(Uint8List bytes) {
    if (bytes.length < 4) return null;
    
    // Check magic numbers for common image formats
    // PNG: 89 50 4E 47
    if (bytes.length >= 4 && 
        bytes[0] == 0x89 && bytes[1] == 0x50 && 
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    
    // JPEG: FF D8 FF
    if (bytes.length >= 3 && 
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    
    // GIF: 47 49 46 38 (GIF8)
    if (bytes.length >= 4 && 
        bytes[0] == 0x47 && bytes[1] == 0x49 && 
        bytes[2] == 0x46 && bytes[3] == 0x38) {
      return 'gif';
    }
    
    // WebP: RIFF...WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && 
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && 
        bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'webp';
    }
    
    // BMP: 42 4D
    if (bytes.length >= 2 && 
        bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }
    
    return null;
  }

  /// Detects image format from filename extension.
  static String? detectFormatFromFilename(String? filename) {
    if (filename == null || filename.isEmpty) return null;
    final ext = filename.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      return ext == 'jpeg' ? 'jpg' : ext;
    }
    return null;
  }

  /// Compresses an image for RouterOS portal use.
  /// 
  /// - [bytes]: Original image bytes
  /// - [isLogo]: If true, uses logo settings (200x200, preserves transparency).
  ///              If false, uses background settings (800x600, optimized for size).
  /// 
  /// Returns compressed image bytes and detected format.
  static Future<({Uint8List bytes, String format, String mimeType})> compressForRouter(
    Uint8List bytes, {
    required bool isLogo,
    String? originalFilename,
  }) async {
    // Try to detect format from filename first, then from bytes
    String? detectedFormat = detectFormatFromFilename(originalFilename);
    detectedFormat ??= detectImageFormat(bytes);
    
    // Compression settings optimized for portal performance
    final maxWidth = isLogo ? 200 : 800;
    final maxHeight = isLogo ? 200 : 600;
    final quality = isLogo ? 80 : 50; // Lower quality for background
    
    // Determine output format - preserve original format whenever possible
    CompressFormat outputFormat;
    String finalFormat;
    
    if (isLogo) {
      // Logos: preserve original format (PNG, JPEG, WebP, GIF)
      if (detectedFormat == 'png') {
        outputFormat = CompressFormat.png;
        finalFormat = 'png';
      } else if (detectedFormat == 'jpg' || detectedFormat == 'jpeg') {
        outputFormat = CompressFormat.jpeg;
        finalFormat = 'jpg';
      } else if (detectedFormat == 'webp') {
        outputFormat = CompressFormat.webp;
        finalFormat = 'webp';
      } else if (detectedFormat == 'gif') {
        // GIF must be converted since flutter_image_compress doesn't support GIF output
        outputFormat = CompressFormat.png;
        finalFormat = 'png';
      } else {
        // Unknown format, default to PNG for logos
        outputFormat = CompressFormat.png;
        finalFormat = 'png';
      }
    } else {
      // Backgrounds: preserve JPEG/WebP, convert others to JPEG
      if (detectedFormat == 'jpg' || detectedFormat == 'jpeg') {
        outputFormat = CompressFormat.jpeg;
        finalFormat = 'jpg';
      } else if (detectedFormat == 'webp') {
        outputFormat = CompressFormat.webp;
        finalFormat = 'webp';
      } else {
        // Convert all other formats to JPEG for backgrounds
        outputFormat = CompressFormat.jpeg;
        finalFormat = 'jpg';
      }
    }

    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxWidth,
      minHeight: maxHeight,
      quality: quality,
      format: outputFormat,
    );

    if (result.isEmpty) {
      throw Exception('Image compression returned empty result');
    }

    final compressedBytes = Uint8List.fromList(result);
    
    // Verify the compressed bytes are valid for the output format
    if (compressedBytes.length < 4) {
      throw Exception('Compressed image is too small to be valid');
    }
    
    // Verify the output format matches what we expect
    bool isValidFormat = false;
    if (finalFormat == 'png') {
      isValidFormat = compressedBytes[0] == 0x89 && compressedBytes[1] == 0x50 && 
                      compressedBytes[2] == 0x4E && compressedBytes[3] == 0x47;
    } else if (finalFormat == 'jpg') {
      isValidFormat = compressedBytes[0] == 0xFF && compressedBytes[1] == 0xD8;
    } else if (finalFormat == 'webp') {
      isValidFormat = compressedBytes.length >= 12 &&
                      compressedBytes[0] == 0x52 && compressedBytes[1] == 0x49 && 
                      compressedBytes[2] == 0x46 && compressedBytes[3] == 0x46 &&
                      compressedBytes[8] == 0x57 && compressedBytes[9] == 0x45 && 
                      compressedBytes[10] == 0x42 && compressedBytes[11] == 0x50;
    }
    
    if (!isValidFormat) {
      throw Exception('Compressed ${finalFormat.toUpperCase()} validation failed - invalid header');
    }
    
    final mimeType = _getMimeTypeFromFormat(finalFormat);
    
    return (
      bytes: compressedBytes,
      format: finalFormat,
      mimeType: mimeType,
    );
  }
  
  /// Returns the MIME type based on format extension.
  static String _getMimeTypeFromFormat(String format) {
    switch (format.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png'; // Default fallback
    }
  }
  
  /// Returns the MIME type for the compressed image based on format.
  /// @deprecated Use compressForRouter which returns format info
  @Deprecated('Use compressForRouter which returns format and mimeType')
  static String getMimeType({required bool isLogo}) {
    return isLogo ? 'image/png' : 'image/jpeg';
  }
}
