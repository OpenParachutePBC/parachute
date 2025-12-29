import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parachute_chat/core/services/file_system_service.dart';
import 'package:parachute_chat/core/services/export_detection_service.dart';
import 'package:parachute_chat/core/services/vault_state_service.dart';
import 'package:parachute_chat/core/services/conversation_import_service.dart';
import 'package:parachute_chat/core/services/performance_service.dart';

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

/// Provider for the ExportDetectionService
final exportDetectionServiceProvider = Provider<ExportDetectionService>((ref) {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  return ExportDetectionService(fileSystem);
});

/// Provider that scans for available exports
final availableExportsProvider = FutureProvider<List<DetectedExport>>((ref) async {
  final service = ref.watch(exportDetectionServiceProvider);
  return service.scanForExports();
});

/// Provider that checks if any exports are available
final hasExportsProvider = FutureProvider<bool>((ref) async {
  final exports = await ref.watch(availableExportsProvider.future);
  return exports.isNotEmpty;
});

/// Provider for VaultStateService
final vaultStateServiceProvider = Provider<VaultStateService>((ref) {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  return VaultStateService(fileSystem);
});

/// Provider for current vault state
final vaultStateProvider = FutureProvider<VaultState>((ref) async {
  final service = ref.watch(vaultStateServiceProvider);
  return service.loadState();
});

/// Provider to check if vault needs capture phase setup
/// (Different from vaultNeedsSetupProvider in context_providers which checks AGENTS.md)
final vaultCaptureNeedsSetupProvider = FutureProvider<bool>((ref) async {
  final state = await ref.watch(vaultStateProvider.future);
  return state.needsSetup;
});

/// Provider to check if agent initialization is needed
final vaultNeedsAgentInitProvider = FutureProvider<bool>((ref) async {
  final state = await ref.watch(vaultStateProvider.future);
  return state.needsAgentInit;
});

/// Provider for ConversationImportService
final conversationImportServiceProvider = Provider<ConversationImportService>((ref) {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  return ConversationImportService(fileSystem);
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
