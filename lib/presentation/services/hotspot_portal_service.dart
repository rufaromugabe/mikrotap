import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../data/services/routeros_api_client.dart';
import '../templates/portal_template.dart';
import '../templates/template_registry.dart';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Legacy preset class for backward compatibility
@Deprecated('Use PortalTemplate instead')
class PortalThemePreset {
  const PortalThemePreset({
    required this.id,
    required this.name,
    required this.primaryHex,
    required this.bgCss,
    required this.cardCss,
    required this.textCss,
    required this.mutedCss,
  });

  final String id;
  final String name;
  final String primaryHex;
  final String bgCss;
  final String cardCss;
  final String textCss;
  final String mutedCss;
}

class PortalBranding {
  const PortalBranding({
    required this.title,
    required this.primaryHex,
    required this.supportText,
    this.themeId = 'midnight',
    this.logoBytes,
    this.logoFilename,
    this.backgroundBytes,
    this.backgroundFilename,
    this.cardOpacity,
    this.borderWidth,
    this.borderStyle,
    this.borderRadius,
  });

  final String title;
  final String primaryHex; // e.g. #2563EB
  final String supportText;
  final String themeId;
  
  // Binary image data (no more Base64!)
  final Uint8List? logoBytes;
  final String? logoFilename; // e.g. 'logo.png'
  final Uint8List? backgroundBytes;
  final String? backgroundFilename; // e.g. 'background.jpg'

  // Template customization options
  final double? cardOpacity; // 0.0 to 1.0
  final double? borderWidth; // in pixels
  final String? borderStyle; // solid, dashed, dotted, double, none
  final double? borderRadius; // in pixels
  
  // Helper to get data URI for preview only
  String? get logoDataUri => logoBytes != null
      ? 'data:image/${_getImageType(logoFilename)};base64,${base64Encode(logoBytes!)}'
      : null;
  
  String? get backgroundDataUri => backgroundBytes != null
      ? 'data:image/${_getImageType(backgroundFilename)};base64,${base64Encode(backgroundBytes!)}'
      : null;
  
  static String _getImageType(String? filename) {
    if (filename == null) return 'png';
    final ext = filename.split('.').last.toLowerCase();
    
    // Map common extensions to MIME type format
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return ext;
      default:
        return 'png'; // Default fallback
    }
  }
}

class HotspotPortalService {
  /// Legacy presets for backward compatibility
  @Deprecated('Use TemplateRegistry.all instead')
  static List<PortalThemePreset> get presets => [
    PortalThemePreset(
      id: 'midnight',
      name: 'Midnight',
      primaryHex: '#2563EB',
      bgCss: '',
      cardCss: '',
      textCss: '',
      mutedCss: '',
    ),
  ];

  /// Get all available templates
  static List<PortalTemplate> get templates => TemplateRegistry.all;

  /// Get a template by ID
  static PortalTemplate getTemplateById(String? id) {
    return TemplateRegistry.getByIdOrDefault(id);
  }

  /// Detects the true image format from file bytes (magic numbers)
  /// Returns the correct file extension that matches the actual data
  static String _getTrueImageExtension(Uint8List bytes) {
    if (bytes.length < 4) return 'png';
    
    // Check magic numbers for common image formats
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && 
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    
    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && 
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
    
    // Default to png if format cannot be determined
    return 'png';
  }

  /// Legacy method for backward compatibility
  @Deprecated('Use getTemplateById instead')
  static PortalThemePreset presetById(String? id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }

  static PortalBranding defaultBranding({required String routerName}) {
    final template = getTemplateById('midnight');
    return PortalBranding(
      title: routerName.isEmpty ? 'MikroTap Wi‑Fi' : routerName,
      primaryHex: template.defaultPrimaryHex,
      supportText: 'Need help? Contact the attendant.',
      themeId: template.id,
    );
  }

  static Future<void> applyDefaultPortal(
    RouterOsApiClient c, {
    required String routerName,
    required String ftpHost,
    required String ftpUsername,
    required String ftpPassword,
    int ftpPort = 21,
  }) async {
    final b = defaultBranding(routerName: routerName);
    await applyPortal(
      c,
      branding: b,
      ftpHost: ftpHost,
      ftpUsername: ftpUsername,
      ftpPassword: ftpPassword,
      ftpPort: ftpPort,
    );
  }


  static Future<String> buildPortalFolder({
    required PortalBranding branding,
  }) async {
    // Use static directory name for easier management (MikroTicket style)
    const directoryName = 'mikrotap_portal';

    // Get temporary directory
    final tempDir = await getTemporaryDirectory();
    final portalDir = Directory(path.join(tempDir.path, directoryName));
    
    // Clean up existing folder if it exists (with error handling)
    try {
      if (await portalDir.exists()) {
        await portalDir.delete(recursive: true);
        // Small delay to ensure filesystem operations complete
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      throw Exception('Failed to clean up existing portal directory: $e');
    }

    // Create main directory with verification
    try {
      await portalDir.create(recursive: true);
      if (!await portalDir.exists()) {
        throw Exception('Failed to create portal directory');
      }
    } catch (e) {
      throw Exception('Failed to create portal directory: $e');
    }

    // Create CSS subdirectory (images go in root folder, not img/ subdirectory)
    final cssDir = Directory(path.join(portalDir.path, 'css'));
    
    try {
      await cssDir.create(recursive: true);
      
      // Verify directory was created
      if (!await cssDir.exists()) {
        throw Exception('Failed to create css subdirectory');
      }
    } catch (e) {
      throw Exception('Failed to create portal subdirectories: $e');
    }

    // Save images as actual files (no base64 encoding) with error handling
    String? logoPath;
    String? backgroundPath;
    
    if (branding.logoBytes != null && branding.logoBytes!.isNotEmpty) {
      try {
        // Detect true image format from bytes (ensures extension matches actual data)
        final trueExt = _getTrueImageExtension(branding.logoBytes!);
        final logoFilename = branding.logoFilename ?? 'logo.$trueExt';
        
        // Ensure filename extension matches the actual format
        final finalLogoFilename = logoFilename.endsWith('.$trueExt') 
            ? logoFilename 
            : 'logo.$trueExt';
        
        // Verify it's a valid image by checking magic numbers
        final isValidImage = branding.logoBytes!.length >= 4 && (
          // PNG
          (branding.logoBytes![0] == 0x89 && branding.logoBytes![1] == 0x50 && 
           branding.logoBytes![2] == 0x4E && branding.logoBytes![3] == 0x47) ||
          // JPEG
          (branding.logoBytes![0] == 0xFF && branding.logoBytes![1] == 0xD8) ||
          // GIF
          (branding.logoBytes![0] == 0x47 && branding.logoBytes![1] == 0x49 && 
           branding.logoBytes![2] == 0x46 && branding.logoBytes![3] == 0x38) ||
          // WebP
          (branding.logoBytes!.length >= 12 &&
           branding.logoBytes![0] == 0x52 && branding.logoBytes![1] == 0x49 && 
           branding.logoBytes![2] == 0x46 && branding.logoBytes![3] == 0x46 &&
           branding.logoBytes![8] == 0x57 && branding.logoBytes![9] == 0x45 && 
           branding.logoBytes![10] == 0x42 && branding.logoBytes![11] == 0x50)
        );
        
        if (!isValidImage) {
          throw Exception('Logo bytes do not appear to be a valid image file');
        }
        
        // Save image in root folder (not img/ subdirectory)
        final logoFile = File(path.join(portalDir.path, finalLogoFilename));
        await logoFile.writeAsBytes(branding.logoBytes!, flush: true);
        
        // Verify file was written correctly
        if (!await logoFile.exists()) {
          throw Exception('Logo file was not created');
        }
        
        final fileSize = await logoFile.length();
        if (fileSize != branding.logoBytes!.length) {
          throw Exception('Logo file size mismatch: expected ${branding.logoBytes!.length}, got $fileSize');
        }
        
        if (fileSize == 0) {
          throw Exception('Logo file is empty');
        }
        
        // Use relative path (no leading slash, no img/ prefix) for HTML
        logoPath = finalLogoFilename;
      } catch (e) {
        throw Exception('Failed to write logo file: $e');
      }
    }
    
    if (branding.backgroundBytes != null && branding.backgroundBytes!.isNotEmpty) {
      try {
        // Detect true image format from bytes (ensures extension matches actual data)
        final trueExt = _getTrueImageExtension(branding.backgroundBytes!);
        final bgFilename = branding.backgroundFilename ?? 'background.$trueExt';
        
        // Ensure filename extension matches the actual format
        final finalBgFilename = bgFilename.endsWith('.$trueExt') 
            ? bgFilename 
            : 'background.$trueExt';
        
        // Verify it's a valid image by checking magic numbers
        final isValidImage = branding.backgroundBytes!.length >= 4 && (
          // PNG
          (branding.backgroundBytes![0] == 0x89 && branding.backgroundBytes![1] == 0x50 && 
           branding.backgroundBytes![2] == 0x4E && branding.backgroundBytes![3] == 0x47) ||
          // JPEG
          (branding.backgroundBytes![0] == 0xFF && branding.backgroundBytes![1] == 0xD8) ||
          // GIF
          (branding.backgroundBytes![0] == 0x47 && branding.backgroundBytes![1] == 0x49 && 
           branding.backgroundBytes![2] == 0x46 && branding.backgroundBytes![3] == 0x38) ||
          // WebP
          (branding.backgroundBytes!.length >= 12 &&
           branding.backgroundBytes![0] == 0x52 && branding.backgroundBytes![1] == 0x49 && 
           branding.backgroundBytes![2] == 0x46 && branding.backgroundBytes![3] == 0x46 &&
           branding.backgroundBytes![8] == 0x57 && branding.backgroundBytes![9] == 0x45 && 
           branding.backgroundBytes![10] == 0x42 && branding.backgroundBytes![11] == 0x50)
        );
        
        if (!isValidImage) {
          throw Exception('Background bytes do not appear to be a valid image file');
        }
        
        // Save image in root folder (not img/ subdirectory)
        final bgFile = File(path.join(portalDir.path, finalBgFilename));
        await bgFile.writeAsBytes(branding.backgroundBytes!, flush: true);
        
        // Verify file was written correctly
        if (!await bgFile.exists()) {
          throw Exception('Background file was not created');
        }
        
        final fileSize = await bgFile.length();
        if (fileSize != branding.backgroundBytes!.length) {
          throw Exception('Background file size mismatch: expected ${branding.backgroundBytes!.length}, got $fileSize');
        }
        
        if (fileSize == 0) {
          throw Exception('Background file is empty');
        }
        
        // Use relative path (no leading slash, no img/ prefix) for HTML
        backgroundPath = finalBgFilename;
      } catch (e) {
        throw Exception('Failed to write background file: $e');
      }
    }

    // Generate all HTML/CSS/JSON content with file references (not data URIs)
    final loginHtml = _loginHtml(
      branding,
      previewMode: false,
      logoPath: logoPath,
      backgroundPath: backgroundPath,
    );
    final logoutHtml = _logoutHtml(
      branding,
      logoPath: logoPath,
      backgroundPath: backgroundPath,
    );
    final statusHtml = _statusHtml(
      branding,
      backgroundPath: backgroundPath,
    );
    final errorHtml = _errorHtml(
      branding,
      logoPath: logoPath,
      backgroundPath: backgroundPath,
    );
    final aloginHtml = _aloginHtml(
      branding,
      logoPath: logoPath,
      backgroundPath: backgroundPath,
    );
    final apiJson = _apiJson(branding);
    final styleCss = _exactStyleCss(
      branding,
      false,
      backgroundPath: backgroundPath,
    );
    final md5Js = _md5Js();
    final redirectHtml = _redirectHtml();
    final rloginHtml = _rloginHtml();
    final errorsTxt = _errorsTxt();

    // Validate that all generated content is not empty
    if (loginHtml.isEmpty) {
      throw Exception('Generated login.html is empty');
    }
    if (logoutHtml.isEmpty) {
      throw Exception('Generated logout.html is empty');
    }
    if (statusHtml.isEmpty) {
      throw Exception('Generated status.html is empty');
    }
    if (errorHtml.isEmpty) {
      throw Exception('Generated error.html is empty');
    }
    if (aloginHtml.isEmpty) {
      throw Exception('Generated alogin.html is empty');
    }
    if (apiJson.isEmpty) {
      throw Exception('Generated api.json is empty');
    }
    if (styleCss.isEmpty) {
      throw Exception('Generated style.css is empty');
    }
    if (md5Js.isEmpty) {
      throw Exception('Generated md5.js is empty');
    }
    if (redirectHtml.isEmpty) {
      throw Exception('Generated redirect.html is empty');
    }
    if (rloginHtml.isEmpty) {
      throw Exception('Generated rlogin.html is empty');
    }
    if (errorsTxt.isEmpty) {
      throw Exception('Generated errors.txt is empty');
    }

    // Helper function to write text files with UTF-8 encoding and verification
    Future<void> _writeTextFile(String filePath, String content, String fileType) async {
      try {
        final file = File(filePath);
        
        // Normalize line endings for consistent output
        final normalizedContent = _normalizeLineEndings(content);
        
        // Write with explicit UTF-8 encoding and flush
        await file.writeAsString(
          normalizedContent,
          encoding: utf8,
          flush: true,
          mode: FileMode.writeOnly,
        );
        
        // Verify file was written correctly
        if (!await file.exists()) {
          throw Exception('$fileType file was not created');
        }
        
        // Verify content matches (read back and compare)
        final writtenContent = await file.readAsString(encoding: utf8);
        if (writtenContent != normalizedContent) {
          throw Exception('$fileType file content verification failed');
        }
      } catch (e) {
        throw Exception('Failed to write $fileType file: $e');
      }
    }

    // Write all files with explicit UTF-8 encoding and verification
    try {
      await _writeTextFile(
        path.join(portalDir.path, 'login.html'),
        loginHtml,
        'login.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'logout.html'),
        logoutHtml,
        'logout.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'status.html'),
        statusHtml,
        'status.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'error.html'),
        errorHtml,
        'error.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'alogin.html'),
        aloginHtml,
        'alogin.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'api.json'),
        apiJson,
        'api.json',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'md5.js'),
        md5Js,
        'md5.js',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'redirect.html'),
        redirectHtml,
        'redirect.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'rlogin.html'),
        rloginHtml,
        'rlogin.html',
      );
      await _writeTextFile(
        path.join(portalDir.path, 'errors.txt'),
        errorsTxt,
        'errors.txt',
      );
      await _writeTextFile(
        path.join(cssDir.path, 'style.css'),
        styleCss,
        'style.css',
      );
    } catch (e) {
      // Clean up on error
      try {
        if (await portalDir.exists()) {
          await portalDir.delete(recursive: true);
        }
      } catch (_) {
        // Ignore cleanup errors
      }
      rethrow;
    }

    // Final verification that all required files exist
    final requiredFiles = [
      path.join(portalDir.path, 'login.html'),
      path.join(portalDir.path, 'logout.html'),
      path.join(portalDir.path, 'status.html'),
      path.join(portalDir.path, 'error.html'),
      path.join(portalDir.path, 'alogin.html'),
      path.join(portalDir.path, 'api.json'),
      path.join(portalDir.path, 'md5.js'),
      path.join(portalDir.path, 'redirect.html'),
      path.join(portalDir.path, 'rlogin.html'),
      path.join(portalDir.path, 'errors.txt'),
      path.join(cssDir.path, 'style.css'),
    ];
    
    for (final filePath in requiredFiles) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Required file missing: ${path.basename(filePath)}');
      }
    }

    return portalDir.path;
  }

  /// Upload portal folder via FTP (fast and reliable transfer)
  /// 
  /// This method uploads the entire portal folder structure to the FTP server.
  /// It handles directory creation and recursive file uploads automatically.
  /// 
  /// Example:
  /// ```dart
  /// await HotspotPortalService.uploadPortalViaFtp(
  ///   portalFolderPath: '/tmp/mikrotap_portal',
  ///   ftpHost: '192.168.1.1',
  ///   ftpUsername: 'admin',
  ///   ftpPassword: 'password',
  ///   ftpPort: 21,
  ///   remotePath: '/mikrotap_portal',
  /// );
  /// ```
  static Future<void> uploadPortalViaFtp({
    required String portalFolderPath,
    required String ftpHost,
    required String ftpUsername,
    required String ftpPassword,
    int ftpPort = 21,
    String remotePath = '/mikrotap_portal',
  }) async {
    final ftp = FTPConnect(ftpHost, port: ftpPort, user: ftpUsername, pass: ftpPassword);
    
    try {
      await ftp.connect();
      
      // CRITICAL: Ensure binary transfer mode to prevent image corruption
      // ASCII mode would corrupt binary files by converting line endings
      // The ftpconnect library should default to binary for binary files,
      // but we attempt to set it explicitly if the API supports it
      try {
        await ftp.setTransferType(TransferType.binary);
      } catch (e) {
        // If setTransferType is not available, the library should default to binary mode
        // for binary file extensions (.png, .jpg, .gif, .webp, etc.)
        // This is acceptable as most modern FTP libraries handle this correctly
      }
      
      // Change to remote directory (create if needed)
      try {
        await ftp.changeDirectory(remotePath);
      } catch (e) {
        // Directory might not exist, try to create it
        await ftp.makeDirectory(remotePath);
        await ftp.changeDirectory(remotePath);
      }

      // Upload all files recursively
      await _uploadDirectoryRecursive(ftp, Directory(portalFolderPath), remotePath);
      
      await ftp.disconnect();
    } catch (e) {
      await ftp.disconnect();
      rethrow;
    }
  }

  /// Recursively upload directory contents via FTP
  static Future<void> _uploadDirectoryRecursive(
    FTPConnect ftp,
    Directory localDir,
    String remoteBasePath,
  ) async {
    final entries = localDir.listSync(recursive: false);
    
    for (final entry in entries) {
      if (entry is File) {
        final relativePath = path.relative(entry.path, from: localDir.path);
        final remoteDir = path.dirname(path.join(remoteBasePath, relativePath)).replaceAll('\\', '/');
        
        // Ensure parent directory exists on remote
        if (remoteDir != remoteBasePath) {
          try {
            await ftp.changeDirectory(remoteDir);
          } catch (e) {
            // Create directory structure if needed
            final parts = remoteDir.split('/').where((p) => p.isNotEmpty).toList();
            String currentPath = '';
            for (final part in parts) {
              currentPath = currentPath.isEmpty ? '/$part' : '$currentPath/$part';
              try {
                await ftp.changeDirectory(currentPath);
              } catch (e) {
                await ftp.makeDirectory(currentPath);
                await ftp.changeDirectory(currentPath);
              }
            }
          }
        } else {
          // Change back to base directory
          await ftp.changeDirectory(remoteBasePath);
        }
        
        // Upload file in binary mode (critical for images - prevents corruption)
        // Ensure we're in binary mode before uploading binary files
        try {
          await ftp.setTransferType(TransferType.binary);
        } catch (e) {
          // Some FTP servers might not support explicit binary mode setting
          // but most modern FTP clients default to binary for binary files
        }
        
        // Upload file with explicit remote name to ensure correct path
        final remoteFileName = path.basename(entry.path);
        await ftp.uploadFile(entry, sRemoteName: remoteFileName);
      } else if (entry is Directory) {
        final relativePath = path.relative(entry.path, from: localDir.path);
        final remotePath = path.join(remoteBasePath, relativePath).replaceAll('\\', '/');
        
        // Create remote directory structure
        final parts = remotePath.split('/').where((p) => p.isNotEmpty).toList();
        String currentPath = '';
        for (final part in parts) {
          currentPath = currentPath.isEmpty ? '/$part' : '$currentPath/$part';
          try {
            await ftp.changeDirectory(currentPath);
          } catch (e) {
            await ftp.makeDirectory(currentPath);
            await ftp.changeDirectory(currentPath);
          }
        }
        
        // Recursively upload subdirectory
        await _uploadDirectoryRecursive(ftp, entry, remotePath);
      }
    }
  }

  /// Apply portal to router via FTP upload.
  /// 
  /// - Builds portal folder locally with actual image files (no base64 encoding)
  /// - Uploads entire folder via FTP (fast and reliable)
  /// - Configures hotspot profile to use the portal
  /// 
  /// Example:
  /// ```dart
  /// await HotspotPortalService.applyPortal(
  ///   routerClient,
  ///   branding: myBranding,
  ///   ftpHost: '192.168.1.1',
  ///   ftpUsername: 'admin',
  ///   ftpPassword: 'password',
  ///   ftpPort: 21,
  ///   ftpRemotePath: '/mikrotap_portal',
  /// );
  /// ```
  static Future<void> applyPortal(
    RouterOsApiClient c, {
    required PortalBranding branding,
    required String ftpHost,
    required String ftpUsername,
    required String ftpPassword,
    int ftpPort = 21,
    String? ftpRemotePath,
  }) async {
    // Use static directory name for easier management (MikroTicket style)
    const directoryName = 'mikrotap_portal';

    // Build portal folder locally
    final portalFolderPath = await buildPortalFolder(branding: branding);
    
    // Upload via FTP
    await uploadPortalViaFtp(
      portalFolderPath: portalFolderPath,
      ftpHost: ftpHost,
      ftpUsername: ftpUsername,
      ftpPassword: ftpPassword,
      ftpPort: ftpPort,
      remotePath: ftpRemotePath ?? '/$directoryName',
    );
    
    // Point Hotspot Profile to this folder
    final profileId = await c.findId(
      '/ip/hotspot/profile/print',
      key: 'name',
      value: 'mikrotap',
    );
    if (profileId != null) {
      await c.setById(
        '/ip/hotspot/profile/set',
        id: profileId,
        attrs: {
          'html-directory': directoryName,
          'login-by': 'cookie,http-chap,http-pap',
        },
      );
    }
  }

  /// Builds the same `login.html` content we upload to RouterOS, but with
  /// MikroTik variables replaced by placeholders so it can be rendered in-app
  /// (WebView preview).
  static String buildLoginHtmlPreview({
    required PortalBranding branding,
    bool isGridPreview = false,
  }) {
    return _loginHtml(
      branding,
      previewMode: true,
      isGridPreview: isGridPreview,
    );
  }


  // EXACT REPRODUCTION OF THE TABBED LOGIN HTML (MikroTicket style)
  static String _loginHtml(
    PortalBranding b, {
    bool previewMode = false,
    bool isGridPreview = false,
    String? logoPath,
    String? backgroundPath,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primaryHex = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();

    // 1. Handle Colors and Backgrounds
    // Use file paths when provided (FTP upload), otherwise fall back to data URIs (preview/legacy)
    final backgroundRef = backgroundPath ?? b.backgroundDataUri;
    final bgCss = template.generateBackgroundCss(
      primaryHex: primaryHex,
      backgroundDataUri: backgroundRef,
    );
    // Ensure background image doesn't repeat and covers properly on all screen sizes
    final hasBackgroundImage = backgroundRef != null && backgroundRef.isNotEmpty;
    // For background images, completely remove 'fixed' from shorthand to prevent repeating on wide screens
    String processedBgCss = bgCss;
    if (hasBackgroundImage) {
      // Remove 'fixed' from the end (most common case: "no-repeat fixed")
      processedBgCss = processedBgCss.replaceAll(RegExp(r'\s+fixed\s*$'), '');
      // Also handle any other occurrences
      processedBgCss = processedBgCss.replaceAll(RegExp(r'\bfixed\b'), '');
      processedBgCss = processedBgCss.trim();
    }
    // Use explicit properties to ensure proper control - don't duplicate width/max-width/min-height
    final bgStyle = hasBackgroundImage
        ? 'background: $processedBgCss !important; background-size: cover !important; background-position: center center !important; background-repeat: no-repeat !important; background-attachment: scroll !important;'
        : 'background: $bgCss !important;';

    // 2. Handle Logo Data - Use file path when provided (FTP upload), otherwise data URI (preview)
    final logoSrc = logoPath ?? b.logoDataUri ?? '';
    final showLogo = logoSrc.isNotEmpty;

    // 3. Mock Variables for Preview
    final formAction = previewMode ? '#' : r'$(link-login-only)';
    final usernameVal = previewMode ? '' : r'value="$(username)" ';

    // Logic Stripping - RouterOS variables (no backslashes, RouterOS processes these)
    final ifChapStart = previewMode ? '' : r'$(if chap-id)';
    final ifChapEnd = previewMode ? '' : r'$(endif)';
    // Build form opening tag - construct completely to avoid $ interpolation conflicts
    final formOpenTag = previewMode
        ? '<form name="login" action="$formAction" method="post" onsubmit="return doLogin()" id="loginForm">'
        : '<form name="login" action="$formAction" method="post" \$(if chap-id)onsubmit="return doLogin()"\$(endif) id="loginForm">';
    final errorBlock = previewMode
        ? '<p class="info">Welcome to $title</p>'
        : r'$(if error)<p class="info alert">$(error)</p>$(endif)';

    // CSS: inline in preview, external link for router
    final cssLink = previewMode
        ? ''
        : '<link rel="stylesheet" href="css/style.css">';
    final cssContent = previewMode
        ? template.generatePreviewCss(
            primaryHex: primaryHex,
            backgroundDataUri: backgroundRef,
            cardOpacity: b.cardOpacity,
            borderWidth: b.borderWidth,
            borderStyle: b.borderStyle,
            borderRadius: b.borderRadius,
          )
        : '';

    // Add zoom wrapper for preview mode to fit in WebView (only affects preview, not router)
    // Editor preview uses larger scale (0.65) for better visibility, grid uses smaller (0.5)
    final previewScale = previewMode ? (isGridPreview ? 0.5 : 0.70) : 1.0;
    final previewWidth = previewMode
        ? (100 / previewScale).toStringAsFixed(2)
        : '100';
    final previewHeight = previewMode
        ? (100 / previewScale).toStringAsFixed(2)
        : '100';
    final previewWrapperStart = previewMode
        ? '<div style="transform: scale($previewScale); transform-origin: center center; width: ${previewWidth}%; height: ${previewHeight}%; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%) scale($previewScale);">'
        : '';
    final previewWrapperEnd = previewMode ? '</div>' : '';

    return '''
<!doctype html>
<html lang="en" style="margin:0; padding:0; width:100%; max-width:100%; overflow-x:hidden; box-sizing:border-box;">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <title>$title</title>
    $cssLink
    ${previewMode ? '<style>$cssContent</style>' : ''}
</head>
<body style="$bgStyle; margin:0; padding:0; width:100%; max-width:100%; min-height:100vh; overflow-x:hidden; overflow-y:auto; box-sizing:border-box;${previewMode ? ' position: relative;' : ''}">
    $previewWrapperStart
    $ifChapStart
    <form name="sendin" action="$formAction" method="post" style="display:none">
        <input type="hidden" name="username" />
        <input type="hidden" name="password" />
        <input type="hidden" name="dst" value="" />
        <input type="hidden" name="popup" value="true" />
    </form>
    ${previewMode ? '<script>${_md5Js()}</script>' : '<script src="md5.js"></script>'}
    <script>
        function doLogin() {
            document.sendin.username.value = document.login.username.value;
            var chal = '${previewMode ? "123" : r"$(chap-challenge)"}';
            var cid = '${previewMode ? "abc" : r"$(chap-id)"}';
            document.sendin.password.value = hexMD5(cid + document.login.password.value + chal);
            document.sendin.submit();
            return false;
        }
    </script>
    $ifChapEnd

    <div class="main"${previewMode ? (isGridPreview ? ' style="padding-top: 200px;"' : ' style="padding-top: 200px;"') : ''}>
        <div class="wrap animated fadeIn">
            ${showLogo ? '<div style="text-align: center; margin-bottom:15px;"><img src="$logoSrc" style="border-radius:10px; width:80px; height:80px; object-fit: cover; border: 2px solid rgba(255,255,255,0.2);" alt="logo"/></div>' : ''}
            
            <div class="form-container">
                <ul class="tabs">
                    <li class="tab active" id="tPin" onclick="switchTab('pin')">🔑 PIN</li>
                    <li class="tab" id="tUser" onclick="switchTab('user')">👤 User</li>
                </ul>
            
                $formOpenTag
                    $errorBlock
                    <label>
                        <input name="username" id="mainInput" class="input-text" type="text" $usernameVal placeholder="PIN Code" autocomplete="off" />
                    </label>
            
                    <label id="passWrapper" style="display: none;">
                        <input name="password" id="passInput" class="input-text" type="password" placeholder="Password" />
                    </label>
            
                    <input type="submit" value="Connect" class="button-submit"/>
                </form>
            </div>

            ${b.supportText.isNotEmpty ? '''
            <div class="info-section">
                <div class="info-content">
                    ${_escapeHtml(b.supportText).replaceAll('\n', '<br>')}
                </div>
            </div>
            ''' : ''}

            <script>
                var mode = 'pin';
                function switchTab(t) {
                    mode = t;
                    document.getElementById('tPin').className = (t === 'pin') ? 'tab active' : 'tab';
                    document.getElementById('tUser').className = (t === 'user') ? 'tab active' : 'tab';
                    document.getElementById('passWrapper').style.display = (t === 'pin') ? 'none' : 'block';
                    document.getElementById('mainInput').placeholder = (t === 'pin') ? 'PIN Code' : 'Username';
                }
                document.getElementById('loginForm').onsubmit = function() {
                    if(mode === 'pin') {
                        document.getElementById('passInput').value = document.getElementById('mainInput').value;
                    }
                    return true;
                };
            </script>

            <div style="padding:10px; text-align: center;">
                <p style="color: white; font-size: 11px; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); margin:0;">Powered by MikroTap</p>
            </div>
        </div>
    </div>
    $previewWrapperEnd
</body>
</html>
''';
  }

  // EXACT REPRODUCTION OF THE style.css (MikroTicket style)
  static String _exactStyleCss(
    PortalBranding b,
    bool previewMode, {
    String? backgroundPath,
  }) {
    final template = getTemplateById(b.themeId);
    final primaryHex = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();

    // Use file path when provided (FTP upload), otherwise fall back to data URI (preview/legacy)
    String? backgroundRef = backgroundPath ?? b.backgroundDataUri;

    // FIX: If we are not in preview mode (meaning we are generating the external style.css file),
    // and we are using a relative file path (like "background.jpg"), 
    // we must prepend "../" because the CSS file lives in the "css/" folder 
    // but the images live in the root folder (one level up from css/).
    if (!previewMode && backgroundRef != null && !backgroundRef.startsWith('data:')) {
      backgroundRef = '../$backgroundRef';
    }

    // For router mode, return the template CSS
    if (!previewMode) {
      String routerCss = template.generateRouterCss(
        primaryHex: primaryHex,
        backgroundDataUri: backgroundRef,
        cardOpacity: b.cardOpacity,
        borderWidth: b.borderWidth,
        borderStyle: b.borderStyle,
        borderRadius: b.borderRadius,
      );
      
      // Remove 'background-attachment: fixed' to match preview behavior
      // Fixed attachment can cause issues on mobile devices and doesn't match preview
      // Remove as separate property: "background-attachment: fixed;"
      routerCss = routerCss.replaceAll(RegExp(r'\s*background-attachment:\s*fixed\s*;?'), '');
      // Remove from shorthand: "url(...) ... fixed" at end of background value
      routerCss = routerCss.replaceAll(RegExp(r'(\s+)fixed(\s*[;}]|\s*$)'), r'$1$2');
      
      return routerCss;
    }

    // For preview mode, return optimized CSS with overflow control
    return template.generatePreviewCss(
      primaryHex: primaryHex,
      backgroundDataUri: backgroundRef,
      cardOpacity: b.cardOpacity,
      borderWidth: b.borderWidth,
      borderStyle: b.borderStyle,
      borderRadius: b.borderRadius,
    );
  }

  static String _logoutHtml(
    PortalBranding b, {
    String? logoPath,
    String? backgroundPath,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final backgroundRef = backgroundPath ?? b.backgroundDataUri;
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: backgroundRef,
    );
    final card = template.generateCardCss(
      primaryHex: primary,
      opacity: b.cardOpacity,
    );
    final text = template.generateTextCss();
    final muted = template.generateMutedCss();
    final logo = logoPath ?? b.logoDataUri;
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:$text; }
    .wrap{ max-width:420px; margin:0 auto; padding:28px 16px; min-height:100vh; display:grid; place-items:center; }
    .card{ width:100%; background:$card; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .btn{ width:100%; padding:12px 14px; border:0; border-radius:12px; background:$primary; color:white; font-weight:700; }
    .muted{ color:$muted; font-size:13px; }
    .brand{ display:flex; align-items:center; gap:10px; margin-bottom:12px; }
    .dot{ width:10px; height:10px; border-radius:999px; background:$primary; box-shadow:0 0 0 6px rgba(37,99,235,.18); }
    .logo { width: 40px; height: 40px; border-radius: 12px; object-fit: cover; border: 1px solid rgba(148,163,184,.18); background: rgba(2,6,23,.35); }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="brand">
        ${logo == null ? '<div class="dot"></div>' : '<img class="logo" src="$logo" alt="logo" />'}
        <div style="font-weight:800;">$title</div>
      </div>
      <h2 style="margin:0 0 8px;">Disconnected</h2>
      <div class="muted">You can close this page.</div>
      <div style="height:12px;"></div>
      <form action="\$(link-login)" method="post">
        <button class="btn" type="submit">Log in again</button>
      </form>
    </div>
  </div>
</body>
</html>
''';
  }

  static String _statusHtml(
    PortalBranding b, {
    String? backgroundPath,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final backgroundRef = backgroundPath ?? b.backgroundDataUri;
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: backgroundRef,
    );
    final card = template.generateCardCss(
      primaryHex: primary,
      opacity: b.cardOpacity,
    );
    final text = template.generateTextCss();
    final muted = template.generateMutedCss();
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title</title>
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:$text; }
    .wrap{ max-width:520px; margin:0 auto; padding:28px 16px; }
    .card{ background:$card; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .muted{ color:$muted; font-size:13px; }
    table{ width:100%; border-collapse:collapse; margin-top:12px; }
    td{ padding:8px 0; border-bottom:1px solid rgba(148,163,184,.12); }
    td:first-child{ color:$muted; width:38%; }
    a{ color:$primary; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h2 style="margin:0 0 6px;">Status</h2>
      <div class="muted">Session information.</div>
      <table>
        <tr><td>IP</td><td>\$(ip)</td></tr>
        <tr><td>MAC</td><td>\$(mac)</td></tr>
        <tr><td>User</td><td>\$(username)</td></tr>
        <tr><td>Uptime</td><td>\$(uptime)</td></tr>
        <tr><td>Bytes in</td><td>\$(bytes-in-nice)</td></tr>
        <tr><td>Bytes out</td><td>\$(bytes-out-nice)</td></tr>
      </table>
      <div style="height:12px;"></div>
      <a class="muted" href="\$(link-logout)">Logout</a>
    </div>
  </div>
</body>
</html>
''';
  }

  // MD5 JavaScript implementation (required for http-chap login)
  static String _md5Js() {
    // This is a minimal MD5 implementation for RouterOS compatibility
    // Full implementation would be longer, but this provides the hexMD5 function
    return '''
function hexMD5(s) {
  function md5cycle(x, k) {
    var a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936);
    d = ff(d, a, b, c, k[1], 12, -389564586);
    c = ff(c, d, a, b, k[2], 17, 606105819);
    b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897);
    d = ff(d, a, b, c, k[5], 12, 1200080426);
    c = ff(c, d, a, b, k[6], 17, -1473231341);
    b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416);
    d = ff(d, a, b, c, k[9], 12, -1958414417);
    c = ff(c, d, a, b, k[10], 17, -42063);
    b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682);
    d = ff(d, a, b, c, k[13], 12, -40341101);
    c = ff(c, d, a, b, k[14], 17, -1502002290);
    b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510);
    d = gg(d, a, b, c, k[6], 9, -1069501632);
    c = gg(c, d, a, b, k[11], 14, 643717713);
    b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691);
    d = gg(d, a, b, c, k[10], 9, 38016083);
    c = gg(c, d, a, b, k[15], 14, -660478335);
    b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438);
    d = gg(d, a, b, c, k[14], 9, -1019803690);
    c = gg(c, d, a, b, k[3], 14, -187363961);
    b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467);
    d = gg(d, a, b, c, k[2], 9, -51403784);
    c = gg(c, d, a, b, k[7], 14, 1735328473);
    b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558);
    d = hh(d, a, b, c, k[8], 11, -2022574463);
    c = hh(c, d, a, b, k[11], 16, 1839030562);
    b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060);
    d = hh(d, a, b, c, k[4], 11, 1272893353);
    c = hh(c, d, a, b, k[7], 16, -155497632);
    b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174);
    d = hh(d, a, b, c, k[0], 11, -358537222);
    c = hh(c, d, a, b, k[3], 16, -722521979);
    b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487);
    d = hh(d, a, b, c, k[12], 11, -421815835);
    c = hh(c, d, a, b, k[15], 16, 530742520);
    b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844);
    d = ii(d, a, b, c, k[7], 10, 1126891415);
    c = ii(c, d, a, b, k[14], 15, -1416354905);
    b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571);
    d = ii(d, a, b, c, k[3], 10, -1894986606);
    c = ii(c, d, a, b, k[10], 15, -1051523);
    b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359);
    d = ii(d, a, b, c, k[15], 10, -30611744);
    c = ii(c, d, a, b, k[6], 15, -1560198380);
    b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070);
    d = ii(d, a, b, c, k[11], 10, -1120210379);
    c = ii(c, d, a, b, k[2], 15, 718787259);
    b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add32(a, x[0]);
    x[1] = add32(b, x[1]);
    x[2] = add32(c, x[2]);
    x[3] = add32(d, x[3]);
  }
  function cmn(q, a, b, x, s, t) {
    a = add32(add32(a, q), add32(x, t));
    return add32((a << s) | (a >>> (32 - s)), b);
  }
  function ff(a, b, c, d, x, s, t) {
    return cmn((b & c) | ((~b) & d), a, b, x, s, t);
  }
  function gg(a, b, c, d, x, s, t) {
    return cmn((b & d) | (c & (~d)), a, b, x, s, t);
  }
  function hh(a, b, c, d, x, s, t) {
    return cmn(b ^ c ^ d, a, b, x, s, t);
  }
  function ii(a, b, c, d, x, s, t) {
    return cmn(c ^ (b | (~d)), a, b, x, s, t);
  }
  function add32(a, b) {
    return (a + b) & 0xFFFFFFFF;
  }
  function rhex(n) {
    var s = '', j = 0;
    for (; j < 4; j++)
      s += hex_chr[(n >> (j * 8 + 4)) & 0x0F] + hex_chr[(n >> (j * 8)) & 0x0F];
    return s;
  }
  var hex_chr = '0123456789abcdef'.split('');
  function md5(s) {
    return hex(md51(s));
  }
  function md51(s) {
    var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
    for (i = 64; i <= s.length; i += 64) {
      md5cycle(state, md5blk(s.substring(i - 64, i)));
    }
    s = s.substring(i - 64);
    var tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (i = 0; i < s.length; i++)
      tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) {
      md5cycle(state, tail);
      for (i = 0; i < 16; i++) tail[i] = 0;
    }
    tail[14] = n * 8;
    md5cycle(state, tail);
    return state;
  }
  function md5blk(s) {
    var md5blk = [];
    for (var i = 0; i < 64; i += 4) {
      md5blk[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
    }
    return md5blk;
  }
  function hex(x) {
    for (var i = 0; i < x.length; i++)
      x[i] = rhex(x[i]);
    return x.join('');
  }
  return md5(s);
}
''';
  }

  /// Generate api.json for captive portal detection
  /// This is used by iOS/Android to detect if they're behind a captive portal
  static String _apiJson(PortalBranding b) {
    // Simple format matching the example - essential for captive portal detection
    return '''{"captive": \$(if logged-in == "yes")false\$(else)true\$(endif)}''';
  }

  /// Generate error.html for error handling
  static String _errorHtml(
    PortalBranding b, {
    String? logoPath,
    String? backgroundPath,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final backgroundRef = backgroundPath ?? b.backgroundDataUri;
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: backgroundRef,
    );
    final card = template.generateCardCss(
      primaryHex: primary,
      opacity: b.cardOpacity,
    );
    final text = template.generateTextCss();
    final muted = template.generateMutedCss();
    final logo = logoPath ?? b.logoDataUri;
    
    return '''<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>$title - Error</title>
  <link rel="stylesheet" href="css/style.css">
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:$text; }
    .wrap{ max-width:420px; margin:0 auto; padding:28px 16px; min-height:100vh; display:grid; place-items:center; }
    .card{ width:100%; background:$card; border:1px solid rgba(148,163,184,.15); border-radius:18px; padding:18px; }
    .btn{ width:100%; padding:12px 14px; border:0; border-radius:12px; background:$primary; color:white; font-weight:700; margin-top:12px; }
    .muted{ color:$muted; font-size:13px; }
    .brand{ display:flex; align-items:center; gap:10px; margin-bottom:12px; }
    .dot{ width:10px; height:10px; border-radius:999px; background:$primary; box-shadow:0 0 0 6px rgba(37,99,235,.18); }
    .logo { width: 40px; height: 40px; border-radius: 12px; object-fit: cover; border: 1px solid rgba(148,163,184,.18); background: rgba(2,6,23,.35); }
    .error { color: #ef4444; font-weight: 600; margin: 12px 0; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="brand">
        ${logo == null ? '<div class="dot"></div>' : '<img class="logo" src="$logo" alt="logo" />'}
        <div style="font-weight:800;">$title</div>
      </div>
      <h2 style="margin:0 0 8px;">Error</h2>
      \$(if error)
      <div class="error">\$(error)</div>
      \$(else)
      <div class="muted">An error occurred. Please try again.</div>
      \$(endif)
      <div style="height:12px;"></div>
      <form action="\$(link-login)" method="post">
        <button class="btn" type="submit">Return to Login</button>
      </form>
    </div>
  </div>
</body>
</html>''';
  }

  /// Generate alogin.html for XML-based alternative login (for devices that prefer XML)
  static String _aloginHtml(
    PortalBranding b, {
    String? logoPath,
    String? backgroundPath,
  }) {
    final title = _escapeHtml(b.title);
    final template = getTemplateById(b.themeId);
    final primary = b.primaryHex.trim().isEmpty
        ? template.defaultPrimaryHex
        : b.primaryHex.trim();
    final backgroundRef = backgroundPath ?? b.backgroundDataUri;
    final bg = template.generateBackgroundCss(
      primaryHex: primary,
      backgroundDataUri: backgroundRef,
    );
    final logo = logoPath ?? b.logoDataUri;
    
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>$title</title>
  <link rel="stylesheet" href="css/style.css">
  <style>
    body { margin:0; font-family: -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial; background:$bg; background-size: cover; background-position: center; color:#fff; }
    .wrap{ max-width:420px; margin:0 auto; padding:28px 16px; min-height:100vh; display:grid; place-items:center; }
    .card{ width:100%; background:rgba(255,255,255,0.1); backdrop-filter: blur(10px); border:1px solid rgba(255,255,255,0.2); border-radius:18px; padding:24px; }
    .input-text{ width:100%; padding:12px 14px; border:1px solid rgba(255,255,255,0.3); border-radius:12px; background:rgba(255,255,255,0.1); color:#fff; font-size:14px; margin-bottom:12px; box-sizing:border-box; }
    .input-text::placeholder{ color:rgba(255,255,255,0.6); }
    .btn{ width:100%; padding:12px 14px; border:0; border-radius:12px; background:$primary; color:white; font-weight:700; font-size:14px; cursor:pointer; }
    .muted{ color:rgba(255,255,255,0.7); font-size:13px; text-align:center; margin-top:12px; }
    .brand{ display:flex; align-items:center; gap:10px; margin-bottom:16px; justify-content:center; }
    .logo { width: 50px; height: 50px; border-radius: 12px; object-fit: cover; border: 2px solid rgba(255,255,255,0.3); }
    .error { color: #ff6b6b; font-size: 13px; margin-bottom: 12px; text-align: center; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="brand">
        ${logo == null ? '' : '<img class="logo" src="$logo" alt="logo" />'}
        <div style="font-weight:800; font-size:20px;">$title</div>
      </div>
      \$(if error)
      <div class="error">\$(error)</div>
      \$(endif)
      <form action="\$(link-login-only)" method="post">
        <input type="text" name="username" class="input-text" placeholder="Username" value="\$(username)" autocomplete="off" />
        <input type="password" name="password" class="input-text" placeholder="Password" autocomplete="off" />
        <input type="hidden" name="dst" value="\$(link-orig)" />
        <button type="submit" class="btn">Connect</button>
      </form>
      <div class="muted">Need help? Contact the attendant.</div>
    </div>
  </div>
</body>
</html>''';
  }

  /// Generate redirect.html for captive portal detection (essential for iOS/Android)
  static String _redirectHtml() {
    return '''<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=\$(link-redirect)">
</head>
<body>
    <p>Redirecting...</p>
</body>
</html>''';
  }

  /// Generate rlogin.html for captive portal detection (essential for iOS/Android)
  static String _rloginHtml() {
    return '''<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=\$(link-redirect)">
</head>
<body>
    <p>Redirecting...</p>
</body>
</html>''';
  }

  /// Generate errors.txt for error message mapping
  static String _errorsTxt() {
    return '''invalid-username = Invalid PIN or Password
user-session-limit = Device limit reached
invalid-password = Invalid password
session-timeout = Session expired
''';
  }

  static String _escapeHtml(String s) {
    // Escape & first to avoid double-escaping existing entities
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Normalize line endings to ensure consistent output across platforms
  static String _normalizeLineEndings(String content) {
    // Convert all line endings to \n, then ensure consistent \n usage
    return content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }
}
