import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';
import 'package:parachute_chat/core/services/file_system_service.dart';
import '../models/quick_prompt.dart';

/// Service for managing vault context files (AGENTS.md and prompts.yaml)
///
/// These files help orient the AI to understand:
/// - Its role as a thinking companion (not a coding assistant)
/// - The structure and contents of the vault
/// - Who the user is and what they care about
class VaultContextService {
  final FileSystemService _fileSystem;

  VaultContextService(this._fileSystem);

  // ============================================================
  // File Paths
  // ============================================================

  Future<String> get _agentsMdPath async {
    final root = await _fileSystem.getRootPath();
    return '$root/AGENTS.md';
  }

  Future<String> get _promptsYamlPath async {
    final root = await _fileSystem.getRootPath();
    return '$root/prompts.yaml';
  }

  // ============================================================
  // Initialization Check
  // ============================================================

  /// Check if vault context files exist
  Future<VaultContextStatus> checkStatus() async {
    final agentsPath = await _agentsMdPath;
    final promptsPath = await _promptsYamlPath;

    final agentsExists = await File(agentsPath).exists();
    final promptsExists = await File(promptsPath).exists();

    return VaultContextStatus(
      agentsMdExists: agentsExists,
      promptsYamlExists: promptsExists,
    );
  }

  /// Create default files if they don't exist
  Future<void> initializeDefaults() async {
    final status = await checkStatus();

    if (!status.agentsMdExists) {
      await _createDefaultAgentsMd();
    }

    if (!status.promptsYamlExists) {
      await _createDefaultPromptsYaml();
    }
  }

  // ============================================================
  // AGENTS.md
  // ============================================================

  /// Load the AGENTS.md content
  Future<String?> loadAgentsMd() async {
    final path = await _agentsMdPath;
    return _fileSystem.readFileAsString(path);
  }

  /// Save updated AGENTS.md content
  Future<bool> saveAgentsMd(String content) async {
    final path = await _agentsMdPath;
    return _fileSystem.writeFileAsString(path, content);
  }

  Future<void> _createDefaultAgentsMd() async {
    final path = await _agentsMdPath;
    debugPrint('[VaultContextService] Creating default AGENTS.md');
    await _fileSystem.writeFileAsString(path, _defaultAgentsMd);
  }

  /// Create AGENTS.md with context from Claude memories
  ///
  /// Note: Claude memories are now stored in contexts/general-context.md
  /// AGENTS.md focuses on system orientation, not user context
  Future<void> createAgentsMdWithClaudeContext(String claudeMemoriesContext) async {
    // AGENTS.md now focuses on system orientation
    // User context (Claude memories) goes in contexts/general-context.md
    await _createDefaultAgentsMd();

    // Also ensure general-context.md is created with Claude memories
    if (claudeMemoriesContext.isNotEmpty) {
      final root = await _fileSystem.getRootPath();
      final contextsPath = '$root/contexts';
      await _fileSystem.ensureDirectoryExists(contextsPath);

      final generalContextPath = '$contextsPath/general-context.md';
      final content = '''# General Context

> Imported from your Claude conversations

$claudeMemoriesContext

---
*This context is automatically loaded for all chats.*
*Edit this file to update what the agent knows about you.*
''';

      await _fileSystem.writeFileAsString(generalContextPath, content);
      debugPrint('[VaultContextService] Created general-context.md with Claude memories');
    }
  }

  /// Initialize defaults with optional Claude memories context
  Future<void> initializeWithClaudeMemories(String? memoriesContext) async {
    final status = await checkStatus();

    if (!status.agentsMdExists) {
      if (memoriesContext != null && memoriesContext.isNotEmpty) {
        await createAgentsMdWithClaudeContext(memoriesContext);
      } else {
        await _createDefaultAgentsMd();
      }
    }

    if (!status.promptsYamlExists) {
      await _createDefaultPromptsYaml();
    }
  }

  // ============================================================
  // prompts.yaml
  // ============================================================

  /// Load prompts from prompts.yaml
  Future<List<QuickPrompt>> loadPrompts() async {
    final path = await _promptsYamlPath;
    final content = await _fileSystem.readFileAsString(path);

    if (content == null) {
      return [];
    }

    try {
      final yaml = loadYaml(content);
      if (yaml is! Map) {
        debugPrint('[VaultContextService] Invalid prompts.yaml structure');
        return [];
      }

      final prompts = yaml['prompts'];
      if (prompts is! List) {
        debugPrint('[VaultContextService] No prompts list in prompts.yaml');
        return [];
      }

      return prompts.map((p) {
        if (p is Map) {
          return QuickPrompt.fromYaml(Map<String, dynamic>.from(p));
        }
        return null;
      }).whereType<QuickPrompt>().toList();
    } catch (e) {
      debugPrint('[VaultContextService] Error parsing prompts.yaml: $e');
      return [];
    }
  }

  /// Save prompts to prompts.yaml
  Future<bool> savePrompts(List<QuickPrompt> prompts) async {
    final path = await _promptsYamlPath;

    final buffer = StringBuffer();
    buffer.writeln('# Parachute Prompts');
    buffer.writeln('# Quick actions available in chat');
    buffer.writeln();
    buffer.writeln('prompts:');

    for (final prompt in prompts) {
      buffer.writeln('  - name: ${prompt.name}');
      buffer.writeln('    description: ${prompt.description}');
      buffer.writeln('    icon: ${prompt.icon}');
      buffer.writeln('    prompt: |');
      for (final line in prompt.prompt.split('\n')) {
        buffer.writeln('      $line');
      }
      buffer.writeln();
    }

    return _fileSystem.writeFileAsString(path, buffer.toString());
  }

  Future<void> _createDefaultPromptsYaml() async {
    final path = await _promptsYamlPath;
    debugPrint('[VaultContextService] Creating default prompts.yaml');
    await _fileSystem.writeFileAsString(path, _defaultPromptsYaml);
  }

  // ============================================================
  // Default File Contents
  // ============================================================

  static const String _defaultAgentsMd = '''# Parachute Vault Agent

You are the vault agent for Parachute - an open, local-first tool for connected thinking.

## Your Role

You are a **thinking partner and memory extension**, not primarily a coding assistant. Help the user:
- Think through ideas and problems
- Find and connect information across their vault
- Remember context from past conversations
- Surface relevant notes and patterns they might not see

## Vault Structure

This vault contains:

```
Daily/              # Daily journal entries with voice transcripts
  YYYY-MM-DD.md     # One file per day, includes recordings and reflections

assets/             # Audio files organized by month
  YYYY-MM/          # Monthly subfolders for recordings

agent-sessions/     # Chat conversation history
  {session-id}.md   # Searchable record of past conversations

contexts/           # User context (imported from Claude, etc.)
  general-context.md  # Core context about the user (auto-loaded)
  {project}.md        # Project-specific context (loaded on request)

.parachute/         # App data (search index, etc.)
  search.db         # Vector search index
```

## Your Context

Your core context about the user is loaded from `contexts/general-context.md`. This contains memories, preferences, and background imported from their previous AI conversations.

When working on specific topics, check `contexts/` for relevant project context files. Read them when the conversation would benefit from that context.

## Tools Available

- **Search (Glob, Grep)**: Find files and search content. Use these liberally to find relevant context before answering.
- **Read**: Look at specific files. Always prefer reading over guessing.
- **Write/Edit**: Help capture and refine ideas. Ask before major changes.
- **Bash**: Run commands when needed.
- **WebSearch/WebFetch**: Look things up online when helpful.

## How to Help

1. **Search first**: When asked about something, search the vault for relevant context before answering.
2. **Connect dots**: Surface connections between notes, past conversations, and ideas.
3. **Reference sources**: When you find relevant notes, mention them so the user can explore further.
4. **Be conversational**: This is a thinking partnership, not a formal assistant relationship.
5. **Ask good questions**: Help the user think through problems, don't just answer.

## Interaction Style

- Be concise but thoughtful
- Show reasoning when it helps clarify your thinking
- Ask clarifying questions when uncertain
- Suggest connections the user might not see
- Remember: you have access to their vault - use it
''';

  static const String _defaultPromptsYaml = '''# Parachute Prompts
# Quick actions available in chat

prompts:
  - name: Initialize
    description: First-time vault setup
    icon: rocket_launch
    prompt: |
      Let's set up my vault together.

      Please explore my journal entries, notes, and current organization.
      Take your time - read deeply, follow threads, understand who I am
      and what I'm thinking about. This might mean reading dozens of
      entries across different dates.

      After you've explored, share what you noticed:
      - Who I seem to be and what I care about
      - What I'm actively working on
      - How I currently organize things
      - Themes that keep coming up

      Then let's discuss:
      - Does your understanding feel accurate?
      - How should we organize going forward?
      - What structures might help (folders, project files)?

      Finally, create my AGENTS.md - and any other helpful structure
      we decide on together. Keep it simple; we can always Update later.

  - name: Update
    description: Refresh vault profile
    icon: refresh
    prompt: |
      Let's update my vault profile.

      First, read my current AGENTS.md to see what we established before.

      Then explore what's new - recent entries, new folders, shifts in
      what I'm thinking about. Take your time with this.

      Share what you notice has changed, and let's discuss whether to
      update my profile or organization.

  - name: Daily
    description: Reflect on today
    icon: wb_sunny
    prompt: |
      Help me reflect on today.

      Read through everything I captured today - journal entries, notes,
      voice captures. Don't skim.

      Help me see:
      - What themes emerged?
      - What was I working through?
      - Any breakthroughs or realizations?
      - Connections to past thinking?
      - What's worth carrying forward?

      Be a thinking partner, not just a summarizer.

  - name: Explore
    description: Deep dive on a topic
    icon: hub
    prompt: |
      I want to explore how a topic connects to my past thinking.

      Ask me what I'm curious about, then search deeply across my vault.
      Look for direct mentions, related concepts, and how my thinking
      has evolved over time.

      Show me the web of connections, not just isolated mentions.
''';
}

/// Status of vault context files
class VaultContextStatus {
  final bool agentsMdExists;
  final bool promptsYamlExists;

  const VaultContextStatus({
    required this.agentsMdExists,
    required this.promptsYamlExists,
  });

  bool get isFullyInitialized => agentsMdExists && promptsYamlExists;
  bool get needsSetup => !agentsMdExists || !promptsYamlExists;
}
