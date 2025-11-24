import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';

// API Client Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

// Note: webSocketClientProvider is defined in message_provider.dart
// It reuses the WebSocketClient from ApiClient to avoid duplicate connections
