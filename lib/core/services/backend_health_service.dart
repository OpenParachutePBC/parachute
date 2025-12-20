import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Service for checking backend server health
class BackendHealthService {
  final Dio _dio;

  BackendHealthService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  /// Check if backend server is reachable and healthy
  Future<ServerHealthStatus> checkHealth(String serverUrl) async {
    try {
      debugPrint('[BackendHealth] Checking health at: $serverUrl/api/health');

      final response = await _dio.get(
        '$serverUrl/api/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final status = data['status'] as String?;
        final version = data['version'] as String?;
        final acpEnabled = data['acp_enabled'] as bool? ?? false;

        if (status == 'ok') {
          debugPrint(
            '[BackendHealth] ✅ Server healthy - version: $version, ACP: $acpEnabled',
          );
          return ServerHealthStatus.connected(
            version: version,
            acpEnabled: acpEnabled,
          );
        }
      }

      debugPrint(
        '[BackendHealth] ⚠️ Unexpected response: ${response.statusCode}',
      );
      return ServerHealthStatus(
        isHealthy: false,
        message: 'Server responded with status ${response.statusCode}',
        connectionState: ServerConnectionState.error,
      );
    } on DioException catch (e) {
      debugPrint(
        '[BackendHealth] ❌ Connection failed: ${e.type} - ${e.message}',
      );

      // Differentiate between timeout, network error, and server offline
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return ServerHealthStatus.timeout();

        case DioExceptionType.connectionError:
          // Check if it's a network issue vs server just not running
          final errorMessage = e.message?.toLowerCase() ?? '';
          if (errorMessage.contains('no internet') ||
              errorMessage.contains('network is unreachable') ||
              errorMessage.contains('no route to host')) {
            return ServerHealthStatus.networkError();
          }
          // Server is likely just not running (connection refused)
          return ServerHealthStatus.serverOffline(serverUrl);

        default:
          return ServerHealthStatus(
            isHealthy: false,
            message: 'Connection error',
            error: e.message,
            connectionState: ServerConnectionState.error,
          );
      }
    } catch (e) {
      debugPrint('[BackendHealth] ❌ Unexpected error: $e');
      return ServerHealthStatus(
        isHealthy: false,
        message: 'Unexpected error',
        error: e.toString(),
        connectionState: ServerConnectionState.error,
      );
    }
  }
}

/// Connection state types for better UI feedback
enum ServerConnectionState {
  connected,      // Server is healthy and reachable
  connecting,     // Currently checking connection
  serverOffline,  // Can reach network but server not responding
  networkError,   // Cannot establish network connection at all
  timeout,        // Connection timed out
  error,          // Other error
}

/// Health status of the backend server
class ServerHealthStatus {
  final bool isHealthy;
  final String message;
  final String? version;
  final bool? acpEnabled;
  final String? error;
  final ServerConnectionState connectionState;

  ServerHealthStatus({
    required this.isHealthy,
    required this.message,
    this.version,
    this.acpEnabled,
    this.error,
    this.connectionState = ServerConnectionState.error,
  });

  /// Factory for a healthy connection
  factory ServerHealthStatus.connected({
    String? version,
    bool acpEnabled = false,
  }) {
    return ServerHealthStatus(
      isHealthy: true,
      message: 'Connected',
      version: version,
      acpEnabled: acpEnabled,
      connectionState: ServerConnectionState.connected,
    );
  }

  /// Factory for server offline
  factory ServerHealthStatus.serverOffline(String serverUrl) {
    return ServerHealthStatus(
      isHealthy: false,
      message: 'Server not responding',
      connectionState: ServerConnectionState.serverOffline,
      error: 'Cannot reach $serverUrl',
    );
  }

  /// Factory for network error
  factory ServerHealthStatus.networkError() {
    return ServerHealthStatus(
      isHealthy: false,
      message: 'No network connection',
      connectionState: ServerConnectionState.networkError,
    );
  }

  /// Factory for timeout
  factory ServerHealthStatus.timeout() {
    return ServerHealthStatus(
      isHealthy: false,
      message: 'Connection timed out',
      connectionState: ServerConnectionState.timeout,
    );
  }

  String get displayMessage {
    if (isHealthy) {
      final versionInfo = version != null ? ' (v$version)' : '';
      final acpInfo = acpEnabled == true ? ' • ACP enabled' : '';
      return 'Connected$versionInfo$acpInfo';
    }
    return message;
  }

  /// User-friendly help text based on connection state
  String get helpText {
    switch (connectionState) {
      case ServerConnectionState.connected:
        return '';
      case ServerConnectionState.connecting:
        return 'Checking server connection...';
      case ServerConnectionState.serverOffline:
        return 'Make sure the agent server is running (npm start in agent/)';
      case ServerConnectionState.networkError:
        return 'Check your network connection';
      case ServerConnectionState.timeout:
        return 'Server is slow to respond - check if it\'s overloaded';
      case ServerConnectionState.error:
        return error ?? 'An unexpected error occurred';
    }
  }
}
