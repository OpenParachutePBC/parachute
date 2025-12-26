import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/ask/models/ask_result.dart';
import 'package:app/features/ask/services/ask_service.dart';
import 'package:app/core/providers/vector_store_provider.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/core/providers/title_generation_provider.dart';

/// Provider for AskService
///
/// The main service for answering questions about journals using RAG.
/// Combines vector search with local LLM for on-device Q&A.
final askServiceProvider = Provider<AskService>((ref) {
  final vectorStore = ref.watch(vectorStoreProvider);
  final embeddingService = ref.watch(embeddingServiceProvider);
  final llmService = ref.watch(localLlmServiceProvider);

  return AskService(
    vectorStore: vectorStore,
    embeddingService: embeddingService,
    llmService: llmService,
  );
});

/// Provider that checks if Ask feature is ready to use
///
/// Returns true when both:
/// 1. Embedding model is ready (for semantic search)
/// 2. LLM service is available (for answer generation)
///
/// On desktop, Ollama must be running.
/// On mobile, Gemma model must be downloaded.
final askReadyProvider = FutureProvider<bool>((ref) async {
  // Check embedding model readiness
  final embeddingStatus = ref.watch(embeddingModelStatusProvider);
  if (!embeddingStatus.isReady) {
    return false;
  }

  // Check LLM readiness
  final askService = ref.watch(askServiceProvider);
  return await askService.isReady();
});

/// State provider for current Ask session messages
///
/// Holds the list of messages in the current Ask session.
/// Persists during the app session but starts fresh on app restart.
/// (Session persistence to ask-sessions/ folder will be added later)
final currentAskMessagesProvider = StateNotifierProvider<AskMessagesNotifier, List<AskMessage>>((ref) {
  return AskMessagesNotifier(ref);
});

/// Notifier for managing Ask session messages
class AskMessagesNotifier extends StateNotifier<List<AskMessage>> {
  final Ref _ref;

  AskMessagesNotifier(this._ref) : super([]);

  /// Add a user message and get AI response
  Future<void> askQuestion(String question) async {
    if (question.trim().isEmpty) return;

    // Add user message
    final userMessage = AskMessage.user(question);
    state = [...state, userMessage];

    try {
      // Get AI response
      final askService = _ref.read(askServiceProvider);
      final result = await askService.askQuestion(question);

      if (result != null) {
        // Add assistant message with sources
        final assistantMessage = AskMessage.assistant(result.answer, result.sources);
        state = [...state, assistantMessage];
      } else {
        // Handle no result
        final errorMessage = AskMessage.assistant(
          "I couldn't process your question. Please try again.",
          [],
        );
        state = [...state, errorMessage];
      }
    } catch (e) {
      // Handle error
      final errorMessage = AskMessage.assistant(
        _getErrorMessage(e),
        [],
      );
      state = [...state, errorMessage];
    }
  }

  /// Clear all messages (start new session)
  void clearSession() {
    state = [];
  }

  /// Get user-friendly error message
  String _getErrorMessage(Object error) {
    final errorString = error.toString();

    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      if (errorString.contains('Ollama')) {
        return "Ollama is not running. Please start Ollama to use the Ask feature.\n\n"
            "Install Ollama from https://ollama.ai and run 'ollama serve' in your terminal.";
      }
    } else {
      if (errorString.contains('Gemma') || errorString.contains('model')) {
        return "The AI model is not available. Please download the Gemma model in Settings → Local AI.";
      }
    }

    return "An error occurred: ${error.toString().split('\n').first}";
  }
}

/// Provider for checking if Ask is currently processing
final askIsLoadingProvider = StateProvider<bool>((ref) => false);

/// Provider for checking Ollama availability on desktop
///
/// Returns true if Ollama is available and running, false otherwise.
/// On mobile platforms, this always returns true (not needed).
final ollamaAvailableProvider = FutureProvider<bool>((ref) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return true; // Not needed on mobile
  }

  try {
    final ollamaService = ref.watch(ollamaCleanupServiceProvider);
    return await ollamaService.isAvailable();
  } catch (e) {
    return false;
  }
});
