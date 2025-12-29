import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/models/title_generation_models.dart';
import 'package:parachute_chat/core/services/title_generation_service.dart';
import 'package:parachute_chat/core/services/gemma_model_manager.dart';
import 'package:parachute_chat/core/services/transcript_cleanup_service.dart';
import 'package:parachute_chat/core/services/ollama_cleanup_service.dart';
import 'package:parachute_chat/core/services/local_llm_service.dart';
import 'package:parachute_chat/core/services/enhancement_service.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import 'package:parachute_chat/features/recorder/providers/service_providers.dart';

/// Provider for the Gemma model manager
final gemmaModelManagerProvider = Provider<GemmaModelManager>((ref) {
  return GemmaModelManager();
});

/// Provider for the Ollama cleanup service
final ollamaCleanupServiceProvider = Provider<OllamaCleanupService>((ref) {
  return OllamaCleanupService();
});

/// Provider for the unified local LLM service
final localLlmServiceProvider = Provider<LocalLlmService>((ref) {
  final gemmaManager = ref.watch(gemmaModelManagerProvider);
  final ollamaService = ref.watch(ollamaCleanupServiceProvider);

  return LocalLlmService(
    gemmaManager,
    ollamaService,
    // Get preferred Gemma model (mobile)
    () async {
      final storageService = ref.read(storageServiceProvider);
      final modelString = await storageService.getPreferredGemmaModel();
      if (modelString == null) return null;
      return GemmaModelType.fromString(modelString);
    },
    // Get preferred Ollama model (desktop)
    () async {
      final storageService = ref.read(storageServiceProvider);
      return await storageService.getOllamaModel();
    },
  );
});

/// Provider for the transcript cleanup service
final transcriptCleanupServiceProvider = Provider<TranscriptCleanupService>((
  ref,
) {
  final gemmaManager = ref.watch(gemmaModelManagerProvider);
  final ollamaService = ref.watch(ollamaCleanupServiceProvider);

  return TranscriptCleanupService(
    gemmaManager,
    ollamaService,
    // Get preferred Gemma model (mobile)
    () async {
      final storageService = ref.read(storageServiceProvider);
      final modelString = await storageService.getPreferredGemmaModel();
      if (modelString == null) return null;
      return GemmaModelType.fromString(modelString);
    },
    // Get preferred Ollama model (desktop)
    () async {
      final storageService = ref.read(storageServiceProvider);
      return await storageService.getOllamaModel();
    },
  );
});

/// Provider for the title generation service
final titleGenerationServiceProvider = Provider<TitleGenerationService>((ref) {
  final gemmaManager = ref.watch(gemmaModelManagerProvider);

  // Create service with all required dependencies
  final service = TitleGenerationService(
    // Get Gemini API key
    () async {
      final storageService = ref.read(storageServiceProvider);
      return await storageService.getGeminiApiKey();
    },
    // Get title generation mode
    () async {
      final storageService = ref.read(storageServiceProvider);
      final modeString = await storageService.getTitleGenerationMode();
      return TitleModelMode.fromString(modeString) ?? TitleModelMode.api;
    },
    // Get preferred Gemma model
    () async {
      final storageService = ref.read(storageServiceProvider);
      final modelString = await storageService.getPreferredGemmaModel();
      if (modelString == null) return null;
      return GemmaModelType.fromString(modelString);
    },
    gemmaManager,
  );

  ref.onDispose(() async {
    await service.dispose();
  });

  return service;
});

/// Provider for the enhancement service (remote/local AI enhancement)
final enhancementServiceProvider = Provider<EnhancementService>((ref) {
  final localLlmService = ref.watch(localLlmServiceProvider);
  final storageService = ref.watch(storageServiceProvider);

  // Create a synchronous getter for the server URL
  // The service will call this when needed
  String getServerUrl() {
    // This is a bit of a hack - we need synchronous access but aiServerUrlProvider is async
    // We'll cache the last known URL
    return _cachedServerUrl ?? 'http://localhost:3333';
  }

  // Watch the server URL and update cache
  ref.listen(aiServerUrlProvider, (previous, next) {
    next.whenData((url) {
      _cachedServerUrl = url;
    });
  });

  // Initial fetch of server URL
  ref.read(aiServerUrlProvider.future).then((url) {
    _cachedServerUrl = url;
  });

  final service = EnhancementService(
    localLlmService: localLlmService,
    storageService: storageService,
    getAgentServerUrl: getServerUrl,
  );

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

// Cache for server URL (module-level for simplicity)
String? _cachedServerUrl;
