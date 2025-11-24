import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/message.dart';
import '../../../core/providers/api_provider.dart';

// Tool Call State
class ToolCallState {
  final String id;
  final String title;
  final String kind;
  final String status; // "pending", "completed"

  ToolCallState({
    required this.id,
    required this.title,
    required this.kind,
    required this.status,
  });

  ToolCallState copyWith({
    String? id,
    String? title,
    String? kind,
    String? status,
  }) {
    return ToolCallState(
      id: id ?? this.id,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      status: status ?? this.status,
    );
  }
}

// Message State - includes both stored messages and streaming message
class MessageState {
  final List<Message> messages;
  final String? streamingContent; // Content being streamed in real-time
  final bool
  isWaitingForResponse; // True when we've sent a message but no chunks yet
  final List<ToolCallState> activeToolCalls; // Tool calls in progress

  MessageState({
    required this.messages,
    this.streamingContent,
    this.isWaitingForResponse = false,
    this.activeToolCalls = const [],
  });

  MessageState copyWith({
    List<Message>? messages,
    String? streamingContent,
    bool? isWaitingForResponse,
    List<ToolCallState>? activeToolCalls,
    bool clearStreaming = false,
    bool clearToolCalls = false,
  }) {
    return MessageState(
      messages: messages ?? this.messages,
      streamingContent: clearStreaming
          ? null
          : (streamingContent ?? this.streamingContent),
      isWaitingForResponse: isWaitingForResponse ?? this.isWaitingForResponse,
      activeToolCalls: clearToolCalls
          ? []
          : (activeToolCalls ?? this.activeToolCalls),
    );
  }
}

// Message State Notifier - manages real-time message updates
class MessageNotifier extends StateNotifier<AsyncValue<MessageState>> {
  final Ref ref;
  String? _currentConversationId;
  StreamSubscription? _wsSubscription;

  MessageNotifier(this.ref) : super(const AsyncValue.loading()) {
    _listenToWebSocket();
  }

  void _listenToWebSocket() {
    final wsClient = ref.read(webSocketClientProvider);
    _wsSubscription = wsClient.messages.listen((message) {
      debugPrint('📩 WebSocket message received: ${message['type']}');

      final type = message['type'] as String?;
      final payload = message['payload'] as Map<String, dynamic>?;
      final conversationId = payload?['conversation_id'] as String?;

      debugPrint(
        '   Conversation ID: $conversationId, Current: $_currentConversationId',
      );

      // Only process messages for the current conversation
      if (conversationId != _currentConversationId) {
        debugPrint('   ⏭️  Skipping message for different conversation');
        return;
      }

      if (type == 'message_chunk') {
        final chunk = payload?['chunk'] as String?;
        debugPrint(
          '   💬 Message chunk: ${chunk?.substring(0, chunk.length > 50 ? 50 : chunk.length)}...',
        );
        if (chunk != null) {
          addStreamingChunk(chunk);
        }
      } else if (type == 'tool_call') {
        final toolCallId = payload?['tool_call_id'] as String?;
        final title = payload?['title'] as String?;
        final kind = payload?['kind'] as String?;
        final status = payload?['status'] as String?;

        debugPrint('   🔧 Tool call: $title ($kind) - $status');

        if (toolCallId != null &&
            title != null &&
            kind != null &&
            status != null) {
          addToolCall(toolCallId, title, kind, status);
        }
      } else if (type == 'tool_call_update') {
        final toolCallId = payload?['tool_call_id'] as String?;
        final status = payload?['status'] as String?;

        debugPrint('   ✅ Tool call update: $toolCallId -> $status');

        if (toolCallId != null && status != null) {
          updateToolCall(toolCallId, status);
        }
      }
    });
  }

  Future<void> setConversation(String? conversationId) async {
    // Clear any existing streaming state when switching conversations
    final isChangingConversation = _currentConversationId != conversationId;

    _currentConversationId = conversationId;

    if (conversationId == null) {
      state = AsyncValue.data(MessageState(messages: []));
      return;
    }

    // If changing conversations, immediately clear streaming state
    if (isChangingConversation) {
      debugPrint('🔄 Switching conversations, clearing streaming state');
      state = AsyncValue.data(
        MessageState(
          messages: [],
          streamingContent: null,
          isWaitingForResponse: false,
          activeToolCalls: [],
        ),
      );
    }

    // Subscribe to WebSocket updates for this conversation
    final wsClient = ref.read(webSocketClientProvider);
    if (wsClient.isConnected) {
      debugPrint('🔌 Subscribing to conversation: $conversationId');
      wsClient.subscribe(conversationId);
    }

    await _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    if (_currentConversationId == null) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final messages = await apiClient.getMessages(_currentConversationId!);

      state.whenData((currentState) {
        // Only preserve streaming state if we're actively streaming for THIS conversation
        final isActivelyStreaming =
            currentState.isWaitingForResponse ||
            currentState.streamingContent != null ||
            currentState.activeToolCalls.isNotEmpty;

        // Check if there's a new assistant message (last message is from assistant and it's new)
        final hasNewAssistantMessage =
            messages.isNotEmpty &&
            messages.length > currentState.messages.length &&
            messages.last.role == 'assistant';

        // Clear streaming state if we got a new assistant message
        final shouldClearStreaming =
            isActivelyStreaming && hasNewAssistantMessage;

        state = AsyncValue.data(
          MessageState(
            messages: messages,
            streamingContent: shouldClearStreaming
                ? null
                : currentState.streamingContent,
            isWaitingForResponse: shouldClearStreaming
                ? false
                : currentState.isWaitingForResponse,
            activeToolCalls: shouldClearStreaming
                ? []
                : currentState.activeToolCalls,
          ),
        );
      });

      // If state wasn't data before, just set it
      if (state is! AsyncData) {
        state = AsyncValue.data(MessageState(messages: messages));
      }
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void setWaitingForResponse() {
    state.whenData((currentState) {
      state = AsyncValue.data(
        currentState.copyWith(isWaitingForResponse: true, clearStreaming: true),
      );
    });
  }

  void addStreamingChunk(String chunk) {
    state.whenData((currentState) {
      final newContent = (currentState.streamingContent ?? '') + chunk;

      // If all tool calls are completed and we're getting new content,
      // clear the tool calls since they're done
      final allToolCallsCompleted =
          currentState.activeToolCalls.isNotEmpty &&
          currentState.activeToolCalls.every((tc) => tc.status == 'completed');

      state = AsyncValue.data(
        currentState.copyWith(
          streamingContent: newContent,
          isWaitingForResponse: false,
          clearToolCalls: allToolCallsCompleted,
        ),
      );
    });
  }

  void clearStreaming() {
    state.whenData((currentState) {
      state = AsyncValue.data(
        currentState.copyWith(
          clearStreaming: true,
          isWaitingForResponse: false,
          clearToolCalls: true,
        ),
      );
    });
  }

  void addToolCall(String id, String title, String kind, String status) {
    debugPrint('➕ Adding tool call: $title ($kind) - $status');
    state.whenData((currentState) {
      final toolCalls = List<ToolCallState>.from(currentState.activeToolCalls);
      toolCalls.add(
        ToolCallState(id: id, title: title, kind: kind, status: status),
      );
      debugPrint('   Active tool calls count: ${toolCalls.length}');
      state = AsyncValue.data(
        currentState.copyWith(
          activeToolCalls: toolCalls,
          isWaitingForResponse: false,
        ),
      );
    });
  }

  void updateToolCall(String id, String status) {
    debugPrint('🔄 Updating tool call: $id -> $status');
    state.whenData((currentState) {
      final toolCalls = currentState.activeToolCalls.map((tc) {
        if (tc.id == id) {
          return tc.copyWith(status: status);
        }
        return tc;
      }).toList();

      debugPrint(
        '   Updated tool calls. Completed: ${toolCalls.where((tc) => tc.status == 'completed').length}/${toolCalls.length}',
      );

      // Keep tool calls visible even when all completed
      // They'll be cleared when the final message arrives from the database
      state = AsyncValue.data(
        currentState.copyWith(activeToolCalls: toolCalls),
      );
    });
  }

  Future<void> refresh() async {
    await _fetchMessages();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }
}

// WebSocket Client Provider
final webSocketClientProvider = Provider((ref) {
  final wsClient = ref.read(apiClientProvider).wsClient;
  return wsClient;
});

// Message State Provider
final messageStateProvider =
    StateNotifierProvider<MessageNotifier, AsyncValue<MessageState>>((ref) {
      return MessageNotifier(ref);
    });

// Message Actions Provider
final messageActionsProvider = Provider((ref) => MessageActions(ref));

class MessageActions {
  final Ref ref;

  MessageActions(this.ref);

  Future<Message> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    // Set waiting state
    ref.read(messageStateProvider.notifier).setWaitingForResponse();

    final apiClient = ref.read(apiClientProvider);
    final message = await apiClient.sendMessage(
      conversationId: conversationId,
      content: content,
    );

    // Refresh the message list
    await ref.read(messageStateProvider.notifier).refresh();

    return message;
  }
}
