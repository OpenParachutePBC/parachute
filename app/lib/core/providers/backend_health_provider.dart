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
final periodicServerHealthProvider = StreamProvider<ServerHealthStatus?>((
  ref,
) async* {
  // Check if AI Chat is enabled
  final aiChatEnabled = await ref.watch(aiChatEnabledProvider.future);

  if (!aiChatEnabled) {
    yield null;
    return;
  }

  // Get server URL
  final serverUrl = await ref.watch(aiServerUrlProvider.future);
  final healthService = ref.watch(backendHealthServiceProvider);

  // Initial check
  yield await healthService.checkHealth(serverUrl);

  // Periodic checks every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await healthService.checkHealth(serverUrl);
  }
});
