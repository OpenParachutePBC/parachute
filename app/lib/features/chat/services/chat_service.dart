import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent.dart';
import '../models/stream_event.dart';

/// Service for communicating with the parachute-agent backend
class ChatService {
  final String baseUrl;
  final http.Client _client;

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
      );

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

  /// Get a specific session with messages
  Future<ChatSessionWithMessages?> getSession(String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/api/chat/session/${Uri.encodeComponent(sessionId)}'),
        headers: {'Content-Type': 'application/json'},
      );

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
      );

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
      );

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
      );

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
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ChatService] Error checking document: $e');
      return false;
    }
  }

  // ============================================================
  // Streaming Chat
  // ============================================================

  /// Send a message and receive streaming response
  /// Returns a stream of events as they arrive
  Stream<StreamEvent> streamChat({
    required String sessionId,
    required String message,
    String? agentPath,
    String? initialContext,
  }) async* {
    debugPrint('[ChatService] Starting stream chat');
    debugPrint('[ChatService] Session: $sessionId');
    debugPrint('[ChatService] Agent: $agentPath');
    debugPrint('[ChatService] Message: ${message.substring(0, message.length.clamp(0, 50))}...');

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/chat/stream'),
    );

    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'message': message,
      'agentPath': agentPath,
      'sessionId': sessionId,
      if (initialContext != null) 'initialContext': initialContext,
    });

    try {
      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200) {
        yield StreamEvent(
          type: StreamEventType.error,
          data: {'error': 'Server returned ${streamedResponse.statusCode}'},
        );
        return;
      }

      String buffer = '';

      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
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
