import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/title_generation_models.dart';
import 'package:app/core/services/title_generation_service.dart';
import 'package:app/core/services/gemma_model_manager.dart';
import 'package:app/core/services/transcript_cleanup_service.dart';
import 'package:app/core/services/ollama_cleanup_service.dart';
import 'package:app/core/services/local_llm_service.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

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
