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

  /// Create all context files from a Claude export
  ///
  /// Creates:
  /// - A general context file from conversations_memory (if present)
  /// - Individual project context files from project_memories
  ///
  /// Returns the list of filenames that were created.
  Future<List<String>> createAllContextFilesFromClaudeExport(String exportPath) async {
    final allFilesCreated = <String>[];

    // Create general context file
    final generalFile = await createGeneralContextFile(exportPath);
    if (generalFile != null) {
      allFilesCreated.add(generalFile);
    }

    // Create project context files
    final projectFiles = await createContextFilesFromClaudeExport(exportPath);
    allFilesCreated.addAll(projectFiles);

    return allFilesCreated;
  }

  /// Create a general context file from Claude's conversations_memory
  ///
  /// This contains the user's general context that Claude learned
  /// across all conversations (not project-specific).
  Future<String?> createGeneralContextFile(String exportPath) async {
    try {
      final memories = await readClaudeMemories(exportPath);
      if (memories == null) return null;

      final conversationsMemory = memories['conversations_memory'] as String?;
      if (conversationsMemory == null || conversationsMemory.isEmpty) {
        return null;
      }

      // Ensure contexts folder exists
      final contextsPath = await _fileSystem.getContextsPath();
      await _fileSystem.ensureContextsFolderExists();

      const filename = 'general-context.md';
      final filePath = '$contextsPath/$filename';

      // Check if file already exists - don't overwrite
      final file = File(filePath);
      if (await file.exists()) {
        debugPrint('[ExportDetectionService] General context file already exists');
        return null;
      }

      // Generate the content
      final buffer = StringBuffer();
      buffer.writeln('# General Context');
      buffer.writeln();
      buffer.writeln('> Imported from Claude export - general context across conversations');
      buffer.writeln();
      buffer.writeln(conversationsMemory);
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('*Imported from Claude conversations memory*');

      await file.writeAsString(buffer.toString());
      debugPrint('[ExportDetectionService] Created general context file');

      return filename;
    } catch (e) {
      debugPrint('[ExportDetectionService] Error creating general context file: $e');
      return null;
    }
  }

  /// Create context files from a Claude export's project memories
  ///
  /// Writes markdown files to the contexts/ folder for each project
  /// that has useful context (memory or prompt template).
  ///
  /// Returns the list of filenames that were created.
  Future<List<String>> createContextFilesFromClaudeExport(String exportPath) async {
    try {
      final contexts = await getClaudeProjectContexts(exportPath);
      final contextFilesCreated = <String>[];

      // Only process projects that have actual context
      final projectsWithContext = contexts.where((c) => c.hasContext).toList();
      if (projectsWithContext.isEmpty) {
        debugPrint('[ExportDetectionService] No projects with context to create files for');
        return [];
      }

      // Ensure contexts folder exists
      final contextsPath = await _fileSystem.getContextsPath();
      await _fileSystem.ensureContextsFolderExists();

      for (final project in projectsWithContext) {
        final filename = '${project.filename}.md';
        final filePath = '$contextsPath/$filename';

        // Check if file already exists - don't overwrite
        final file = File(filePath);
        if (await file.exists()) {
          debugPrint('[ExportDetectionService] Context file already exists: $filename');
          continue;
        }

        // Write the context file
        final content = project.toMarkdown();
        await file.writeAsString(content);
        contextFilesCreated.add(filename);
        debugPrint('[ExportDetectionService] Created context file: $filename');
      }

      return contextFilesCreated;
    } catch (e) {
      debugPrint('[ExportDetectionService] Error creating context files: $e');
      return [];
    }
  }

  /// Get project info paired with its memory from a Claude export
  ///
  /// Returns a list of projects with their associated memory content
  Future<List<ClaudeProjectContext>> getClaudeProjectContexts(String exportPath) async {
    final projects = await readClaudeProjects(exportPath);
    final memories = await readClaudeMemories(exportPath);
    final projectMemories = memories?['project_memories'] as Map<String, dynamic>? ?? {};

    final contexts = <ClaudeProjectContext>[];

    for (final project in projects) {
      final uuid = project['uuid'] as String?;
      final name = project['name'] as String?;

      if (uuid == null || name == null) continue;

      // Find the memory for this project
      final memory = projectMemories[uuid] as String?;

      // Get prompt template if any
      final promptTemplate = project['prompt_template'] as String?;

      contexts.add(ClaudeProjectContext(
        uuid: uuid,
        name: name,
        description: project['description'] as String?,
        promptTemplate: promptTemplate,
        memory: memory,
      ));
    }

    return contexts;
  }
}

/// Represents a Claude project with its associated context
class ClaudeProjectContext {
  final String uuid;
  final String name;
  final String? description;
  final String? promptTemplate;
  final String? memory;

  const ClaudeProjectContext({
    required this.uuid,
    required this.name,
    this.description,
    this.promptTemplate,
    this.memory,
  });

  /// Whether this project has any useful context
  bool get hasContext => (memory?.isNotEmpty ?? false) || (promptTemplate?.isNotEmpty ?? false);

  /// Generate a safe filename from the project name
  String get filename {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
  }

  /// Generate markdown content for this project's context file
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# $name');
    buffer.writeln();

    if (description != null && description!.isNotEmpty) {
      buffer.writeln('> $description');
      buffer.writeln();
    }

    if (memory != null && memory!.isNotEmpty) {
      buffer.writeln('## Context');
      buffer.writeln();
      buffer.writeln(memory);
      buffer.writeln();
    }

    if (promptTemplate != null && promptTemplate!.isNotEmpty) {
      buffer.writeln('## Instructions');
      buffer.writeln();
      buffer.writeln(promptTemplate);
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln('*Imported from Claude project: $uuid*');

    return buffer.toString();
  }
}
