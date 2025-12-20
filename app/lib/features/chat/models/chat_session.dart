/// Represents a chat session with an AI agent
class ChatSession {
  final String id;
  final String? agentPath;
  final String? agentName;
  final String? title;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int messageCount;
  final bool archived;

  /// Whether this session was loaded from local files (vs from server API)
  final bool isLocal;

  const ChatSession({
    required this.id,
    this.agentPath,
    this.agentName,
    this.title,
    required this.createdAt,
    this.updatedAt,
    this.messageCount = 0,
    this.archived = false,
    this.isLocal = false,
  });

  /// Alias for archived (for consistency with local session reader)
  bool get isArchived => archived;

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    // Handle both 'updatedAt' and 'lastAccessed' field names from backend
    final updatedAtStr = json['updatedAt'] as String? ?? json['lastAccessed'] as String?;

    return ChatSession(
      id: json['id'] as String? ?? json['context']?['sessionId'] as String? ?? '',
      agentPath: json['agentPath'] as String?,
      agentName: json['agentName'] as String?,
      title: json['title'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: updatedAtStr != null ? DateTime.parse(updatedAtStr) : null,
      messageCount: json['messageCount'] as int? ?? 0,
      archived: json['archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agentPath': agentPath,
      'agentName': agentName,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'messageCount': messageCount,
      'archived': archived,
    };
  }

  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    if (agentName != null && agentName!.isNotEmpty) return 'Chat with $agentName';
    return 'New Chat';
  }

  ChatSession copyWith({
    String? id,
    String? agentPath,
    String? agentName,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    bool? archived,
    bool? isLocal,
  }) {
    return ChatSession(
      id: id ?? this.id,
      agentPath: agentPath ?? this.agentPath,
      agentName: agentName ?? this.agentName,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      archived: archived ?? this.archived,
      isLocal: isLocal ?? this.isLocal,
    );
  }
}
