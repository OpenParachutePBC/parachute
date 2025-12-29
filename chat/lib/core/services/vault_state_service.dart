import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import 'file_system_service.dart';

/// Tracks initialization state of a Parachute vault
///
/// Manages the `.parachute/` folder which contains:
/// - state.yaml: Initialization state and tracking
///
/// This allows Parachute to work with existing vaults (like Obsidian)
/// and know what setup steps have been completed.
class VaultStateService {
  final FileSystemService _fileSystem;

  VaultStateService(this._fileSystem);

  /// Get the .parachute folder path
  Future<String> get _parachuteFolderPath async {
    final root = await _fileSystem.getRootPath();
    return '$root/.parachute';
  }

  /// Get the state.yaml path
  Future<String> get _statePath async {
    final folder = await _parachuteFolderPath;
    return '$folder/state.yaml';
  }

  /// Ensure the .parachute folder exists
  Future<void> ensureParachuteFolderExists() async {
    final folderPath = await _parachuteFolderPath;
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
      debugPrint('[VaultStateService] Created .parachute folder');
    }
  }

  /// Check if this vault has been initialized by Parachute at all
  Future<bool> isParachuteVault() async {
    final folderPath = await _parachuteFolderPath;
    return Directory(folderPath).exists();
  }

  /// Load the current vault state
  Future<VaultState> loadState() async {
    try {
      final statePath = await _statePath;
      final file = File(statePath);

      if (!await file.exists()) {
        return VaultState.empty();
      }

      final content = await file.readAsString();
      final yaml = loadYaml(content);

      if (yaml is! Map) {
        return VaultState.empty();
      }

      return VaultState.fromYaml(Map<String, dynamic>.from(yaml));
    } catch (e) {
      debugPrint('[VaultStateService] Error loading state: $e');
      return VaultState.empty();
    }
  }

  /// Save the vault state
  Future<void> saveState(VaultState state) async {
    try {
      await ensureParachuteFolderExists();

      final statePath = await _statePath;
      final content = _stateToYaml(state);

      await File(statePath).writeAsString(content);
      debugPrint('[VaultStateService] Saved vault state');
    } catch (e) {
      debugPrint('[VaultStateService] Error saving state: $e');
    }
  }

  /// Convert state to YAML string
  String _stateToYaml(VaultState state) {
    final buffer = StringBuffer();
    buffer.writeln('# Parachute vault state');
    buffer.writeln('# Do not edit manually unless you know what you\'re doing');
    buffer.writeln();
    buffer.writeln('version: ${state.version}');
    buffer.writeln('capture_ready: ${state.captureReady}');
    buffer.writeln('agent_initialized: ${state.agentInitialized}');
    if (state.lastAgentInit != null) {
      buffer.writeln('last_agent_init: ${state.lastAgentInit!.toIso8601String()}');
    }
    if (state.importsProcessed.isNotEmpty) {
      buffer.writeln('imports_processed:');
      for (final import in state.importsProcessed) {
        buffer.writeln('  - $import');
      }
    } else {
      buffer.writeln('imports_processed: []');
    }
    return buffer.toString();
  }

  /// Mark capture phase as initialized (Phase 1)
  Future<void> markCaptureReady() async {
    final state = await loadState();
    await saveState(state.copyWith(
      captureReady: true,
      version: VaultState.currentVersion,
    ));
  }

  /// Mark agent phase as initialized (Phase 2)
  Future<void> markAgentInitialized() async {
    final state = await loadState();
    await saveState(state.copyWith(
      agentInitialized: true,
      lastAgentInit: DateTime.now(),
      version: VaultState.currentVersion,
    ));
  }

  /// Record that an import has been processed
  Future<void> recordImportProcessed(String importName) async {
    final state = await loadState();
    if (!state.importsProcessed.contains(importName)) {
      await saveState(state.copyWith(
        importsProcessed: [...state.importsProcessed, importName],
      ));
    }
  }

  /// Check if an import has already been processed
  Future<bool> isImportProcessed(String importName) async {
    final state = await loadState();
    return state.importsProcessed.contains(importName);
  }

  /// Get list of unprocessed imports
  Future<List<String>> getUnprocessedImports(List<String> availableImports) async {
    final state = await loadState();
    return availableImports
        .where((name) => !state.importsProcessed.contains(name))
        .toList();
  }
}

/// Represents the initialization state of a vault
class VaultState {
  static const int currentVersion = 1;

  /// State file version for migrations
  final int version;

  /// Whether capture/journaling is set up (Phase 1)
  final bool captureReady;

  /// Whether full agent initialization has been done (Phase 2)
  final bool agentInitialized;

  /// Timestamp of last agent initialization
  final DateTime? lastAgentInit;

  /// List of import folder names that have been processed
  final List<String> importsProcessed;

  const VaultState({
    required this.version,
    required this.captureReady,
    required this.agentInitialized,
    this.lastAgentInit,
    required this.importsProcessed,
  });

  /// Empty state for new vaults
  factory VaultState.empty() {
    return const VaultState(
      version: currentVersion,
      captureReady: false,
      agentInitialized: false,
      lastAgentInit: null,
      importsProcessed: [],
    );
  }

  /// Parse from YAML map
  factory VaultState.fromYaml(Map<String, dynamic> yaml) {
    return VaultState(
      version: yaml['version'] as int? ?? 1,
      captureReady: yaml['capture_ready'] as bool? ?? false,
      agentInitialized: yaml['agent_initialized'] as bool? ?? false,
      lastAgentInit: yaml['last_agent_init'] != null
          ? DateTime.tryParse(yaml['last_agent_init'].toString())
          : null,
      importsProcessed: (yaml['imports_processed'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// Convert to map for YAML serialization
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'capture_ready': captureReady,
      'agent_initialized': agentInitialized,
      if (lastAgentInit != null)
        'last_agent_init': lastAgentInit!.toIso8601String(),
      'imports_processed': importsProcessed,
    };
  }

  /// Create a copy with updated fields
  VaultState copyWith({
    int? version,
    bool? captureReady,
    bool? agentInitialized,
    DateTime? lastAgentInit,
    List<String>? importsProcessed,
  }) {
    return VaultState(
      version: version ?? this.version,
      captureReady: captureReady ?? this.captureReady,
      agentInitialized: agentInitialized ?? this.agentInitialized,
      lastAgentInit: lastAgentInit ?? this.lastAgentInit,
      importsProcessed: importsProcessed ?? this.importsProcessed,
    );
  }

  /// Whether this vault needs any initialization
  bool get needsSetup => !captureReady;

  /// Whether agent initialization is pending
  bool get needsAgentInit => captureReady && !agentInitialized;

  /// Whether the vault is fully initialized
  bool get isFullyInitialized => captureReady && agentInitialized;
}
