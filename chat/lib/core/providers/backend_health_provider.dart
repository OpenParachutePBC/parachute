import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backend_health_service.dart';
import 'feature_flags_provider.dart';

/// Provider for the backend health service
final backendHealthServiceProvider = Provider<BackendHealthService>((ref) {
  return BackendHealthService();
});

/// Provider for checking server health
/// This is a future provider that checks health when requested
final serverHealthProvider = FutureProvider.family<ServerHealthStatus, String>((
  ref,
  serverUrl,
) async {
  final healthService = ref.read(backendHealthServiceProvider);
  return healthService.checkHealth(serverUrl);
});

/// Provider for periodic server health checks (when AI Chat is enabled)
/// Returns null if AI Chat is disabled
/// Uses proper disposal to prevent resource leaks
final periodicServerHealthProvider = StreamProvider<ServerHealthStatus?>((
  ref,
) {
  // Create a StreamController to manage the stream lifecycle
  final controller = StreamController<ServerHealthStatus?>();
  Timer? periodicTimer;
  bool isDisposed = false;

  // Set up disposal to cancel the timer
  ref.onDispose(() {
    isDisposed = true;
    periodicTimer?.cancel();
    controller.close();
  });

  // Start the health check logic
  () async {
    try {
      // Check if AI Chat is enabled
      final aiChatEnabled = await ref.read(aiChatEnabledProvider.future);

      if (!aiChatEnabled || isDisposed) {
        if (!isDisposed) controller.add(null);
        return;
      }

      // Get server URL
      final serverUrl = await ref.read(aiServerUrlProvider.future);
      final healthService = ref.read(backendHealthServiceProvider);

      // Initial check
      if (!isDisposed) {
        final status = await healthService.checkHealth(serverUrl);
        controller.add(status);
      }

      // Periodic checks every 30 seconds
      periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        if (isDisposed) return;
        try {
          final status = await healthService.checkHealth(serverUrl);
          if (!isDisposed) controller.add(status);
        } catch (e) {
          if (!isDisposed) {
            controller.add(ServerHealthStatus.networkError());
          }
        }
      });
    } catch (e) {
      if (!isDisposed) {
        controller.add(ServerHealthStatus.networkError());
      }
    }
  }();

  return controller.stream;
});
