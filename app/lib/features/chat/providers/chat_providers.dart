import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/agent.dart';
import '../models/stream_event.dart';
import '../models/context_file.dart';
import '../models/session_resume_info.dart';
import '../services/chat_service.dart';
import '../services/local_session_reader.dart';
import '../services/chat_import_service.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/providers/file_system_provider.dart';
import 'package:app/core/providers/search_providers.dart';

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

/// Provider for the chat import service
///
/// Used to import chat history from ChatGPT, Claude, and other sources.
final chatImportServiceProvider = Provider<ChatImportService>((ref) {
  final fileSystemService = ref.watch(fileSystemServiceProvider);
  return ChatImportService(fileSystemService);
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
// Context Providers
// ============================================================

/// Provider for fetching available context files from the vault
///
/// Returns a list of context files that can be loaded into chat sessions.
/// The server reads these from the vault's contexts/ folder.
final availableContextsProvider = FutureProvider<List<ContextFile>>((ref) async {
  final service = ref.watch(chatServiceProvider);
  try {
    return await service.getContexts();
  } catch (e) {
    debugPrint('[ChatProviders] Error fetching contexts: $e');
    return [];
  }
});

/// Provider for the currently selected contexts for a chat session
///
/// By default, includes general-context.md if it exists.
/// Users can add or remove contexts before starting a chat.
final selectedContextsProvider = StateProvider<List<ContextFile>>((ref) {
  // Auto-select the default context (general-context.md) when available
  final contextsAsync = ref.watch(availableContextsProvider);
  return contextsAsync.when(
    data: (contexts) => contexts.where((c) => c.isDefault).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

/// Provider for toggling context selection
final toggleContextProvider = Provider<void Function(ContextFile)>((ref) {
  return (ContextFile context) {
    final current = ref.read(selectedContextsProvider);
    final isSelected = current.any((c) => c.path == context.path);

    if (isSelected) {
      ref.read(selectedContextsProvider.notifier).state =
          current.where((c) => c.path != context.path).toList();
    } else {
      ref.read(selectedContextsProvider.notifier).state = [...current, context];
    }
  };
});

/// Clear selected contexts (reset to defaults)
final resetContextsProvider = Provider<void Function()>((ref) {
  return () {
    final contextsAsync = ref.read(availableContextsProvider);
    contextsAsync.whenData((contexts) {
      ref.read(selectedContextsProvider.notifier).state =
          contexts.where((c) => c.isDefault).toList();
    });
  };
});

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

  /// If this is a continuation, the original session being continued
  final ChatSession? continuedFromSession;

  /// Messages from the original session (for display in resume marker)
  final List<ChatMessage> priorMessages;

  /// The session being viewed (for imported sessions that can be continued)
  final ChatSession? viewingSession;

  /// Information about how the session was resumed
  /// Set when receiving a session or done event from the backend
  final SessionResumeInfo? sessionResumeInfo;

  const ChatMessagesState({
    this.messages = const [],
    this.isStreaming = false,
    this.error,
    this.sessionId,
    this.sessionTitle,
    this.continuedFromSession,
    this.priorMessages = const [],
    this.viewingSession,
    this.sessionResumeInfo,
  });

  /// Whether this session is continuing from another
  bool get isContinuation => continuedFromSession != null;

  /// Whether we're viewing an imported session that can be continued
  bool get isViewingImported => viewingSession?.isImported ?? false;

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? error,
    String? sessionId,
    String? sessionTitle,
    ChatSession? continuedFromSession,
    List<ChatMessage>? priorMessages,
    ChatSession? viewingSession,
    SessionResumeInfo? sessionResumeInfo,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      error: error,
      sessionId: sessionId ?? this.sessionId,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      continuedFromSession: continuedFromSession ?? this.continuedFromSession,
      priorMessages: priorMessages ?? this.priorMessages,
      viewingSession: viewingSession ?? this.viewingSession,
      sessionResumeInfo: sessionResumeInfo ?? this.sessionResumeInfo,
    );
  }
}

/// Notifier for managing chat messages and streaming
class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final ChatService _service;
  final Ref _ref;
  static const _uuid = Uuid();

  /// Track the session ID of the currently active stream
  /// Used to prevent old streams from updating state after session switch
  String? _activeStreamSessionId;

  ChatMessagesNotifier(this._service, this._ref) : super(const ChatMessagesState());

  /// Load messages for a session
  ///
  /// Tries the server first, falls back to local files for imported/local sessions.
  /// Also cancels any active stream by invalidating the stream session ID.
  /// If the session was continued from another session, loads prior messages too.
  Future<void> loadSession(String sessionId, {bool isLocal = false}) async {
    _activeStreamSessionId = null; // Cancel any active stream

    try {
      ChatSession? loadedSession;
      List<ChatMessage> loadedMessages = [];

      // Try server first unless we know it's local
      if (!isLocal) {
        try {
          final sessionData = await _service.getSession(sessionId);
          if (sessionData != null) {
            loadedSession = sessionData.session;
            loadedMessages = sessionData.messages;
          }
        } catch (e) {
          debugPrint('[ChatMessagesNotifier] Server unavailable, trying local: $e');
        }
      }

      // Fall back to local session reader if not found on server
      if (loadedSession == null) {
        final localReader = _ref.read(localSessionReaderProvider);
        final localSession = await localReader.getSession(sessionId);
        if (localSession != null) {
          loadedSession = localSession.session;
          loadedMessages = localSession.messages;
        }
      }

      if (loadedSession == null) {
        state = state.copyWith(error: 'Session not found');
        return;
      }

      // Check if this session continues another - load prior messages
      List<ChatMessage> priorMessages = [];
      ChatSession? continuedFromSession;

      if (loadedSession.continuedFrom != null) {
        debugPrint('[ChatMessagesNotifier] Session continues from: ${loadedSession.continuedFrom}');
        final localReader = _ref.read(localSessionReaderProvider);
        final originalSession = await localReader.getSession(loadedSession.continuedFrom!);
        if (originalSession != null) {
          priorMessages = originalSession.messages;
          continuedFromSession = originalSession.session;
          debugPrint('[ChatMessagesNotifier] Loaded ${priorMessages.length} prior messages');
        } else {
          debugPrint('[ChatMessagesNotifier] Could not find original session to load prior messages');
        }
      }

      // SIMPLIFIED: The session id IS the SDK session ID now
      // Just use it directly for all API calls
      debugPrint('[ChatMessagesNotifier] Loading session with ID: $sessionId');

      state = ChatMessagesState(
        messages: loadedMessages,
        sessionId: sessionId,
        sessionTitle: loadedSession.title,
        viewingSession: loadedSession.isImported ? loadedSession : null,
        priorMessages: priorMessages,
        continuedFromSession: continuedFromSession,
      );
    } catch (e) {
      debugPrint('[ChatMessagesNotifier] Error loading session: $e');
      state = state.copyWith(error: e.toString());
    }
  }

  /// Clear current session (for new chat)
  ///
  /// Also cancels any active stream by invalidating the stream session ID.
  void clearSession() {
    _activeStreamSessionId = null; // Cancel any active stream
    state = const ChatMessagesState();
  }

  /// Set up a continuation from an existing session
  ///
  /// This prepares the chat state to continue from an imported or prior session.
  /// The prior messages are stored for display in the resume marker,
  /// and will be passed as context with the first message.
  void setupContinuation({
    required ChatSession originalSession,
    required List<ChatMessage> priorMessages,
  }) {
    debugPrint('[ChatMessagesNotifier] setupContinuation called');
    debugPrint('[ChatMessagesNotifier] Original session: ${originalSession.id}');
    debugPrint('[ChatMessagesNotifier] Prior messages: ${priorMessages.length}');
    if (priorMessages.isNotEmpty) {
      debugPrint('[ChatMessagesNotifier] First prior message: ${priorMessages.first.textContent.substring(0, (priorMessages.first.textContent.length).clamp(0, 100))}...');
    }
    state = ChatMessagesState(
      continuedFromSession: originalSession,
      priorMessages: priorMessages,
    );
    debugPrint('[ChatMessagesNotifier] State set - isContinuation: ${state.isContinuation}');
  }

  /// Format prior messages as context for the AI
  /// The server wraps this in its own header, so we just provide the messages
  /// Limited to ~50k chars to avoid 413 errors
  String _formatPriorMessagesAsContext() {
    if (state.priorMessages.isEmpty) return '';

    final buffer = StringBuffer();
    const maxChars = 50000;

    // Take most recent messages that fit within limit
    final messages = state.priorMessages.reversed.toList();
    final selectedMessages = <ChatMessage>[];
    int totalChars = 0;

    for (final msg in messages) {
      final content = msg.textContent;
      if (content.isEmpty) continue;

      final msgText = '${msg.role == MessageRole.user ? "Human" : "Assistant"}: $content\n\n';
      if (totalChars + msgText.length > maxChars) break;

      totalChars += msgText.length;
      selectedMessages.insert(0, msg);
    }

    for (final msg in selectedMessages) {
      final role = msg.role == MessageRole.user ? 'Human' : 'Assistant';
      final content = msg.textContent;
      buffer.writeln('$role: $content\n');
    }

    debugPrint('[ChatMessagesNotifier] Formatted ${selectedMessages.length}/${state.priorMessages.length} prior messages ($totalChars chars)');
    return buffer.toString().trim();
  }

  /// Send a message and handle streaming response
  ///
  /// [contexts] - List of context file paths to load. If not provided,
  /// the server will load general-context.md by default.
  ///
  /// [priorConversation] - For continued conversations, prior messages
  /// formatted as text. Goes into system prompt, not shown in chat.
  ///
  /// [workingDirectory] - Directory for Claude to operate in (for external codebases)
  /// Sessions are still stored in the vault, but file operations target this directory.
  Future<void> sendMessage({
    required String message,
    String? agentPath,
    String? initialContext,
    List<String>? contexts,
    String? priorConversation,
    String? workingDirectory,
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

    // Mark this session as the active stream
    _activeStreamSessionId = sessionId;

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantMessage],
      isStreaming: true,
      sessionId: sessionId,
      error: null,
    );

    // Track accumulated content for streaming
    List<MessageContent> accumulatedContent = [];
    String? actualSessionId;

    // Include prior conversation context if this is a continuation
    // This goes into the system prompt, not shown in the user message
    String? effectivePriorConversation = priorConversation;
    debugPrint('[ChatMessagesNotifier] sendMessage - isContinuation: ${state.isContinuation}');
    debugPrint('[ChatMessagesNotifier] sendMessage - messages.length: ${state.messages.length}');
    debugPrint('[ChatMessagesNotifier] sendMessage - priorMessages.length: ${state.priorMessages.length}');
    if (state.isContinuation && state.messages.length <= 2) {
      // Only inject prior context on first message of continuation
      debugPrint('[ChatMessagesNotifier] Injecting prior conversation context');
      final formatted = _formatPriorMessagesAsContext();
      if (formatted.isNotEmpty) {
        effectivePriorConversation = formatted;
        debugPrint('[ChatMessagesNotifier] Formatted context length: ${effectivePriorConversation.length}');
      } else {
        debugPrint('[ChatMessagesNotifier] WARNING: Prior messages formatted to empty string!');
      }
    } else {
      debugPrint('[ChatMessagesNotifier] NOT injecting prior context (isContinuation: ${state.isContinuation}, messages: ${state.messages.length})');
    }

    try {
      // Get continuedFrom ID for first message of continuation (for persistence)
      final continuedFromId = (state.isContinuation && state.messages.length <= 2)
          ? state.continuedFromSession?.id
          : null;
      debugPrint('[ChatMessagesNotifier] continuedFromId: $continuedFromId');
      if (state.isContinuation) {
        debugPrint('[ChatMessagesNotifier] continuedFromSession.id: ${state.continuedFromSession?.id}');
      }

      await for (final event in _service.streamChat(
        sessionId: sessionId,
        message: message,
        agentPath: agentPath,
        initialContext: initialContext,
        contexts: contexts,
        priorConversation: effectivePriorConversation,
        continuedFrom: continuedFromId,
        workingDirectory: workingDirectory,
      )) {
        // Check if session has changed (user switched chats during stream)
        if (_activeStreamSessionId != sessionId) {
          debugPrint('[ChatMessagesNotifier] Stream cancelled - session changed from $sessionId');
          break; // Exit the stream loop
        }

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
            // Capture session resume info
            final resumeInfo = event.sessionResumeInfo;
            if (resumeInfo != null) {
              debugPrint('[ChatMessagesNotifier] Session resume info: ${resumeInfo.method} '
                  '(sdkResumeFailed: ${resumeInfo.sdkResumeFailed}, '
                  'contextInjected: ${resumeInfo.contextInjected}, '
                  'messagesInjected: ${resumeInfo.messagesInjected})');
              state = state.copyWith(sessionResumeInfo: resumeInfo);
            }
            break;

          case StreamEventType.text:
            // Accumulating text content from server
            final content = event.textContent;
            if (content != null) {
              // Track the current text for potential conversion to "thinking"
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
            // Tool call event - convert any pending text to "thinking"
            final toolCall = event.toolCall;
            if (toolCall != null) {
              // Check if there's text content before this tool call
              final lastTextIndex = accumulatedContent.lastIndexWhere(
                  (c) => c.type == ContentType.text);
              if (lastTextIndex >= 0) {
                // Convert the last text block to thinking
                final thinkingText = accumulatedContent[lastTextIndex].text ?? '';
                if (thinkingText.isNotEmpty) {
                  accumulatedContent[lastTextIndex] = MessageContent.thinking(thinkingText);
                }
              }
              accumulatedContent.add(MessageContent.toolUse(toolCall));
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
            break;

          case StreamEventType.toolResult:
            // Tool result - attach to the corresponding tool call
            final toolUseId = event.toolUseId;
            final resultContent = event.toolResultContent;
            if (toolUseId != null && resultContent != null) {
              // Find the tool call with this ID and update it with the result
              for (int i = 0; i < accumulatedContent.length; i++) {
                final content = accumulatedContent[i];
                if (content.type == ContentType.toolUse &&
                    content.toolCall?.id == toolUseId) {
                  // Replace with updated tool call that has the result
                  final updatedToolCall = content.toolCall!.withResult(
                    resultContent,
                    isError: event.toolResultIsError,
                  );
                  accumulatedContent[i] = MessageContent.toolUse(updatedToolCall);
                  _updateAssistantMessage(accumulatedContent, isStreaming: true);
                  break;
                }
              }
            }
            break;

          case StreamEventType.done:
            // Stream complete
            _updateAssistantMessage(accumulatedContent, isStreaming: false);

            // CRITICAL: Capture session ID from done event (for new sessions, this is the first time we get the real ID)
            final doneSessionId = event.sessionId;
            if (doneSessionId != null && doneSessionId.isNotEmpty && doneSessionId != actualSessionId) {
              debugPrint('[ChatMessagesNotifier] Done event has new session ID: $doneSessionId (was: $actualSessionId)');
              actualSessionId = doneSessionId;
              _ref.read(currentSessionIdProvider.notifier).state = doneSessionId;
            }

            // Capture session title if present in done event
            final doneTitle = event.sessionTitle;
            // Also capture resume info from done event (may have more complete info)
            final doneResumeInfo = event.sessionResumeInfo;
            if (doneResumeInfo != null) {
              debugPrint('[ChatMessagesNotifier] Done event resume info: ${doneResumeInfo.method}');
              state = state.copyWith(
                isStreaming: false,
                sessionTitle: (doneTitle != null && doneTitle.isNotEmpty) ? doneTitle : null,
                sessionResumeInfo: doneResumeInfo,
              );
            } else if (doneTitle != null && doneTitle.isNotEmpty) {
              state = state.copyWith(isStreaming: false, sessionTitle: doneTitle);
            } else {
              state = state.copyWith(isStreaming: false);
            }
            // Refresh sessions list to get updated title
            _ref.invalidate(chatSessionsProvider);
            // Index the chat session for search (fire-and-forget)
            // Wrapped in try-catch since vectorStore may not be ready yet
            try {
              final indexSessionId = actualSessionId ?? state.sessionId ?? sessionId;
              _ref.read(searchIndexServiceProvider).indexChatSessionById(indexSessionId);
            } catch (e) {
              debugPrint('[ChatMessagesNotifier] Search indexing skipped: $e');
            }
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

          case StreamEventType.thinking:
            // Extended thinking content from Claude
            final thinkingText = event.thinkingContent;
            if (thinkingText != null && thinkingText.isNotEmpty) {
              accumulatedContent.add(MessageContent.thinking(thinkingText));
              _updateAssistantMessage(accumulatedContent, isStreaming: true);
            }
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
///
/// Set [isLocal] to true for imported or local-only sessions that don't
/// need to check the server.
final switchSessionProvider = Provider<Future<void> Function(String, {bool isLocal})>((ref) {
  return (String sessionId, {bool isLocal = false}) async {
    ref.read(currentSessionIdProvider.notifier).state = sessionId;
    await ref.read(chatMessagesProvider.notifier).loadSession(sessionId, isLocal: isLocal);
  };
});

/// Provider for continuing an imported session
///
/// Creates a new chat that continues from the given session,
/// passing all prior messages as context for the AI.
final continueSessionProvider = Provider<Future<void> Function(ChatSession)>((ref) {
  final service = ref.watch(chatServiceProvider);
  final localReader = ref.watch(localSessionReaderProvider);

  return (ChatSession originalSession) async {
    debugPrint('[ChatProviders] continueSessionProvider called');
    debugPrint('[ChatProviders] Original session ID: ${originalSession.id}');
    debugPrint('[ChatProviders] isLocal: ${originalSession.isLocal}, isImported: ${originalSession.isImported}');

    try {
      List<ChatMessage> priorMessages = [];

      // For local/imported sessions, use local reader
      // For server sessions, try the server API
      if (originalSession.isLocal || originalSession.isImported) {
        debugPrint('[ChatProviders] Loading from local reader...');
        final localSession = await localReader.getSession(originalSession.id);
        if (localSession == null) {
          debugPrint('[ChatProviders] WARNING: localReader.getSession returned null!');
        } else {
          priorMessages = localSession.messages;
          debugPrint('[ChatProviders] Loaded ${priorMessages.length} messages from local session');
          if (priorMessages.isNotEmpty) {
            debugPrint('[ChatProviders] First message preview: ${priorMessages.first.textContent.substring(0, priorMessages.first.textContent.length.clamp(0, 100))}...');
          }
        }
      } else {
        debugPrint('[ChatProviders] Loading from server...');
        final sessionData = await service.getSession(originalSession.id);
        priorMessages = sessionData?.messages ?? [];
        debugPrint('[ChatProviders] Loaded ${priorMessages.length} messages from server');
      }

      // Clear current session and set up continuation
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).setupContinuation(
        originalSession: originalSession,
        priorMessages: priorMessages,
      );
    } catch (e, st) {
      debugPrint('[ChatProviders] Error setting up continuation: $e');
      debugPrint('[ChatProviders] Stack trace: $st');
      // Fall back to just clearing the session
      ref.read(currentSessionIdProvider.notifier).state = null;
      ref.read(chatMessagesProvider.notifier).clearSession();
    }
  };
});
