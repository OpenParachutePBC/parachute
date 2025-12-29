import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent.dart';
import '../models/stream_event.dart';
import '../models/context_file.dart';
import '../models/system_prompt_info.dart';
import '../models/working_directory.dart';

/// Service for communicating with the parachute-agent backend
class ChatService {
  final String baseUrl;
  final http.Client _client;

  /// Timeout for non-streaming HTTP requests
  static const requestTimeout = Duration(seconds: 30);

  ChatService({required this.baseUrl}) : _client = http.Client();

  // ============================================================
  // Sessions
  // ============================================================

  /// Get all chat sessions
  Future<List<ChatSession>> getSessions() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat/sessions'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get sessions: ${response.statusCode}');
      }

      // API returns {"sessions": [...]} not just [...]
      final decoded = jsonDecode(response.body);
      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['sessions'] is List) {
        data = decoded['sessions'] as List<dynamic>;
      } else {
        data = [];
      }
      return data
          .map((json) => ChatSession.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ChatService] Error getting sessions: $e');
      rethrow;
    }
  }

  /// Reload the session index from disk
  /// Call this to ensure the server's index reflects the current file state
  Future<void> reloadSessionIndex() async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/api/chat/sessions/reload'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        debugPrint('[ChatService] Failed to reload session index: ${response.statusCode}');
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[ChatService] Session index reloaded: ${data['sessionCount']} sessions');
      }
    } catch (e) {
      // Don't throw - this is a best-effort operation
      debugPrint('[ChatService] Error reloading session index: $e');
    }
  }

  /// Get a specific session with messages
  Future<ChatSessionWithMessages?> getSession(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat/session/${Uri.encodeComponent(sessionId)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to get session: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ChatSessionWithMessages.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting session: $e');
      rethrow;
    }
  }

  /// Delete a session
  Future<void> deleteSession(String sessionId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$baseUrl/api/chat/session/${Uri.encodeComponent(sessionId)}'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to delete session: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ChatService] Error deleting session: $e');
      rethrow;
    }
  }

  // ============================================================
  // Agents
  // ============================================================

  /// Get all available agents
  Future<List<Agent>> getAgents() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/agents'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get agents: ${response.statusCode}');
      }

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((json) => Agent.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ChatService] Error getting agents: $e');
      rethrow;
    }
  }

  // ============================================================
  // Document Upload
  // ============================================================

  /// Upload a document (recording transcript) to the server
  ///
  /// This syncs a local recording to the server's captures folder so agents
  /// can reference it. Returns the server-side path to the document.
  Future<String> uploadDocument({
    required String filename,
    required String content,
    String? title,
    String? context,
    DateTime? timestamp,
  }) async {
    try {
      debugPrint('[ChatService] Uploading document: $filename');

      final response = await _client.post(
        Uri.parse('$baseUrl/api/captures'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'filename': filename,
          'content': content,
          if (title != null) 'title': title,
          if (context != null) 'context': context,
          if (timestamp != null) 'timestamp': timestamp.toIso8601String(),
        }),
      ).timeout(requestTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to upload document: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final path = data['path'] as String? ?? 'captures/$filename';

      debugPrint('[ChatService] Document uploaded: $path');
      return path;
    } catch (e) {
      debugPrint('[ChatService] Error uploading document: $e');
      rethrow;
    }
  }

  /// Check if a document exists on the server
  Future<bool> documentExists(String filename) async {
    try {
      final response = await _client.head(
        Uri.parse('$baseUrl/api/captures/${Uri.encodeComponent(filename)}'),
      ).timeout(requestTimeout);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ChatService] Error checking document: $e');
      return false;
    }
  }

  // ============================================================
  // Contexts
  // ============================================================

  /// Get all available context files from the vault
  Future<List<ContextFile>> getContexts() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/contexts'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get contexts: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final contextsList = data['contexts'] as List<dynamic>? ?? [];
      return contextsList
          .map((json) => ContextFile.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ChatService] Error getting contexts: $e');
      rethrow;
    }
  }

  // ============================================================
  // Working Directories
  // ============================================================

  /// Get available working directories for chat sessions
  ///
  /// Returns the home vault plus any recently used directories from existing sessions.
  /// Use these when starting a new chat to work with external codebases.
  Future<DirectoriesInfo> getDirectories() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/directories'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get directories: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return DirectoriesInfo.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting directories: $e');
      rethrow;
    }
  }

  // ============================================================
  // System Prompt
  // ============================================================

  /// Get the built-in default system prompt
  ///
  /// Returns information about the default prompt including:
  /// - content: The actual prompt text
  /// - isActive: Whether it's currently being used (no AGENTS.md override)
  /// - overrideFile: Name of override file if present
  Future<DefaultPromptInfo> getDefaultPrompt() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/default-prompt'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get default prompt: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return DefaultPromptInfo.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting default prompt: $e');
      rethrow;
    }
  }

  /// Get the current AGENTS.md content (if exists)
  Future<AgentsMdInfo> getAgentsMd() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/agents-md'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to get AGENTS.md: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return AgentsMdInfo.fromJson(data);
    } catch (e) {
      debugPrint('[ChatService] Error getting AGENTS.md: $e');
      rethrow;
    }
  }

  /// Save AGENTS.md content
  ///
  /// Creates or updates the AGENTS.md file in the vault root.
  /// This will override the built-in default system prompt.
  Future<void> saveAgentsMd(String content) async {
    try {
      final response = await _client.put(
        Uri.parse('$baseUrl/api/agents-md'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content}),
      ).timeout(requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to save AGENTS.md: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[ChatService] Error saving AGENTS.md: $e');
      rethrow;
    }
  }

  // ============================================================
  // Streaming Chat
  // ============================================================

  /// Send a message and receive streaming response
  /// Returns a stream of events as they arrive
  ///
  /// [contexts] - List of context file paths to load (e.g., ['contexts/general-context.md'])
  /// If not provided, the server will load general-context.md by default
  ///
  /// [priorConversation] - For continued conversations, formatted prior messages
  /// that go into the system prompt (not shown in user message)
  ///
  /// [continuedFrom] - ID of the session this continues from (for persistence)
  ///
  /// [workingDirectory] - Directory for Claude to operate in (for external codebases)
  /// Sessions are still stored in the vault, but file operations target this directory
  /// [recoveryMode] - How to recover when SDK session is unavailable:
  ///   - 'inject_context': Continue with context injection from markdown history
  ///   - 'fresh_start': Start a completely new conversation
  Stream<StreamEvent> streamChat({
    required String sessionId,
    required String message,
    String? agentPath,
    String? initialContext,
    List<String>? contexts,
    String? priorConversation,
    String? continuedFrom,
    String? workingDirectory,
    String? recoveryMode,
  }) async* {
    debugPrint('[ChatService] Starting stream chat');
    debugPrint('[ChatService] Session: $sessionId');
    debugPrint('[ChatService] Agent: $agentPath');
    debugPrint('[ChatService] Working directory: $workingDirectory');
    debugPrint('[ChatService] Message: ${message.substring(0, message.length.clamp(0, 50))}...');
    debugPrint('[ChatService] priorConversation provided: ${priorConversation != null}');
    if (priorConversation != null) {
      debugPrint('[ChatService] priorConversation length: ${priorConversation.length}');
      debugPrint('[ChatService] priorConversation preview: ${priorConversation.substring(0, priorConversation.length.clamp(0, 200))}...');
    }

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/chat/stream'),
    );

    request.headers['Content-Type'] = 'application/json';
    final requestBody = {
      'message': message,
      'agentPath': agentPath,
      'sessionId': sessionId,
      if (initialContext != null) 'initialContext': initialContext,
      if (contexts != null && contexts.isNotEmpty) 'contexts': contexts,
      if (priorConversation != null) 'priorConversation': priorConversation,
      if (continuedFrom != null) 'continuedFrom': continuedFrom,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (recoveryMode != null) 'recoveryMode': recoveryMode,
    };
    debugPrint('[ChatService] Request body keys: ${requestBody.keys.toList()}');
    request.body = jsonEncode(requestBody);

    // Timeouts for streaming requests
    const connectionTimeout = Duration(seconds: 30);
    const chunkTimeout = Duration(seconds: 60); // Allow time for AI thinking

    try {
      final streamedResponse = await _client.send(request).timeout(
        connectionTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection to server timed out after ${connectionTimeout.inSeconds}s',
          );
        },
      );

      if (streamedResponse.statusCode != 200) {
        yield StreamEvent(
          type: StreamEventType.error,
          data: {'error': 'Server returned ${streamedResponse.statusCode}'},
        );
        return;
      }

      String buffer = '';

      // Add per-chunk timeout to detect stalled connections
      await for (final chunk in streamedResponse.stream
          .timeout(chunkTimeout, onTimeout: (sink) {
            sink.addError(TimeoutException(
              'No data received for ${chunkTimeout.inSeconds}s - connection may be stalled',
            ));
            sink.close();
          })
          .transform(utf8.decoder)) {
        buffer += chunk;

        // Process complete lines (SSE format: data: {...}\n\n)
        while (buffer.contains('\n')) {
          final newlineIndex = buffer.indexOf('\n');
          final line = buffer.substring(0, newlineIndex).trim();
          buffer = buffer.substring(newlineIndex + 1);

          if (line.isEmpty) continue;

          final event = StreamEvent.parse(line);
          if (event != null) {
            debugPrint('[ChatService] Event: ${event.type}');
            yield event;

            if (event.type == StreamEventType.done ||
                event.type == StreamEventType.error) {
              return;
            }
          } else if (line.isNotEmpty && !line.startsWith(':')) {
            // Log unexpected parse failures (ignore SSE comments which start with :)
            debugPrint('[ChatService] Failed to parse SSE line: ${line.substring(0, line.length.clamp(0, 100))}');
          }
        }
      }

      // Process any remaining buffer
      if (buffer.trim().isNotEmpty) {
        final event = StreamEvent.parse(buffer.trim());
        if (event != null) {
          yield event;
        }
      }

      debugPrint('[ChatService] Stream completed');
    } catch (e) {
      debugPrint('[ChatService] Stream error: $e');
      yield StreamEvent(
        type: StreamEventType.error,
        data: {'error': e.toString()},
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}

/// A session with its messages
class ChatSessionWithMessages {
  final ChatSession session;
  final List<ChatMessage> messages;

  const ChatSessionWithMessages({
    required this.session,
    required this.messages,
  });

  factory ChatSessionWithMessages.fromJson(Map<String, dynamic> json) {
    final session = ChatSession.fromJson(json);

    final messagesList = json['messages'] as List<dynamic>? ?? [];
    final messages = messagesList.map((m) {
      final msg = m as Map<String, dynamic>;
      return ChatMessage.fromJson({
        ...msg,
        'sessionId': session.id,
      });
    }).toList();

    return ChatSessionWithMessages(
      session: session,
      messages: messages,
    );
  }
}
