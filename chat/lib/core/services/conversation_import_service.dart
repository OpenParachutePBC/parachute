import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'file_system_service.dart';

/// Progress update during conversation import
class ImportProgress {
  /// Current conversation being processed
  final String currentTitle;

  /// Number of conversations processed so far
  final int processed;

  /// Total number of conversations to process
  final int total;

  /// Phase of import: 'scanning', 'importing', 'complete', 'error'
  final String phase;

  /// Error message if phase is 'error'
  final String? error;

  const ImportProgress({
    required this.currentTitle,
    required this.processed,
    required this.total,
    required this.phase,
    this.error,
  });

  double get progress => total > 0 ? processed / total : 0;
  bool get isComplete => phase == 'complete';
  bool get hasError => phase == 'error';
}

/// Result of scanning an export folder
class ImportScanResult {
  /// Source type: 'claude' or 'chatgpt'
  final String source;

  /// Total conversations found
  final int conversationCount;

  /// Conversations with actual messages
  final int nonEmptyCount;

  /// Whether memories/context was found
  final bool hasMemories;

  /// Number of projects found (Claude only)
  final int projectCount;

  /// List of project names (Claude only)
  final List<String> projectNames;

  /// Preview of memory content (first 200 chars)
  final String? memoryPreview;

  /// Date range of conversations
  final DateTime? oldestDate;
  final DateTime? newestDate;

  const ImportScanResult({
    required this.source,
    required this.conversationCount,
    required this.nonEmptyCount,
    required this.hasMemories,
    this.projectCount = 0,
    this.projectNames = const [],
    this.memoryPreview,
    this.oldestDate,
    this.newestDate,
  });
}

/// Result of completed import
class ImportResult {
  /// Number of conversations imported
  final int conversationsImported;

  /// Number of context files created
  final int contextFilesCreated;

  /// Paths to created files
  final List<String> createdFiles;

  /// Any conversations that failed to import
  final List<String> failures;

  const ImportResult({
    required this.conversationsImported,
    required this.contextFilesCreated,
    required this.createdFiles,
    this.failures = const [],
  });
}

/// Service for importing conversations from Claude and ChatGPT exports
///
/// Converts exported conversations to markdown files in agent-sessions/
/// with proper frontmatter for indexing and search.
class ConversationImportService {
  final FileSystemService _fileSystem;

  ConversationImportService(this._fileSystem);

  // ============================================================
  // Scanning - Preview what's in an export
  // ============================================================

  /// Scan a Claude export folder and return what's available
  Future<ImportScanResult> scanClaudeExport(String exportPath) async {
    try {
      final conversationsFile = File(p.join(exportPath, 'conversations.json'));
      final memoriesFile = File(p.join(exportPath, 'memories.json'));
      final projectsFile = File(p.join(exportPath, 'projects.json'));

      int conversationCount = 0;
      int nonEmptyCount = 0;
      DateTime? oldestDate;
      DateTime? newestDate;

      if (await conversationsFile.exists()) {
        final content = await conversationsFile.readAsString();
        final List<dynamic> conversations = jsonDecode(content);
        conversationCount = conversations.length;

        for (final conv in conversations) {
          final messages = conv['chat_messages'] as List<dynamic>? ?? [];
          if (messages.isNotEmpty) {
            nonEmptyCount++;

            final createdAt = DateTime.tryParse(conv['created_at'] ?? '');
            if (createdAt != null) {
              if (oldestDate == null || createdAt.isBefore(oldestDate)) {
                oldestDate = createdAt;
              }
              if (newestDate == null || createdAt.isAfter(newestDate)) {
                newestDate = createdAt;
              }
            }
          }
        }
      }

      String? memoryPreview;
      bool hasMemories = false;
      if (await memoriesFile.exists()) {
        final content = await memoriesFile.readAsString();
        final List<dynamic> memories = jsonDecode(content);
        if (memories.isNotEmpty) {
          final memory = memories.first as Map<String, dynamic>;
          final conversationsMemory = memory['conversations_memory'] as String?;
          if (conversationsMemory != null && conversationsMemory.isNotEmpty) {
            hasMemories = true;
            memoryPreview = conversationsMemory.length > 200
                ? '${conversationsMemory.substring(0, 200)}...'
                : conversationsMemory;
          }
        }
      }

      int projectCount = 0;
      List<String> projectNames = [];
      if (await projectsFile.exists()) {
        final content = await projectsFile.readAsString();
        final List<dynamic> projects = jsonDecode(content);
        projectCount = projects.length;
        projectNames = projects
            .map((p) => p['name'] as String?)
            .where((n) => n != null && n.isNotEmpty)
            .cast<String>()
            .toList();
      }

      return ImportScanResult(
        source: 'claude',
        conversationCount: conversationCount,
        nonEmptyCount: nonEmptyCount,
        hasMemories: hasMemories,
        projectCount: projectCount,
        projectNames: projectNames,
        memoryPreview: memoryPreview,
        oldestDate: oldestDate,
        newestDate: newestDate,
      );
    } catch (e) {
      debugPrint('[ConversationImportService] Error scanning Claude export: $e');
      return const ImportScanResult(
        source: 'claude',
        conversationCount: 0,
        nonEmptyCount: 0,
        hasMemories: false,
      );
    }
  }

  // ============================================================
  // Import - Convert and save conversations
  // ============================================================

  /// Import conversations from a Claude export
  ///
  /// Yields [ImportProgress] updates as conversations are processed.
  /// Returns [ImportResult] when complete.
  Stream<ImportProgress> importClaudeConversations(String exportPath) async* {
    final sessionsPath = await _fileSystem.getSessionsPath();
    await _fileSystem.ensureDirectoryExists(sessionsPath);

    // Create a subdirectory for imported conversations
    final importedPath = p.join(sessionsPath, 'imported');
    await _fileSystem.ensureDirectoryExists(importedPath);

    final conversationsFile = File(p.join(exportPath, 'conversations.json'));
    if (!await conversationsFile.exists()) {
      yield const ImportProgress(
        currentTitle: 'Error',
        processed: 0,
        total: 0,
        phase: 'error',
        error: 'conversations.json not found',
      );
      return;
    }

    yield const ImportProgress(
      currentTitle: 'Reading export...',
      processed: 0,
      total: 0,
      phase: 'scanning',
    );

    final content = await conversationsFile.readAsString();
    final List<dynamic> conversations = jsonDecode(content);

    // Filter to only conversations with messages
    final nonEmptyConversations = conversations
        .where((c) => (c['chat_messages'] as List<dynamic>?)?.isNotEmpty ?? false)
        .toList();

    final total = nonEmptyConversations.length;
    final createdFiles = <String>[];
    final failures = <String>[];

    for (var i = 0; i < nonEmptyConversations.length; i++) {
      final conv = nonEmptyConversations[i];
      final title = _getConversationTitle(conv);

      yield ImportProgress(
        currentTitle: title,
        processed: i,
        total: total,
        phase: 'importing',
      );

      try {
        final filePath = await _convertClaudeConversation(conv, importedPath);
        if (filePath != null) {
          createdFiles.add(filePath);
        }
      } catch (e) {
        debugPrint('[ConversationImportService] Error importing conversation: $e');
        failures.add(title);
      }
    }

    yield ImportProgress(
      currentTitle: 'Complete',
      processed: total,
      total: total,
      phase: 'complete',
    );
  }

  /// Convert a single Claude conversation to markdown
  Future<String?> _convertClaudeConversation(
    Map<String, dynamic> conversation,
    String outputPath,
  ) async {
    final uuid = conversation['uuid'] as String?;
    if (uuid == null) return null;

    final messages = conversation['chat_messages'] as List<dynamic>? ?? [];
    if (messages.isEmpty) return null;

    // Check if already imported (by UUID)
    final filename = 'claude-$uuid.md';
    final filePath = p.join(outputPath, filename);
    final file = File(filePath);
    if (await file.exists()) {
      debugPrint('[ConversationImportService] Already imported: $filename');
      return null; // Already imported
    }

    final title = _getConversationTitle(conversation);
    final createdAt = conversation['created_at'] as String?;
    final updatedAt = conversation['updated_at'] as String?;
    final summary = conversation['summary'] as String?;

    final buffer = StringBuffer();

    // YAML frontmatter
    buffer.writeln('---');
    buffer.writeln('title: ${_escapeYaml(title)}');
    buffer.writeln('sdk_session_id: $uuid');
    buffer.writeln('source: claude');
    buffer.writeln('original_id: $uuid');
    if (createdAt != null) buffer.writeln('created_at: $createdAt');
    if (updatedAt != null) buffer.writeln('last_accessed: $updatedAt');
    buffer.writeln('imported: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('archived: false');
    buffer.writeln('---');
    buffer.writeln();

    // Summary if available
    if (summary != null && summary.isNotEmpty) {
      buffer.writeln('> $summary');
      buffer.writeln();
    }

    // Messages - use format: ### Human | timestamp
    for (final msg in messages) {
      final sender = msg['sender'] as String? ?? 'unknown';
      final text = msg['text'] as String? ?? '';
      final msgCreatedAt = msg['created_at'] as String?;
      final attachments = msg['attachments'] as List<dynamic>? ?? [];

      // Format sender header with timestamp
      final senderDisplay = sender == 'human' ? 'Human' : 'Assistant';
      if (msgCreatedAt != null) {
        buffer.writeln('### $senderDisplay | $msgCreatedAt');
      } else {
        buffer.writeln('### $senderDisplay | ${DateTime.now().toUtc().toIso8601String()}');
      }
      buffer.writeln();

      // Message content
      buffer.writeln(text);

      // Note attachments if any
      if (attachments.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('_[${attachments.length} attachment(s)]_');
      }

      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
    return filePath;
  }

  /// Get a display title for a conversation
  String _getConversationTitle(Map<String, dynamic> conversation) {
    final name = conversation['name'] as String?;
    if (name != null && name.isNotEmpty) {
      return name;
    }

    // Fall back to first message preview
    final messages = conversation['chat_messages'] as List<dynamic>? ?? [];
    if (messages.isNotEmpty) {
      final firstMsg = messages.first['text'] as String? ?? '';
      if (firstMsg.length > 50) {
        return '${firstMsg.substring(0, 50)}...';
      }
      return firstMsg.isNotEmpty ? firstMsg : 'Untitled conversation';
    }

    return 'Untitled conversation';
  }

  /// Escape a string for YAML
  String _escapeYaml(String value) {
    // If contains special characters, quote it
    if (value.contains(':') ||
        value.contains('#') ||
        value.contains('\n') ||
        value.contains('"') ||
        value.contains("'") ||
        value.startsWith(' ') ||
        value.endsWith(' ')) {
      // Use double quotes and escape internal double quotes
      return '"${value.replaceAll('"', '\\"').replaceAll('\n', ' ')}"';
    }
    return value;
  }

  // ============================================================
  // ChatGPT Import
  // ============================================================

  /// Scan a ChatGPT export folder
  Future<ImportScanResult> scanChatGPTExport(String exportPath) async {
    try {
      final conversationsFile = File(p.join(exportPath, 'conversations.json'));

      int conversationCount = 0;
      int nonEmptyCount = 0;
      DateTime? oldestDate;
      DateTime? newestDate;
      String? memoryPreview;
      bool hasMemories = false;

      if (await conversationsFile.exists()) {
        final content = await conversationsFile.readAsString();
        final List<dynamic> conversations = jsonDecode(content);
        conversationCount = conversations.length;

        for (final conv in conversations) {
          final mapping = conv['mapping'] as Map<String, dynamic>? ?? {};

          // Count messages and find memory context
          int messageCount = 0;
          for (final node in mapping.values) {
            final msg = node['message'];
            if (msg != null) {
              final role = msg['author']?['role'];
              if (role == 'user' || role == 'assistant') {
                messageCount++;
              }

              // Check for memory context
              final metadata = msg['metadata'] as Map<String, dynamic>? ?? {};
              final userContext = metadata['user_context_message_data'] as Map<String, dynamic>?;
              if (userContext != null && !hasMemories) {
                final aboutUser = userContext['about_user_message'] as String?;
                if (aboutUser != null && aboutUser.isNotEmpty) {
                  hasMemories = true;
                  memoryPreview = aboutUser.length > 200
                      ? '${aboutUser.substring(0, 200)}...'
                      : aboutUser;
                }
              }
            }
          }

          if (messageCount > 0) {
            nonEmptyCount++;

            // Parse timestamp (ChatGPT uses Unix timestamp)
            final createTime = conv['create_time'];
            if (createTime != null) {
              final timestamp = DateTime.fromMillisecondsSinceEpoch(
                (createTime * 1000).toInt(),
              );
              if (oldestDate == null || timestamp.isBefore(oldestDate)) {
                oldestDate = timestamp;
              }
              if (newestDate == null || timestamp.isAfter(newestDate)) {
                newestDate = timestamp;
              }
            }
          }
        }
      }

      return ImportScanResult(
        source: 'chatgpt',
        conversationCount: conversationCount,
        nonEmptyCount: nonEmptyCount,
        hasMemories: hasMemories,
        memoryPreview: memoryPreview,
        oldestDate: oldestDate,
        newestDate: newestDate,
      );
    } catch (e) {
      debugPrint('[ConversationImportService] Error scanning ChatGPT export: $e');
      return const ImportScanResult(
        source: 'chatgpt',
        conversationCount: 0,
        nonEmptyCount: 0,
        hasMemories: false,
      );
    }
  }

  /// Import conversations from a ChatGPT export
  Stream<ImportProgress> importChatGPTConversations(String exportPath) async* {
    final sessionsPath = await _fileSystem.getSessionsPath();
    await _fileSystem.ensureDirectoryExists(sessionsPath);

    final importedPath = p.join(sessionsPath, 'imported');
    await _fileSystem.ensureDirectoryExists(importedPath);

    final conversationsFile = File(p.join(exportPath, 'conversations.json'));
    if (!await conversationsFile.exists()) {
      yield const ImportProgress(
        currentTitle: 'Error',
        processed: 0,
        total: 0,
        phase: 'error',
        error: 'conversations.json not found',
      );
      return;
    }

    yield const ImportProgress(
      currentTitle: 'Reading export...',
      processed: 0,
      total: 0,
      phase: 'scanning',
    );

    final content = await conversationsFile.readAsString();
    final List<dynamic> conversations = jsonDecode(content);

    // Filter to conversations with actual messages
    final nonEmptyConversations = conversations.where((c) {
      final mapping = c['mapping'] as Map<String, dynamic>? ?? {};
      return mapping.values.any((node) {
        final msg = node['message'];
        return msg != null && ['user', 'assistant'].contains(msg['author']?['role']);
      });
    }).toList();

    final total = nonEmptyConversations.length;
    final createdFiles = <String>[];
    final failures = <String>[];

    for (var i = 0; i < nonEmptyConversations.length; i++) {
      final conv = nonEmptyConversations[i];
      final title = conv['title'] as String? ?? 'Untitled';

      yield ImportProgress(
        currentTitle: title,
        processed: i,
        total: total,
        phase: 'importing',
      );

      try {
        final filePath = await _convertChatGPTConversation(conv, importedPath);
        if (filePath != null) {
          createdFiles.add(filePath);
        }
      } catch (e) {
        debugPrint('[ConversationImportService] Error importing ChatGPT conversation: $e');
        failures.add(title);
      }
    }

    yield ImportProgress(
      currentTitle: 'Complete',
      processed: total,
      total: total,
      phase: 'complete',
    );
  }

  /// Convert a ChatGPT conversation to markdown
  Future<String?> _convertChatGPTConversation(
    Map<String, dynamic> conversation,
    String outputPath,
  ) async {
    final id = conversation['id'] as String? ?? conversation['conversation_id'] as String?;
    if (id == null) return null;

    // Check if already imported
    final filename = 'chatgpt-$id.md';
    final filePath = p.join(outputPath, filename);
    final file = File(filePath);
    if (await file.exists()) {
      debugPrint('[ConversationImportService] Already imported: $filename');
      return null;
    }

    final title = conversation['title'] as String? ?? 'Untitled';
    final createTime = conversation['create_time'];
    final updateTime = conversation['update_time'];
    final isArchived = conversation['is_archived'] as bool? ?? false;

    // Build ordered message list from tree structure
    final messages = _extractChatGPTMessages(conversation);
    if (messages.isEmpty) return null;

    final buffer = StringBuffer();

    // YAML frontmatter
    buffer.writeln('---');
    buffer.writeln('title: ${_escapeYaml(title)}');
    buffer.writeln('sdk_session_id: $id');
    buffer.writeln('source: chatgpt');
    buffer.writeln('original_id: $id');
    if (createTime != null) {
      final created = DateTime.fromMillisecondsSinceEpoch((createTime * 1000).toInt());
      buffer.writeln('created_at: ${created.toUtc().toIso8601String()}');
    }
    if (updateTime != null) {
      final updated = DateTime.fromMillisecondsSinceEpoch((updateTime * 1000).toInt());
      buffer.writeln('last_accessed: ${updated.toUtc().toIso8601String()}');
    }
    buffer.writeln('imported: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('archived: $isArchived');
    buffer.writeln('---');
    buffer.writeln();

    // Messages - use format: ### Human | timestamp
    for (final msg in messages) {
      final role = msg['role'] as String;
      final text = msg['text'] as String;
      final timestamp = msg['timestamp'] as DateTime?;

      final senderDisplay = role == 'user' ? 'Human' : 'Assistant';
      final timestampStr = timestamp?.toUtc().toIso8601String() ?? DateTime.now().toUtc().toIso8601String();
      buffer.writeln('### $senderDisplay | $timestampStr');
      buffer.writeln();
      buffer.writeln(text);
      buffer.writeln();
    }

    await file.writeAsString(buffer.toString());
    return filePath;
  }

  /// Extract messages from ChatGPT's tree structure in order
  List<Map<String, dynamic>> _extractChatGPTMessages(Map<String, dynamic> conversation) {
    final mapping = conversation['mapping'] as Map<String, dynamic>? ?? {};
    final currentNode = conversation['current_node'] as String?;

    if (mapping.isEmpty) return [];

    // Build path from root to current node
    final messages = <Map<String, dynamic>>[];

    // Find all nodes and build parent-child relationships
    String? nodeId = currentNode;

    // Walk backwards to find root, collecting the path
    final pathToRoot = <String>[];
    while (nodeId != null) {
      pathToRoot.add(nodeId);
      final node = mapping[nodeId];
      nodeId = node?['parent'] as String?;
    }

    // Reverse to get root-to-current order
    pathToRoot.reversed.toList();

    // Walk from root to current, extracting messages
    for (final id in pathToRoot.reversed) {
      final node = mapping[id];
      final msg = node?['message'];

      if (msg != null) {
        final role = msg['author']?['role'] as String?;
        if (role == 'user' || role == 'assistant') {
          final content = msg['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List<dynamic>?;

          if (parts != null && parts.isNotEmpty) {
            // Concatenate text parts (skip images/files)
            final textParts = parts.whereType<String>().toList();
            if (textParts.isNotEmpty) {
              final text = textParts.join('\n');

              DateTime? timestamp;
              final createTime = msg['create_time'];
              if (createTime != null) {
                timestamp = DateTime.fromMillisecondsSinceEpoch(
                  (createTime * 1000).toInt(),
                );
              }

              messages.add({
                'role': role,
                'text': text,
                'timestamp': timestamp,
              });
            }
          }
        }
      }
    }

    return messages;
  }

  // ============================================================
  // Memory/Context Extraction
  // ============================================================

  /// Extract ChatGPT memory context (about_user_message)
  Future<String?> extractChatGPTMemory(String exportPath) async {
    try {
      final conversationsFile = File(p.join(exportPath, 'conversations.json'));
      if (!await conversationsFile.exists()) return null;

      final content = await conversationsFile.readAsString();
      final List<dynamic> conversations = jsonDecode(content);

      // Find the most recent conversation with memory context
      for (final conv in conversations) {
        final mapping = conv['mapping'] as Map<String, dynamic>? ?? {};
        for (final node in mapping.values) {
          final msg = node['message'];
          if (msg != null) {
            final metadata = msg['metadata'] as Map<String, dynamic>? ?? {};
            final userContext = metadata['user_context_message_data'] as Map<String, dynamic>?;
            if (userContext != null) {
              final aboutUser = userContext['about_user_message'] as String?;
              final aboutModel = userContext['about_model_message'] as String?;

              if (aboutUser != null && aboutUser.isNotEmpty) {
                final buffer = StringBuffer();
                buffer.writeln(aboutUser);
                if (aboutModel != null && aboutModel.isNotEmpty) {
                  buffer.writeln();
                  buffer.writeln('Communication preferences: $aboutModel');
                }
                return buffer.toString();
              }
            }
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('[ConversationImportService] Error extracting ChatGPT memory: $e');
      return null;
    }
  }
}
