import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import '../models/quick_prompt.dart';
import '../services/vault_context_service.dart';

// ============================================================
// Service Provider
// ============================================================

/// Provider for VaultContextService
final vaultContextServiceProvider = Provider<VaultContextService>((ref) {
  final fileSystem = ref.watch(fileSystemServiceProvider);
  return VaultContextService(fileSystem);
});

// ============================================================
// Status Providers
// ============================================================

/// Check if vault context files are initialized
final vaultContextStatusProvider = FutureProvider<VaultContextStatus>((ref) async {
  final service = ref.watch(vaultContextServiceProvider);
  return service.checkStatus();
});

/// Whether vault needs setup (AGENTS.md or prompts.yaml missing)
final vaultNeedsSetupProvider = FutureProvider<bool>((ref) async {
  final status = await ref.watch(vaultContextStatusProvider.future);
  return status.needsSetup;
});

// ============================================================
// Content Providers
// ============================================================

/// Load AGENTS.md content
final agentsMdProvider = FutureProvider<String?>((ref) async {
  final service = ref.watch(vaultContextServiceProvider);
  return service.loadAgentsMd();
});

/// Load prompts from prompts.yaml
final promptsProvider = FutureProvider<List<QuickPrompt>>((ref) async {
  final service = ref.watch(vaultContextServiceProvider);
  return service.loadPrompts();
});

// ============================================================
// Actions
// ============================================================

/// Initialize default vault context files
final initializeVaultContextProvider = Provider<Future<void> Function()>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return () async {
    await service.initializeDefaults();
    // Invalidate status and content providers to refresh
    ref.invalidate(vaultContextStatusProvider);
    ref.invalidate(agentsMdProvider);
    ref.invalidate(promptsProvider);
  };
});

/// Initialize vault context with optional Claude memories
final initializeVaultWithMemoriesProvider = Provider<Future<void> Function(String?)>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return (String? memoriesContext) async {
    await service.initializeWithClaudeMemories(memoriesContext);
    // Invalidate status and content providers to refresh
    ref.invalidate(vaultContextStatusProvider);
    ref.invalidate(agentsMdProvider);
    ref.invalidate(promptsProvider);
  };
});

/// Save updated AGENTS.md content
final saveAgentsMdProvider = Provider<Future<bool> Function(String)>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return (String content) async {
    final success = await service.saveAgentsMd(content);
    if (success) {
      ref.invalidate(agentsMdProvider);
    }
    return success;
  };
});

/// Save updated prompts
final savePromptsProvider = Provider<Future<bool> Function(List<QuickPrompt>)>((ref) {
  final service = ref.watch(vaultContextServiceProvider);
  return (List<QuickPrompt> prompts) async {
    final success = await service.savePrompts(prompts);
    if (success) {
      ref.invalidate(promptsProvider);
    }
    return success;
  };
});
