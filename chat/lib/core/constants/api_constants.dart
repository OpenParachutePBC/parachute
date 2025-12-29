/// API configuration constants
class ApiConstants {
  // Prevent instantiation
  ApiConstants._();

  /// Base URL for the backend API
  /// Can be overridden with --dart-define=API_BASE_URL=...
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  /// WebSocket URL for real-time communication
  /// Can be overridden with --dart-define=WS_URL=...
  static const String websocketUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:8080/ws',
  );

  // API Endpoints
  static const String health = '/health';
  static const String spaces = '/api/spaces';
  static const String conversations = '/api/conversations';
  static const String messages = '/api/messages';
}
