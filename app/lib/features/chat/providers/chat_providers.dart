import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent.dart';
import '../models/stream_event.dart';
import '../services/chat_service.dart';
import '../services/local_session_reader.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/core/services/file_system_service.dart';

// ============================================================
// Service Provider
// ============================================================

// Note: aiServerUrlProvider is imported from feature_flags_provider.dart
// Do NOT redefine it here - that was causing the URL not to update bug!

/// Provider for ChatService
///
/// Creates a new ChatService instance with the configured server URL.
/// The service handles all communication with the parachute-agent backend.
final chatServiceProvider = Provider<ChatService>((ref) {
  // Watch the server URL - this will rebuild ChatService when URL changes
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? 'http://localhost:3333';

  final service = ChatService(baseUrl: baseUrl);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider for the local session reader (reads from vault markdown files)
final localSessionReaderProvider = Provider<LocalSessionReader>((ref) {
  return LocalSessionReader(FileSystemService());
});

// ============================================================
// Session Providers
// ============================================================

/// Provider for fetching all chat sessions
///
/// Tries to fetch from the server first. If server is unavailable,
/// falls back to reading local session files from the vault.
final chatSessionsProvider = FutureProvider<List<ChatSession>>((ref) async {
  final service = ref.watch(chatServiceProvider);
  final localReader = ref.watch(localSessionReaderProvider);

  try {
    // Try server first
    final serverSessions = await service.getSessions();
    debugPrint('[ChatProviders] Loaded ${serverSessions.length} sessions from server');
    return serverSessions;
  } catch (e) {
    debugPrint('[ChatProviders] Server unavailable, falling back to local sessions: $e');

    // Fall back to local sessions
    try {
      final localSessions = await localReader.getLocalSessions();
      debugPrint('[ChatProviders] Loaded ${localSessions.length} local sessions');
      return localSessions;
    } catch (localError) {
      debugPrint('[ChatProviders] Error loading local sessions: $localError');
      return [];
    }
  }
});

/// Provider for the current session ID
///
/// When null, indicates a new chat should be started.
/// When set, the chat screen shows that session's messages.
final currentSessionIdProvider = StateProvider<String?>((ref) => null);

/// Provider for fetching a specific session with messages
final sessionWithMessagesProvider =
    FutureProvider.family<ChatSessionWithMessages?, String>((ref, sessionId) async {
  final service = ref.watch(chatServiceProvider);
  try {
    return await service.getSession(sessionId);
  } catch (e) {
    debugPrint('[ChatProviders] Error fetching session $sessionId: $e');
    return null;
  }
});

// ============================================================
// Agent Providers
// ============================================================

/// Provider for fetching available agents
final agentsProvider = FutureProvider<List<Agent>>((ref) async {
  final service = ref.watch(chatServiceProvider);
  try {
    return await service.getAgents();
  } catch (e) {
    debugPrint('[ChatProviders] Error fetching agents: $e');
    return [];
  }
});

/// Provider for the currently selected agent
///
/// When null, uses the default vault agent.
final selectedAgentProvider = StateProvider<Agent?>((ref) => null);

// ============================================================
// Chat State Management
// ============================================================

/// State for the chat messages list with streaming support
class ChatMessagesState {
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? error;
  final String? sessionId;
  final String? sessionTitle;

  const ChatMessagesState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.sessionId,
    this.sessionTitle,
  });

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? error,
    String? sessionId,
    String? sessionTitle,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
      sessionId: sessionId ?? this.sessionId,
      sessionTitle: sessionTitle ?? this.sessionTitle,
    );
  }
}

/// Notifier for managing chat messages and streaming
class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final ChatService _service;
  final Ref _ref;
  static const _uuid = Uuid();

  ChatMessagesNotifier(this._service, this._ref) : super(const ChatMessagesState());

  /// Load messages for a session
  Future<void> loadSession(String sessionId) async {
    try {
      final sessionData = await _service.getSession(sessionId);
      if (sessionData != null) {
        state = ChatMessagesState(
          messages: sessionData.messages,
          sessionId: sessionId,
          sessionTitle: sessionData.session.title,
        );
      }
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] Error loading session: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  /// Clear current session (for new chat)
  void clearSession() {
    state = const ChatMessagesState();
  }

  /// Send a message and handle streaming response
  Future<void> sendMessage({
    required String message,
    String? agentPath,
    String? initialContext,
  }) async {
    if (state.isStreaming) return;

    // Generate or use existing session ID
    final sessionId = state.sessionId ?? _uuid.v4();

    // Add user message immediately
    final userMessage = ChatMessage.user(
      sessionId: sessionId,
      text: message,
    );

    // Create placeholder for assistant response
    final assistantMessage = ChatMessage.assistantPlaceholder(
      sessionId: sessionId,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantMessage],
      isStreaming: true,
      sessionId: sessionId,
      error: null,
    );

    // Track accumulated content for streaming
    List<MessageContent> accumulatedContent = [];
    String? actualSessionId;

    try {
      await for (final event in _service.streamChat(
        sessionId: sessionId,
        message: message,
        agentPath: agentPath,
        initialContext: initialContext,
      )) {
        switch (event.type) {
          case StreamEventType.session:
            // Server may return a different session ID
            actualSessionId = event.sessionId;
            if (actualSessionId != null && actualSessionId != sessionId) {
              // Update session ID if server assigned a different one
              _ref.read(currentSessionIdProvider.notifier).state = actualSessionId;
            }
            // Capture session title if present
            final sessionTitle = event.sessionTitle;
            if (sessionTitle != null && sessionTitle.isNotEmpty) {
              state = state.copyWith(sessionTitle: sessionTitle);
            }
            break;

          case StreamEventType.text:
            // Accumulating text content from server
            final content = event.textContent;
            if (content != null) {
              // Replace or add text content
              // The server sends accumulated text, so we replace the last text block
              final hasTextContent = accumulatedContent.any((c) => c.type == ContentType.text);
              if (hasTextContent) {
                // Replace the last text content
                final lastTextIndex = accumulatedContent.lastIndexWhere(
                    (c) => c.type == ContentType.text);
                accumulatedContent[lastTextIndex] = MessageContent.text(content);
              } else {
                accumulatedContent.add(MessageContent.text(content));
              }
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.toolUse:
            // Tool call event
            final toolCall = event.toolCall;
            if (toolCall != null) {
              accumulatedContent.add(MessageContent.toolUse(toolCall));
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.done:
            // Stream complete
            _updateAssistantMessage(accumulatedContent, isStreaming: false);
            // Capture session title if present in done event
            final doneTitle = event.sessionTitle;
            if (doneTitle != null && doneTitle.isNotEmpty) {
              state = state.copyWith(isStreaming: false, sessionTitle: doneTitle);
            } else {
              state = state.copyWith(isStreaming: false);
            }
            // Refresh sessions list to get updated title
            _ref.invalidate(chatSessionsProvider);
            break;

          case StreamEventType.error:
            final errorMsg = event.errorMessage ?? 'Unknown error';
            state = state.copyWith(
              isStreaming: false,
              error: errorMsg,
            );
            _updateAssistantMessage(
              [MessageContent.text('Error: $errorMsg')],
              isStreaming: false,
            );
            break;

          case StreamEventType.init:
          case StreamEventType.unknown:
            // Ignore init and unknown events
            break;
        }
      }
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] Stream error: $e');
      state = state.copyWith(
        isStreaming: false,
        error: e.toString(),
      );
      _updateAssistantMessage(
        [MessageContent.text('Error: $e')],
        isStreaming: false,
      );
    }
  }

  /// Update the assistant message being streamed
  void _updateAssistantMessage(List<MessageContent> content, {required bool isStreaming}) {
    final messages = List<ChatMessage>.from(state.messages);
    if (messages.isEmpty) return;

    // Find the last assistant message (should be the streaming one)
    final lastIndex = messages.length - 1;
    if (messages[lastIndex].role != MessageRole.assistant) return;

    messages[lastIndex] = messages[lastIndex].copyWith(
      content: List.from(content),
      isStreaming: isStreaming,
    );

    state = state.copyWith(messages: messages);
  }
}

/// Provider for chat messages state
final chatMessagesProvider =
    StateNotifierProvider<ChatMessagesNotifier, ChatMessagesState>((ref) {
  final service = ref.watch(chatServiceProvider);
  return ChatMessagesNotifier(service, ref);
});

// ============================================================
// Session Management Actions
// ============================================================

/// Provider for deleting a session
final deleteSessionProvider = Provider<Future<void> Function(String)>((ref) {
  final service = ref.watch(chatServiceProvider);
  return (String sessionId) async {
    await service.deleteSession(sessionId);
    // Clear current session if it was deleted
    if (ref.read(currentSessionIdProvider) == sessionId) {
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).clearSession();
    }
    // Refresh sessions list
    ref.invalidate(chatSessionsProvider);
  };
});

/// Provider for creating a new chat
final newChatProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(currentSessionIdProvider.notifier).state = null;
    ref.read(chatMessagesProvider.notifier).clearSession();
  };
});

/// Provider for switching to a session
final switchSessionProvider = Provider<Future<void> Function(String)>((ref) {
  return (String sessionId) async {
    ref.read(currentSessionIdProvider.notifier).state = sessionId;
    await ref.read(chatMessagesProvider.notifier).loadSession(sessionId);
  };
});
