import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Progress state for active transcription
class TranscriptionProgressState {
  final bool isActive;
  final double progress; // 0.0 to 1.0
  final String status;
  final Duration? audioDuration;
  final Duration? estimatedTimeRemaining;
  final DateTime? startedAt;

  const TranscriptionProgressState({
    this.isActive = false,
    this.progress = 0.0,
    this.status = '',
    this.audioDuration,
    this.estimatedTimeRemaining,
    this.startedAt,
  });

  TranscriptionProgressState copyWith({
    bool? isActive,
    double? progress,
    String? status,
    Duration? audioDuration,
    Duration? estimatedTimeRemaining,
    DateTime? startedAt,
  }) {
    return TranscriptionProgressState(
      isActive: isActive ?? this.isActive,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      audioDuration: audioDuration ?? this.audioDuration,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  /// Get formatted time remaining string
  String get timeRemainingText {
    if (estimatedTimeRemaining == null) return '';
    final seconds = estimatedTimeRemaining!.inSeconds;
    if (seconds < 2) return 'Almost done...';
    if (seconds < 60) return '~${seconds}s remaining';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '~${minutes}m ${secs}s remaining';
  }

  /// Get formatted progress percentage
  String get progressText => '${(progress * 100).toInt()}%';
}

/// Notifier for transcription progress
class TranscriptionProgressNotifier extends StateNotifier<TranscriptionProgressState> {
  Timer? _progressTimer;

  // Transcription speed: audio duration / processing time
  // Parakeet typically processes at ~10-15x real-time on modern devices
  static const double _estimatedSpeedRatio = 12.0;

  TranscriptionProgressNotifier() : super(const TranscriptionProgressState());

  /// Start tracking transcription progress
  void startTranscription({required int audioDurationSeconds}) {
    final audioDuration = Duration(seconds: audioDurationSeconds);
    final estimatedProcessingTime = Duration(
      milliseconds: (audioDurationSeconds * 1000 / _estimatedSpeedRatio).round(),
    );

    state = TranscriptionProgressState(
      isActive: true,
      progress: 0.05,
      status: 'Transcribing...',
      audioDuration: audioDuration,
      estimatedTimeRemaining: estimatedProcessingTime,
      startedAt: DateTime.now(),
    );

    // Start progress simulation timer
    _startProgressTimer(estimatedProcessingTime);
  }

  void _startProgressTimer(Duration estimatedTotal) {
    _progressTimer?.cancel();

    const updateInterval = Duration(milliseconds: 200);
    final totalMs = estimatedTotal.inMilliseconds;

    _progressTimer = Timer.periodic(updateInterval, (timer) {
      if (!state.isActive) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(state.startedAt!);
      final elapsedMs = elapsed.inMilliseconds;

      // Calculate estimated progress (cap at 95% until actually complete)
      var estimatedProgress = (elapsedMs / totalMs).clamp(0.0, 0.95);

      // Calculate remaining time
      final remainingMs = (totalMs - elapsedMs).clamp(0, totalMs * 2);
      final remaining = Duration(milliseconds: remainingMs.round());

      state = state.copyWith(
        progress: estimatedProgress,
        estimatedTimeRemaining: remaining,
        status: _getStatusForProgress(estimatedProgress),
      );
    });
  }

  String _getStatusForProgress(double progress) {
    if (progress < 0.3) return 'Transcribing...';
    if (progress < 0.6) return 'Processing audio...';
    if (progress < 0.9) return 'Finalizing...';
    return 'Almost done...';
  }

  /// Mark transcription as complete
  void complete() {
    _progressTimer?.cancel();
    state = state.copyWith(
      isActive: false,
      progress: 1.0,
      status: 'Complete!',
      estimatedTimeRemaining: Duration.zero,
    );

    // Clear state after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!state.isActive) {
        state = const TranscriptionProgressState();
      }
    });
  }

  /// Mark transcription as failed
  void fail(String error) {
    _progressTimer?.cancel();
    state = state.copyWith(
      isActive: false,
      status: 'Failed: $error',
    );
  }

  /// Cancel tracking
  void cancel() {
    _progressTimer?.cancel();
    state = const TranscriptionProgressState();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }
}

/// Provider for transcription progress
final transcriptionProgressProvider = StateNotifierProvider<
    TranscriptionProgressNotifier, TranscriptionProgressState>((ref) {
  return TranscriptionProgressNotifier();
});
