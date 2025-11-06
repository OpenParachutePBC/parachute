import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/repositories/recording_repository.dart';
import 'package:app/features/recorder/services/audio_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/services/whisper_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/services/whisper_model_manager.dart';
import 'package:app/features/recorder/services/live_transcription_service_v2.dart';
import 'package:app/features/recorder/models/whisper_models.dart';

/// Provider for AudioService
///
/// This manages audio recording and playback functionality.
/// The service is initialized on first access and kept alive for the app lifetime.
final audioServiceProvider = Provider<AudioService>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  final service = AudioService(storageService);
  // Initialize the service when first accessed
  service.initialize();

  // Dispose when the provider is disposed
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider for StorageService
///
/// Local-first storage service for recording management.
/// All recordings are stored in ~/Parachute/captures/ as .wav, .md, and .json files.
/// Git sync handles multi-device synchronization.
final storageServiceProvider = Provider<StorageService>((ref) {
  final service = StorageService(ref);
  // Initialize the service when first accessed
  service.initialize();

  return service;
});

/// Provider for WhisperService
///
/// This manages transcription via OpenAI's Whisper API.
final whisperServiceProvider = Provider<WhisperService>((ref) {
  // WhisperService depends on StorageService for API key management
  final storageService = ref.watch(storageServiceProvider);
  return WhisperService(storageService);
});

/// Provider for RecordingRepository
///
/// This provides data access for recordings following the Repository Pattern.
/// It separates data access logic from business logic.
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return RecordingRepository(storageService);
});

/// Provider for WhisperModelManager
///
/// This manages Whisper model downloads and lifecycle.
final whisperModelManagerProvider = Provider<WhisperModelManager>((ref) {
  final manager = WhisperModelManager();

  ref.onDispose(() {
    manager.dispose();
  });

  return manager;
});

/// Provider for WhisperLocalService
///
/// This manages local on-device transcription using Whisper models.
final whisperLocalServiceProvider = Provider<WhisperLocalService>((ref) {
  final modelManager = ref.watch(whisperModelManagerProvider);
  final storageService = ref.watch(storageServiceProvider);

  final service = WhisperLocalService(modelManager, storageService);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider for transcription mode
///
/// Returns the current transcription mode (API or Local)
final transcriptionModeProvider = FutureProvider<TranscriptionMode>((
  ref,
) async {
  final storageService = ref.watch(storageServiceProvider);
  final modeString = await storageService.getTranscriptionMode();
  return TranscriptionMode.fromString(modeString) ?? TranscriptionMode.api;
});

/// Provider for auto-transcribe setting
///
/// Returns whether auto-transcribe is enabled
final autoTranscribeProvider = FutureProvider<bool>((ref) async {
  final storageService = ref.watch(storageServiceProvider);
  return await storageService.getAutoTranscribe();
});

/// Provider for triggering recordings list refresh
///
/// Increment this counter to trigger a refresh of the recordings list.
/// Used by Omi capture service to notify UI when new recordings are saved.
final recordingsRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Provider for SimpleTranscriptionService
///
/// This manages manual pause-based transcription with one continuous audio file.
/// Creates a new instance each time it's requested (not kept alive).
final simpleTranscriptionServiceProvider =
    Provider.autoDispose<SimpleTranscriptionService>((ref) {
      final whisperService = ref.watch(whisperLocalServiceProvider);
      final service = SimpleTranscriptionService(whisperService);

      ref.onDispose(() {
        service.dispose();
      });

      return service;
    });
