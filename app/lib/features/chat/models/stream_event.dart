import 'dart:convert';
import 'chat_message.dart';

/// Type of SSE stream event from the agent backend
enum StreamEventType {
  session,
  init,
  text,
  toolUse,
  done,
  error,
  unknown,
}

/// Parsed SSE event from the chat stream
class StreamEvent {
  final StreamEventType type;
  final Map<String, dynamic> data;

  const StreamEvent({
    required this.type,
    required this.data,
  });

  /// Parse an SSE event from raw line
  /// Expected format: data: {...json...}
  static StreamEvent? parse(String line) {
    if (!line.startsWith('data: ')) return null;

    final jsonStr = line.substring(6).trim();
    if (jsonStr.isEmpty || jsonStr == '[DONE]') {
      return const StreamEvent(
        type: StreamEventType.done,
        data: {},
      );
    }

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final typeStr = json['type'] as String? ?? 'unknown';

      StreamEventType type;
      switch (typeStr) {
        case 'session':
          type = StreamEventType.session;
          break;
        case 'init':
          type = StreamEventType.init;
          break;
        case 'text':
          type = StreamEventType.text;
          break;
        case 'tool_use':
          type = StreamEventType.toolUse;
          break;
        case 'done':
          type = StreamEventType.done;
          break;
        case 'error':
          type = StreamEventType.error;
          break;
        default:
          type = StreamEventType.unknown;
      }

      return StreamEvent(type: type, data: json);
    } catch (e) {
      return StreamEvent(
        type: StreamEventType.error,
        data: {'error': 'Failed to parse event: $e', 'raw': jsonStr},
      );
    }
  }

  /// Get session ID from session event
  String? get sessionId => data['sessionId'] as String?;

  /// Get session title from session or done event
  String? get sessionTitle => data['title'] as String?;

  /// Get text content from text event
  String? get textContent => data['content'] as String?;

  /// Get tool call from tool_use event
  ToolCall? get toolCall {
    final tool = data['tool'] as Map<String, dynamic>?;
    if (tool == null) return null;
    return ToolCall.fromJson(tool);
  }

  /// Get error message from error event
  String? get errorMessage => data['error'] as String?;

  /// Get duration from done event
  int? get durationMs => data['durationMs'] as int?;
}
