import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/repositories/recording_repository.dart';
import 'package:app/features/recorder/services/audio_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/services/transcription_service_adapter.dart';
import 'package:app/features/recorder/services/live_transcription_service_v3.dart';
import 'package:app/features/recorder/services/background_transcription_service.dart';
import 'package:app/features/recorder/services/recording_post_processing_service.dart';

/// Provider for AudioService
///
/// This manages audio recording and playback functionality.
/// The service is initialized on first access and kept alive for the app lifetime.
///
/// IMPORTANT: The service initializes asynchronously. Callers should use
/// `await audioService.ensureInitialized()` before using the service if they
/// need to guarantee initialization is complete.
final audioServiceProvider = Provider<AudioService>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  final service = AudioService(storageService);
  // Initialize the service when first accessed
  // Note: This is async but we don't await - callers should use ensureInitialized() if needed
  service.initialize().catchError((e) {
    debugPrint('[AudioServiceProvider] Initialization error: $e');
  });

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
///
/// IMPORTANT: The service initializes asynchronously. Callers should use
/// `await storageService.ensureInitialized()` before using the service if they
/// need to guarantee initialization is complete.
final storageServiceProvider = Provider<StorageService>((ref) {
  final service = StorageService(ref);
  // Initialize the service when first accessed
  // Note: This is async but we don't await - callers should use ensureInitialized() if needed
  service.initialize().catchError((e) {
    debugPrint('[StorageServiceProvider] Initialization error: $e');
  });

  return service;
});

/// Provider for RecordingRepository
///
/// This provides data access for recordings following the Repository Pattern.
/// It separates data access logic from business logic.
final recordingRepositoryProvider = Provider<RecordingRepository>((ref) {
  final storageService = ref.watch(storageServiceProvider);
  return RecordingRepository(storageService);
});

/// Provider for TranscriptionServiceAdapter
///
/// Platform-adaptive transcription using Parakeet v3:
/// - iOS/macOS: FluidAudio (CoreML + Apple Neural Engine)
/// - Android: Sherpa-ONNX (ONNX Runtime)
final transcriptionServiceAdapterProvider =
    Provider<TranscriptionServiceAdapter>((ref) {
      final service = TranscriptionServiceAdapter();

      ref.onDispose(() {
        service.dispose();
      });

      return service;
    });

/// Provider for RecordingPostProcessingService
///
/// Pipeline for processing recordings:
/// - Transcription (Parakeet v3 via FluidAudio or Sherpa-ONNX)
final recordingPostProcessingProvider =
    Provider<RecordingPostProcessingService>((ref) {
      final transcriptionService = ref.watch(
        transcriptionServiceAdapterProvider,
      );

      return RecordingPostProcessingService(
        transcriptionService: transcriptionService,
      );
    });

/// Provider for triggering recordings list refresh
///
/// Increment this counter to trigger a refresh of the recordings list.
/// Used by Omi capture service to notify UI when new recordings are saved.
final recordingsRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// State notifier for managing active recording session
///
/// This holds the current recording state and transcription service,
/// allowing it to persist across navigation (recording screen → detail screen).
class ActiveRecordingState {
  final AutoPauseTranscriptionService? service;
  final String? audioFilePath;
  final DateTime? startTime;
  final bool isTranscribing;

  ActiveRecordingState({
    this.service,
    this.audioFilePath,
    this.startTime,
    this.isTranscribing = false,
  });

  ActiveRecordingState copyWith({
    AutoPauseTranscriptionService? service,
    String? audioFilePath,
    DateTime? startTime,
    bool? isTranscribing,
  }) {
    return ActiveRecordingState(
      service: service ?? this.service,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      startTime: startTime ?? this.startTime,
      isTranscribing: isTranscribing ?? this.isTranscribing,
    );
  }
}

class ActiveRecordingNotifier extends StateNotifier<ActiveRecordingState> {
  ActiveRecordingNotifier() : super(ActiveRecordingState());

  /// Start a new recording session
  void startSession(AutoPauseTranscriptionService service, DateTime startTime) {
    state = ActiveRecordingState(
      service: service,
      startTime: startTime,
      isTranscribing: false,
    );
  }

  /// Stop recording and get audio file path
  Future<String?> stopRecording() async {
    if (state.service == null) return null;

    final audioPath = await state.service!.stopRecording();
    state = state.copyWith(audioFilePath: audioPath, isTranscribing: true);

    return audioPath;
  }

  /// Mark transcription as complete
  void completeTranscription() {
    state = state.copyWith(isTranscribing: false);
  }

  /// Clear the session (called after save is complete)
  void clearSession() {
    final oldService = state.service;
    state = ActiveRecordingState();

    // Dispose old service
    oldService?.dispose();
  }
}

/// Provider for active recording session
///
/// This keeps the transcription service alive across navigation,
/// allowing recording → detail screen transition while transcription continues.
final activeRecordingProvider =
    StateNotifierProvider<ActiveRecordingNotifier, ActiveRecordingState>((ref) {
      return ActiveRecordingNotifier();
    });

/// Provider for background transcription service
///
/// This keeps transcription running even when screens are disposed,
/// automatically saving results when transcription completes.
///
/// IMPORTANT: Uses keepAlive to prevent disposal when screens navigate away.
/// This ensures background transcription continues and completes even when
/// the UI is not actively watching the provider.
final backgroundTranscriptionProvider =
    Provider<BackgroundTranscriptionService>((ref) {
      final service = BackgroundTranscriptionService();

      // Keep this provider alive even when no widgets are listening
      // This is critical for background transcription to complete
      ref.keepAlive();

      // Set callback to trigger UI refresh when file is saved
      // This updates the recordings list even when user navigates away
      service.onFileSaved = () {
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      };

      return service;
    });
