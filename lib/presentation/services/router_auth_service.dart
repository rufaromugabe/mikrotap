import 'dart:async';
import 'dart:io';

import '../../data/services/routeros_api_client.dart';

/// Service for router authentication and connection verification
class RouterAuthService {
  /// Verifies router connection and re-authenticates if needed
  /// Returns true if connection is valid, false if router is dead/unreachable
  static Future<bool> verifyConnection({
    required String host,
    required String username,
    required String password,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = RouterOsApiClient(host: host, port: 8728, timeout: timeout);
    
    try {
      await client.login(username: username, password: password);
      // Test with a simple command
      final resp = await client.command(['/system/resource/print']);
      final ok = resp.any((s) => s.type == '!re');
      await client.close();
      return ok;
    } on SocketException {
      await client.close();
      return false; // Router is dead/unreachable
    } on TimeoutException {
      await client.close();
      return false; // Router is not responding
    } on RouterOsApiException {
      await client.close();
      return false; // Authentication failed
    } catch (e) {
      await client.close();
      return false; // Other error
    }
  }

  /// Re-authenticates the active router session
  /// Returns true if successful, false if router is dead or credentials invalid
  static Future<bool> reAuthenticateActiveRouter() async {
    // This will be called from a provider that has access to activeRouterProvider
    // For now, we'll return a Future that can be used with ref.read
    throw UnimplementedError('Use reAuthenticateActiveRouterProvider instead');
  }
}
