import 'package:flutter/foundation.dart';

/// Centralized application configuration
///
/// Contains all configurable values with sensible defaults.
/// Values can be overridden via environment or at runtime.
///
/// Modeled after the parachute-agent CONFIG pattern for consistency.
class AppConfig {
  // ============================================================
  // Backend / API Configuration
  // ============================================================

  /// Default agent server URL
  static const String defaultAgentServerUrl = 'http://localhost:3333';

  /// Health check endpoint path
  static const String healthEndpoint = '/api/health';

  /// API request timeout
  static const Duration apiTimeout = Duration(seconds: 30);

  /// SSE stream timeout (longer for streaming responses)
  static const Duration streamTimeout = Duration(minutes: 10);

  // ============================================================
  // Storage Configuration
  // ============================================================

  /// Default vault folder name
  static const String defaultVaultName = 'Parachute';

  /// Default captures subfolder name
  static const String defaultCapturesFolder = 'captures';

  /// Default spheres subfolder name
  static const String defaultSpheresFolder = 'spheres';

  /// Recording cache duration
  static const Duration recordingCacheDuration = Duration(seconds: 30);

  // ============================================================
  // Recording Configuration
  // ============================================================

  /// Default audio sample rate (Hz)
  static const int audioSampleRate = 16000;

  /// Audio channels (1 = mono, 2 = stereo)
  static const int audioChannels = 1;

  /// VAD silence threshold for auto-pause (seconds)
  static const double vadSilenceThreshold = 1.0;

  /// High-pass filter cutoff frequency (Hz)
  static const double highPassFilterCutoff = 80.0;

  /// Minimum recording duration to save (milliseconds)
  static const int minRecordingDurationMs = 500;

  // ============================================================
  // Transcription Configuration
  // ============================================================

  /// Default transcription model
  static const String defaultTranscriptionModel = 'parakeet-tdt-0.6b-v2';

  /// Maximum transcript preview length (characters)
  static const int transcriptPreviewLength = 500;

  // ============================================================
  // Chat Configuration
  // ============================================================

  /// Maximum message length (characters)
  static const int maxMessageLength = 102400; // 100KB

  /// Session cache TTL
  static const Duration sessionCacheTtl = Duration(minutes: 30);

  /// Search debounce delay
  static const Duration searchDebounceDelay = Duration(milliseconds: 300);

  // ============================================================
  // UI Configuration
  // ============================================================

  /// Default animation duration
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);

  /// Snackbar display duration
  static const Duration snackbarDuration = Duration(seconds: 3);

  /// Pull-to-refresh trigger distance
  static const double pullToRefreshTrigger = 100.0;

  // ============================================================
  // Performance Configuration
  // ============================================================

  /// Parallel file I/O batch size
  static const int fileIoBatchSize = 20;

  /// Maximum log buffer entries
  static const int maxLogBufferSize = 1000;

  /// Maximum recordings to load at once (0 = unlimited)
  static const int maxRecordingsToLoad = 0;

  // ============================================================
  // Debug Configuration
  // ============================================================

  /// Enable verbose logging in debug mode
  static bool verboseLogging = kDebugMode;

  /// Show debug UI elements
  static bool showDebugUI = kDebugMode;

  /// Print API requests/responses
  static bool logApiCalls = kDebugMode;

  // ============================================================
  // Feature Flags (can be toggled at runtime)
  // ============================================================

  /// Enable AI chat feature
  static bool enableAiChat = true;

  /// Enable Omi device support
  static bool enableOmiDevice = true;

  /// Enable Git sync
  static bool enableGitSync = true;

  /// Enable search indexing
  static bool enableSearchIndexing = true;

  /// Enable background transcription
  static bool enableBackgroundTranscription = true;

  // ============================================================
  // Helper Methods
  // ============================================================

  /// Get all configuration as a map (useful for debugging)
  static Map<String, dynamic> toMap() => {
        'backend': {
          'defaultAgentServerUrl': defaultAgentServerUrl,
          'healthEndpoint': healthEndpoint,
          'apiTimeoutMs': apiTimeout.inMilliseconds,
          'streamTimeoutMs': streamTimeout.inMilliseconds,
        },
        'storage': {
          'defaultVaultName': defaultVaultName,
          'defaultCapturesFolder': defaultCapturesFolder,
          'defaultSpheresFolder': defaultSpheresFolder,
          'recordingCacheDurationSec': recordingCacheDuration.inSeconds,
        },
        'recording': {
          'audioSampleRate': audioSampleRate,
          'audioChannels': audioChannels,
          'vadSilenceThreshold': vadSilenceThreshold,
          'highPassFilterCutoff': highPassFilterCutoff,
          'minRecordingDurationMs': minRecordingDurationMs,
        },
        'transcription': {
          'defaultModel': defaultTranscriptionModel,
          'transcriptPreviewLength': transcriptPreviewLength,
        },
        'chat': {
          'maxMessageLength': maxMessageLength,
          'sessionCacheTtlMin': sessionCacheTtl.inMinutes,
          'searchDebounceDelayMs': searchDebounceDelay.inMilliseconds,
        },
        'performance': {
          'fileIoBatchSize': fileIoBatchSize,
          'maxLogBufferSize': maxLogBufferSize,
          'maxRecordingsToLoad': maxRecordingsToLoad,
        },
        'debug': {
          'verboseLogging': verboseLogging,
          'showDebugUI': showDebugUI,
          'logApiCalls': logApiCalls,
        },
        'features': {
          'enableAiChat': enableAiChat,
          'enableOmiDevice': enableOmiDevice,
          'enableGitSync': enableGitSync,
          'enableSearchIndexing': enableSearchIndexing,
          'enableBackgroundTranscription': enableBackgroundTranscription,
        },
      };
}
