/// Role of the message sender
enum MessageRole { user, assistant }

/// Type of content within a message
enum ContentType { text, toolUse }

/// A tool call made by the assistant
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ToolCall({
    required this.id,
    required this.name,
    required this.input,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      input: json['input'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Summarize the tool input for display
  String get summary {
    final toolName = name.toLowerCase();

    // File operations - show filename
    if (toolName == 'read' || toolName.contains('read')) {
      return input['file_path'] as String? ??
          input['path'] as String? ??
          '';
    }

    // Bash commands - show truncated command
    if (toolName == 'bash' || toolName.contains('bash')) {
      final cmd = input['command'] as String? ?? '';
      return cmd.length > 50 ? '${cmd.substring(0, 47)}...' : cmd;
    }

    // Search operations - show pattern
    if (toolName == 'glob' || toolName.contains('glob')) {
      return input['pattern'] as String? ?? '';
    }

    if (toolName == 'grep' || toolName.contains('grep')) {
      return input['pattern'] as String? ?? '';
    }

    // Write/Edit - show file path
    if (toolName == 'write' || toolName == 'edit') {
      return input['file_path'] as String? ?? '';
    }

    // Default - try common field names
    return input['file_path'] as String? ??
        input['path'] as String? ??
        input['pattern'] as String? ??
        input['query'] as String? ??
        '';
  }
}

/// A piece of content within a message (text or tool use)
class MessageContent {
  final ContentType type;
  final String? text;
  final ToolCall? toolCall;

  const MessageContent({
    required this.type,
    this.text,
    this.toolCall,
  });

  factory MessageContent.text(String text) {
    return MessageContent(type: ContentType.text, text: text);
  }

  factory MessageContent.toolUse(ToolCall toolCall) {
    return MessageContent(type: ContentType.toolUse, toolCall: toolCall);
  }
}

/// A chat message with ordered content (text and tool calls interleaved)
class ChatMessage {
  final String id;
  final String sessionId;
  final MessageRole role;
  final List<MessageContent> content;
  final DateTime timestamp;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
  });

  /// Get the full text content (concatenated)
  String get textContent {
    return content
        .where((c) => c.type == ContentType.text)
        .map((c) => c.text ?? '')
        .join('');
  }

  /// Get all tool calls
  List<ToolCall> get toolCalls {
    return content
        .where((c) => c.type == ContentType.toolUse)
        .map((c) => c.toolCall!)
        .toList();
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final role = json['role'] == 'user' ? MessageRole.user : MessageRole.assistant;

    // Parse content - could be string or structured
    List<MessageContent> content = [];
    if (json['content'] is String) {
      content = [MessageContent.text(json['content'] as String)];
    } else if (json['content'] is List) {
      content = (json['content'] as List).map((c) {
        if (c is String) {
          return MessageContent.text(c);
        } else if (c is Map<String, dynamic>) {
          if (c['type'] == 'tool_use') {
            return MessageContent.toolUse(ToolCall.fromJson(c));
          } else {
            return MessageContent.text(c['text'] as String? ?? '');
          }
        }
        return MessageContent.text('');
      }).toList();
    }

    return ChatMessage(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      sessionId: json['sessionId'] as String? ?? '',
      role: role,
      content: content,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      isStreaming: json['isStreaming'] as bool? ?? false,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    List<MessageContent>? content,
    DateTime? timestamp,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  /// Create a user message
  factory ChatMessage.user({
    required String sessionId,
    required String text,
  }) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sessionId: sessionId,
      role: MessageRole.user,
      content: [MessageContent.text(text)],
      timestamp: DateTime.now(),
    );
  }

  /// Create a placeholder assistant message for streaming
  factory ChatMessage.assistantPlaceholder({
    required String sessionId,
  }) {
    return ChatMessage(
      id: 'streaming-${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      role: MessageRole.assistant,
      content: [],
      timestamp: DateTime.now(),
      isStreaming: true,
    );
  }
}
