import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app/services/parakeet_service.dart';
import 'package:app/services/sherpa_onnx_service.dart';

/// Platform-adaptive transcription service using Parakeet v3
///
/// Uses Parakeet via different implementations:
/// - iOS/macOS: FluidAudio (CoreML-based, Apple Neural Engine)
/// - Android: Sherpa-ONNX (ONNX Runtime-based)
///
/// This provides fast, offline transcription with 25-language support.
class TranscriptionServiceAdapter {
  final ParakeetService _parakeetService = ParakeetService();
  final SherpaOnnxService _sherpaService = SherpaOnnxService();

  // Progress tracking
  final _transcriptionProgressController =
      StreamController<TranscriptionProgress>.broadcast();

  Stream<TranscriptionProgress> get transcriptionProgressStream =>
      _transcriptionProgressController.stream;

  bool get isUsingParakeet =>
      _parakeetService.isSupported || _sherpaService.isSupported;

  String get engineName {
    if (_parakeetService.isSupported && _parakeetService.isInitialized) {
      return 'Parakeet v3 (FluidAudio)';
    } else if (_sherpaService.isInitialized) {
      return 'Parakeet v3 (Sherpa-ONNX)';
    } else {
      return 'Parakeet v3';
    }
  }

  /// Initialize the transcription service
  ///
  /// Platform-specific initialization:
  /// - iOS/macOS: Parakeet via FluidAudio (CoreML)
  /// - Android: Parakeet via Sherpa-ONNX
  Future<void> initialize() async {
    if (_parakeetService.isSupported) {
      // iOS/macOS: Initialize Parakeet via FluidAudio
      debugPrint(
        '[TranscriptionAdapter] Initializing Parakeet (FluidAudio)...',
      );
      try {
        await _parakeetService.initialize(version: 'v3');
        debugPrint('[TranscriptionAdapter] ✅ Parakeet (FluidAudio) ready');
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Parakeet init failed: $e');
        throw TranscriptionException(
          'Failed to initialize Parakeet: ${e.toString()}',
        );
      }
    } else {
      // Android/other: Initialize Parakeet via Sherpa-ONNX
      debugPrint(
        '[TranscriptionAdapter] Initializing Parakeet (Sherpa-ONNX)...',
      );
      try {
        await _sherpaService.initialize();
        debugPrint('[TranscriptionAdapter] ✅ Parakeet (Sherpa-ONNX) ready');
      } catch (e) {
        debugPrint('[TranscriptionAdapter] ⚠️ Sherpa-ONNX init failed: $e');
        throw TranscriptionException(
          'Failed to initialize Parakeet: ${e.toString()}',
        );
      }
    }
  }

  /// Transcribe audio file
  ///
  /// [audioPath] - Absolute path to audio file (WAV, 16kHz mono)
  /// [language] - Optional language hint (auto-detected by default)
  /// [onProgress] - Progress callback
  ///
  /// Returns transcribed text
  Future<String> transcribeAudio(
    String audioPath, {
    String? language,
    Function(TranscriptionProgress)? onProgress,
  }) async {
    // Lazy initialization - initialize on first use if not already done
    final needsInit =
        (_parakeetService.isSupported && !_parakeetService.isInitialized) ||
        (!_parakeetService.isSupported && !_sherpaService.isInitialized);

    if (needsInit) {
      debugPrint('[TranscriptionAdapter] Lazy-initializing...');
      await initialize();
    }

    // Try Parakeet (FluidAudio on iOS/macOS)
    if (_parakeetService.isSupported && _parakeetService.isInitialized) {
      return await _transcribeWithParakeet(audioPath, onProgress: onProgress);
    }

    // Try Parakeet (Sherpa-ONNX on Android)
    if (_sherpaService.isInitialized) {
      return await _transcribeWithSherpa(audioPath, onProgress: onProgress);
    }

    throw TranscriptionException('No transcription service available');
  }

  /// Transcribe using Parakeet via FluidAudio (iOS/macOS)
  Future<String> _transcribeWithParakeet(
    String audioPath, {
    Function(TranscriptionProgress)? onProgress,
  }) async {
    try {
      // Start progress
      _updateProgress(0.1, 'Transcribing with Parakeet...', onProgress);

      // Transcribe
      final result = await _parakeetService.transcribeAudio(audioPath);

      // Complete
      _updateProgress(
        1.0,
        'Transcription complete!',
        onProgress,
        isComplete: true,
      );

      debugPrint(
        '[TranscriptionAdapter] ✅ Parakeet (FluidAudio) transcribed in ${result.duration.inMilliseconds}ms',
      );

      return result.text;
    } on PlatformException catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.message}');
    } catch (e) {
      throw TranscriptionException('Parakeet failed: ${e.toString()}');
    }
  }

  /// Transcribe using Parakeet via Sherpa-ONNX (Android)
  Future<String> _transcribeWithSherpa(
    String audioPath, {
    Function(TranscriptionProgress)? onProgress,
  }) async {
    try {
      // Start progress
      _updateProgress(0.1, 'Transcribing with Parakeet...', onProgress);

      // Transcribe
      final result = await _sherpaService.transcribeAudio(audioPath);

      // Complete
      _updateProgress(
        1.0,
        'Transcription complete!',
        onProgress,
        isComplete: true,
      );

      debugPrint(
        '[TranscriptionAdapter] ✅ Parakeet (Sherpa-ONNX) transcribed in ${result.duration.inMilliseconds}ms',
      );

      return result.text;
    } catch (e) {
      throw TranscriptionException(
        'Parakeet (Sherpa-ONNX) failed: ${e.toString()}',
      );
    }
  }

  /// Update and broadcast progress
  void _updateProgress(
    double progress,
    String status,
    Function(TranscriptionProgress)? onProgress, {
    bool isComplete = false,
  }) {
    final progressData = TranscriptionProgress(
      progress: progress.clamp(0.0, 1.0),
      status: status,
      isComplete: isComplete,
    );

    _transcriptionProgressController.add(progressData);
    onProgress?.call(progressData);
  }

  /// Check if transcription service is ready
  Future<bool> isReady() async {
    // Check FluidAudio (iOS/macOS)
    if (_parakeetService.isSupported) {
      return await _parakeetService.isReady();
    }

    // Check Sherpa-ONNX (Android)
    return await _sherpaService.isReady();
  }

  void dispose() {
    _transcriptionProgressController.close();
  }
}

/// Transcription progress data
class TranscriptionProgress {
  final double progress;
  final String status;
  final bool isComplete;

  TranscriptionProgress({
    required this.progress,
    required this.status,
    this.isComplete = false,
  });
}

/// Generic transcription exception
class TranscriptionException implements Exception {
  final String message;

  TranscriptionException(this.message);

  @override
  String toString() => message;
}
