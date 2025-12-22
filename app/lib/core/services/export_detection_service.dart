import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'file_system_service.dart';

/// Types of AI assistant exports we can detect
enum ExportType {
  claude,
  chatgpt,
  unknown,
}

/// Information about a detected export
class DetectedExport {
  /// The type of export (Claude, ChatGPT, etc.)
  final ExportType type;

  /// Path to the export folder
  final String path;

  /// Display name for the export
  final String displayName;

  /// Files found in the export
  final List<String> files;

  /// Whether this export has memories (Claude)
  final bool hasMemories;

  /// Whether this export has projects (Claude)
  final bool hasProjects;

  /// Whether this export has conversations
  final bool hasConversations;

  /// Number of conversations found (if parsed)
  final int? conversationCount;

  const DetectedExport({
    required this.type,
    required this.path,
    required this.displayName,
    required this.files,
    this.hasMemories = false,
    this.hasProjects = false,
    this.hasConversations = false,
    this.conversationCount,
  });

  /// Get a summary description
  String get summary {
    final parts = <String>[];
    if (hasConversations) {
      parts.add(conversationCount != null
          ? '$conversationCount conversations'
          : 'conversations');
    }
    if (hasMemories) parts.add('memories');
    if (hasProjects) parts.add('projects');
    return parts.isEmpty ? 'export' : parts.join(', ');
  }
}

/// Service for detecting and analyzing AI assistant exports in the vault
///
/// Scans the imports folder for Claude, ChatGPT, and other exports,
/// providing information about what data is available for import or
/// for the agent to use as context.
class ExportDetectionService {
  final FileSystemService _fileSystem;

  ExportDetectionService(this._fileSystem);

  /// Scan the imports folder for any AI assistant exports
  Future<List<DetectedExport>> scanForExports() async {
    try {
      final importsPath = await _fileSystem.getImportsPath();
      final importsDir = Directory(importsPath);

      if (!await importsDir.exists()) {
        return [];
      }

      final exports = <DetectedExport>[];

      await for (final entity in importsDir.list()) {
        if (entity is Directory) {
          final export = await _analyzeExportFolder(entity);
          if (export != null) {
            exports.add(export);
          }
        }
      }

      // Sort by type (Claude first, then ChatGPT, then unknown)
      exports.sort((a, b) => a.type.index.compareTo(b.type.index));

      return exports;
    } catch (e) {
      debugPrint('[ExportDetectionService] Error scanning for exports: $e');
      return [];
    }
  }

  /// Check if any exports are available
  Future<bool> hasExports() async {
    final exports = await scanForExports();
    return exports.isNotEmpty;
  }

  /// Analyze a folder to determine if it's an AI assistant export
  Future<DetectedExport?> _analyzeExportFolder(Directory folder) async {
    try {
      final files = <String>[];
      await for (final entity in folder.list()) {
        if (entity is File) {
          files.add(p.basename(entity.path));
        }
      }

      // Check for Claude export signature
      if (files.contains('memories.json') || files.contains('projects.json')) {
        return await _analyzeClaudeExport(folder, files);
      }

      // Check for ChatGPT export signature
      if (files.contains('conversations.json') && !files.contains('memories.json')) {
        return await _analyzeChatGPTExport(folder, files);
      }

      // Unknown export with conversations.json
      if (files.contains('conversations.json')) {
        return DetectedExport(
          type: ExportType.unknown,
          path: folder.path,
          displayName: p.basename(folder.path),
          files: files,
          hasConversations: true,
        );
      }

      return null;
    } catch (e) {
      debugPrint('[ExportDetectionService] Error analyzing ${folder.path}: $e');
      return null;
    }
  }

  /// Analyze a Claude export folder
  Future<DetectedExport> _analyzeClaudeExport(
    Directory folder,
    List<String> files,
  ) async {
    int? conversationCount;

    // Try to count conversations
    final conversationsFile = File(p.join(folder.path, 'conversations.json'));
    if (await conversationsFile.exists()) {
      try {
        final content = await conversationsFile.readAsString();
        final List<dynamic> conversations = jsonDecode(content);
        conversationCount = conversations.length;
      } catch (e) {
        debugPrint('[ExportDetectionService] Error parsing Claude conversations: $e');
      }
    }

    return DetectedExport(
      type: ExportType.claude,
      path: folder.path,
      displayName: 'Claude Export',
      files: files,
      hasMemories: files.contains('memories.json'),
      hasProjects: files.contains('projects.json'),
      hasConversations: files.contains('conversations.json'),
      conversationCount: conversationCount,
    );
  }

  /// Analyze a ChatGPT export folder
  Future<DetectedExport> _analyzeChatGPTExport(
    Directory folder,
    List<String> files,
  ) async {
    int? conversationCount;

    // Try to count conversations
    final conversationsFile = File(p.join(folder.path, 'conversations.json'));
    if (await conversationsFile.exists()) {
      try {
        final content = await conversationsFile.readAsString();
        final List<dynamic> conversations = jsonDecode(content);
        conversationCount = conversations.length;
      } catch (e) {
        debugPrint('[ExportDetectionService] Error parsing ChatGPT conversations: $e');
      }
    }

    return DetectedExport(
      type: ExportType.chatgpt,
      path: folder.path,
      displayName: 'ChatGPT Export',
      files: files,
      hasConversations: files.contains('conversations.json'),
      conversationCount: conversationCount,
    );
  }

  /// Read Claude memories from an export
  Future<Map<String, dynamic>?> readClaudeMemories(String exportPath) async {
    try {
      final memoriesFile = File(p.join(exportPath, 'memories.json'));
      if (!await memoriesFile.exists()) return null;

      final content = await memoriesFile.readAsString();
      final List<dynamic> memories = jsonDecode(content);

      if (memories.isEmpty) return null;

      // Return the first memory object (typically there's only one)
      return memories.first as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ExportDetectionService] Error reading Claude memories: $e');
      return null;
    }
  }

  /// Read Claude projects from an export
  Future<List<Map<String, dynamic>>> readClaudeProjects(String exportPath) async {
    try {
      final projectsFile = File(p.join(exportPath, 'projects.json'));
      if (!await projectsFile.exists()) return [];

      final content = await projectsFile.readAsString();
      final List<dynamic> projects = jsonDecode(content);

      return projects.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[ExportDetectionService] Error reading Claude projects: $e');
      return [];
    }
  }

  /// Format Claude memories as a context string for the agent
  Future<String?> formatClaudeMemoriesAsContext(String exportPath) async {
    final memories = await readClaudeMemories(exportPath);
    if (memories == null) return null;

    final buffer = StringBuffer();
    buffer.writeln('# Context from Claude Export\n');

    // Conversations memory (general context)
    final conversationsMemory = memories['conversations_memory'] as String?;
    if (conversationsMemory != null && conversationsMemory.isNotEmpty) {
      buffer.writeln('## General Context\n');
      buffer.writeln(conversationsMemory);
      buffer.writeln();
    }

    // Project memories
    final projectMemories = memories['project_memories'] as Map<String, dynamic>?;
    if (projectMemories != null && projectMemories.isNotEmpty) {
      buffer.writeln('## Project Context\n');
      for (final entry in projectMemories.entries) {
        final projectMemory = entry.value as String?;
        if (projectMemory != null && projectMemory.isNotEmpty) {
          buffer.writeln('### Project\n');
          buffer.writeln(projectMemory);
          buffer.writeln();
        }
      }
    }

    return buffer.toString();
  }
}
