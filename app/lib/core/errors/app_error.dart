/// Base class for all application errors
///
/// Provides structured error handling with error codes, user-friendly messages,
/// and optional underlying causes. Modeled after the parachute-agent error pattern.
abstract class AppError implements Exception {
  /// Machine-readable error code
  final String code;

  /// User-friendly error message
  final String message;

  /// Optional underlying error that caused this
  final Object? cause;

  /// Optional stack trace from the underlying error
  final StackTrace? stackTrace;

  const AppError({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() => '$runtimeType($code): $message';

  /// Convert to JSON for logging/debugging
  Map<String, dynamic> toJson() => {
        'type': runtimeType.toString(),
        'code': code,
        'message': message,
        if (cause != null) 'cause': cause.toString(),
      };
}

// ============================================================
// Storage & File System Errors
// ============================================================

/// Error related to file system operations
class StorageError extends AppError {
  final String? path;

  const StorageError({
    required super.code,
    required super.message,
    this.path,
    super.cause,
    super.stackTrace,
  });

  /// File not found
  factory StorageError.notFound(String path, [Object? cause]) => StorageError(
        code: 'STORAGE_NOT_FOUND',
        message: 'File not found: $path',
        path: path,
        cause: cause,
      );

  /// Permission denied
  factory StorageError.permissionDenied(String path, [Object? cause]) =>
      StorageError(
        code: 'STORAGE_PERMISSION_DENIED',
        message: 'Permission denied: $path',
        path: path,
        cause: cause,
      );

  /// Failed to read file
  factory StorageError.readFailed(String path, Object cause) => StorageError(
        code: 'STORAGE_READ_FAILED',
        message: 'Failed to read file: $path',
        path: path,
        cause: cause,
      );

  /// Failed to write file
  factory StorageError.writeFailed(String path, Object cause) => StorageError(
        code: 'STORAGE_WRITE_FAILED',
        message: 'Failed to write file: $path',
        path: path,
        cause: cause,
      );

  /// Invalid path (traversal attempt, etc.)
  factory StorageError.invalidPath(String path) => StorageError(
        code: 'STORAGE_INVALID_PATH',
        message: 'Invalid path: $path',
        path: path,
      );
}

// ============================================================
// Network & API Errors
// ============================================================

/// Error related to network/API operations
class NetworkError extends AppError {
  final int? statusCode;
  final String? url;

  const NetworkError({
    required super.code,
    required super.message,
    this.statusCode,
    this.url,
    super.cause,
    super.stackTrace,
  });

  /// No network connection
  factory NetworkError.noConnection([Object? cause]) => NetworkError(
        code: 'NETWORK_NO_CONNECTION',
        message: 'No network connection',
        cause: cause,
      );

  /// Request timeout
  factory NetworkError.timeout(String url, [Object? cause]) => NetworkError(
        code: 'NETWORK_TIMEOUT',
        message: 'Request timed out',
        url: url,
        cause: cause,
      );

  /// Server returned an error status
  factory NetworkError.serverError(int statusCode, String url, [String? body]) =>
      NetworkError(
        code: 'NETWORK_SERVER_ERROR',
        message: 'Server error: $statusCode',
        statusCode: statusCode,
        url: url,
        cause: body,
      );

  /// Server not reachable
  factory NetworkError.unreachable(String url, [Object? cause]) => NetworkError(
        code: 'NETWORK_UNREACHABLE',
        message: 'Server not reachable',
        url: url,
        cause: cause,
      );
}

// ============================================================
// Recording & Transcription Errors
// ============================================================

/// Error related to recording operations
class RecordingError extends AppError {
  final String? recordingId;

  const RecordingError({
    required super.code,
    required super.message,
    this.recordingId,
    super.cause,
    super.stackTrace,
  });

  /// Microphone permission denied
  factory RecordingError.microphonePermissionDenied() => const RecordingError(
        code: 'RECORDING_MIC_PERMISSION',
        message: 'Microphone permission denied',
      );

  /// Recording not found
  factory RecordingError.notFound(String id) => RecordingError(
        code: 'RECORDING_NOT_FOUND',
        message: 'Recording not found: $id',
        recordingId: id,
      );

  /// Failed to start recording
  factory RecordingError.startFailed(Object cause) => RecordingError(
        code: 'RECORDING_START_FAILED',
        message: 'Failed to start recording',
        cause: cause,
      );

  /// Failed to save recording
  factory RecordingError.saveFailed(Object cause) => RecordingError(
        code: 'RECORDING_SAVE_FAILED',
        message: 'Failed to save recording',
        cause: cause,
      );
}

/// Error related to transcription operations
class TranscriptionError extends AppError {
  const TranscriptionError({
    required super.code,
    required super.message,
    super.cause,
    super.stackTrace,
  });

  /// Model not downloaded
  factory TranscriptionError.modelNotDownloaded(String model) =>
      TranscriptionError(
        code: 'TRANSCRIPTION_MODEL_NOT_FOUND',
        message: 'Transcription model not downloaded: $model',
      );

  /// Model download failed
  factory TranscriptionError.downloadFailed(String model, Object cause) =>
      TranscriptionError(
        code: 'TRANSCRIPTION_DOWNLOAD_FAILED',
        message: 'Failed to download model: $model',
        cause: cause,
      );

  /// Transcription failed
  factory TranscriptionError.failed(Object cause) => TranscriptionError(
        code: 'TRANSCRIPTION_FAILED',
        message: 'Transcription failed',
        cause: cause,
      );
}

// ============================================================
// Chat & Agent Errors
// ============================================================

/// Error related to chat operations
class ChatError extends AppError {
  final String? sessionId;

  const ChatError({
    required super.code,
    required super.message,
    this.sessionId,
    super.cause,
    super.stackTrace,
  });

  /// Session not found
  factory ChatError.sessionNotFound(String id) => ChatError(
        code: 'CHAT_SESSION_NOT_FOUND',
        message: 'Chat session not found: $id',
        sessionId: id,
      );

  /// Stream error
  factory ChatError.streamError(Object cause) => ChatError(
        code: 'CHAT_STREAM_ERROR',
        message: 'Chat stream error',
        cause: cause,
      );

  /// Agent not found
  factory ChatError.agentNotFound(String path) => ChatError(
        code: 'CHAT_AGENT_NOT_FOUND',
        message: 'Agent not found: $path',
      );
}

// ============================================================
// Bluetooth & Device Errors
// ============================================================

/// Error related to Bluetooth/Omi device operations
class DeviceError extends AppError {
  final String? deviceId;

  const DeviceError({
    required super.code,
    required super.message,
    this.deviceId,
    super.cause,
    super.stackTrace,
  });

  /// Bluetooth not available
  factory DeviceError.bluetoothNotAvailable() => const DeviceError(
        code: 'DEVICE_BT_NOT_AVAILABLE',
        message: 'Bluetooth not available',
      );

  /// Bluetooth permission denied
  factory DeviceError.bluetoothPermissionDenied() => const DeviceError(
        code: 'DEVICE_BT_PERMISSION',
        message: 'Bluetooth permission denied',
      );

  /// Device not found
  factory DeviceError.notFound(String id) => DeviceError(
        code: 'DEVICE_NOT_FOUND',
        message: 'Device not found: $id',
        deviceId: id,
      );

  /// Connection failed
  factory DeviceError.connectionFailed(String id, Object cause) => DeviceError(
        code: 'DEVICE_CONNECTION_FAILED',
        message: 'Failed to connect to device',
        deviceId: id,
        cause: cause,
      );

  /// Firmware update failed
  factory DeviceError.firmwareUpdateFailed(Object cause) => DeviceError(
        code: 'DEVICE_FIRMWARE_FAILED',
        message: 'Firmware update failed',
        cause: cause,
      );
}

// ============================================================
// Validation Errors
// ============================================================

/// Error related to input validation
class ValidationError extends AppError {
  final String? field;

  const ValidationError({
    required super.code,
    required super.message,
    this.field,
    super.cause,
  });

  /// Required field missing
  factory ValidationError.required(String field) => ValidationError(
        code: 'VALIDATION_REQUIRED',
        message: '$field is required',
        field: field,
      );

  /// Invalid format
  factory ValidationError.invalidFormat(String field, String expected) =>
      ValidationError(
        code: 'VALIDATION_INVALID_FORMAT',
        message: '$field has invalid format. Expected: $expected',
        field: field,
      );

  /// Value out of range
  factory ValidationError.outOfRange(String field, num min, num max) =>
      ValidationError(
        code: 'VALIDATION_OUT_OF_RANGE',
        message: '$field must be between $min and $max',
        field: field,
      );
}
