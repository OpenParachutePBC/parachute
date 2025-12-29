import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parachute_daily/core/services/file_system_service.dart';
import 'package:parachute_daily/core/services/performance_service.dart';

/// Provider for the FileSystemService singleton
final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  return FileSystemService();
});

/// Provider for the vault root path
final vaultPathProvider = FutureProvider<String>((ref) async {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  await fileSystem.initialize();
  return fileSystem.getRootPath();
});

/// Provider to check if onboarding has been completed
final hasCompletedOnboardingProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('has_seen_onboarding_v1') ?? false;
});

/// Provider that initializes the performance service with vault path
///
/// Watch this provider early in the app to enable file-based performance logging.
/// Performance data is written to {vault}/.parachute/perf/
final performanceServiceProvider = FutureProvider<PerformanceService>((ref) async {
  final vaultPath = await ref.watch(vaultPathProvider.future);
  perf.init(vaultPath);

  // Ensure perf data is flushed when provider is disposed
  ref.onDispose(() {
    perf.flush();
  });

  return perf;
});
