import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Log levels for categorizing messages
enum LogLevel { debug, info, warning, error }

/// A single log entry with timestamp and metadata
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  String get formatted {
    final levelStr = level.name.toUpperCase().padRight(5);
    final timeStr = timestamp.toIso8601String().substring(
      11,
      23,
    ); // HH:mm:ss.SSS
    final errorStr = error != null ? '\n  Error: $error' : '';
    final stackStr = stackTrace != null ? '\n  Stack: $stackTrace' : '';
    return '[$timeStr] $levelStr [$tag] $message$errorStr$stackStr';
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    if (error != null) 'error': error.toString(),
  };
}

/// Centralized logging service with:
/// - Rolling in-memory buffer (last 500 entries)
/// - Sentry breadcrumbs integration
/// - Local file fallback (flushed periodically)
/// - User opt-out support
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  /// Maximum entries to keep in memory
  static const int maxBufferSize = 500;

  /// How often to flush logs to file (in debug/file mode)
  static const Duration flushInterval = Duration(minutes: 5);

  /// Maximum log file size before rotation (1MB)
  static const int maxLogFileSize = 1024 * 1024;

  /// Number of old log files to keep
  static const int maxLogFiles = 5;

  /// In-memory log buffer (circular)
  final Queue<LogEntry> _buffer = Queue<LogEntry>();

  /// Whether Sentry is initialized
  bool _sentryInitialized = false;

  /// Whether user has opted out of crash reporting
  bool _crashReportingEnabled = true;

  /// File for local logging
  File? _logFile;

  /// Timer for periodic file flush
  Timer? _flushTimer;

  /// Pending logs to write to file
  final List<LogEntry> _pendingFileWrites = [];

  /// Settings key for crash reporting opt-out
  static const String _crashReportingKey = 'crash_reporting_enabled';

  /// Initialize the logging service
  Future<void> initialize({
    required String? sentryDsn,
    String? environment,
    String? release,
  }) async {
    // Load user preference for crash reporting
    final prefs = await SharedPreferences.getInstance();
    _crashReportingEnabled = prefs.getBool(_crashReportingKey) ?? true;

    // Initialize local file logging
    await _initializeFileLogging();

    // Start periodic flush timer
    _flushTimer = Timer.periodic(flushInterval, (_) => flushToFile());

    // Initialize Sentry if DSN provided and user hasn't opted out
    if (sentryDsn != null && sentryDsn.isNotEmpty && _crashReportingEnabled) {
      await _initializeSentry(
        dsn: sentryDsn,
        environment: environment,
        release: release,
      );
    } else if (!_crashReportingEnabled) {
      debugPrint('[LoggingService] Crash reporting disabled by user');
    } else {
      debugPrint(
        '[LoggingService] No Sentry DSN configured, using file logging only',
      );
    }

    info('LoggingService', 'Logging service initialized');
  }

  Future<void> _initializeSentry({
    required String dsn,
    String? environment,
    String? release,
  }) async {
    try {
      await SentryFlutter.init((options) {
        options.dsn = dsn;
        options.environment =
            environment ?? (kReleaseMode ? 'production' : 'development');
        options.release = release;

        // beforeSend can be used for filtering if needed
        // Events are sent as-is with breadcrumbs attached automatically

        // Performance monitoring (optional, can be disabled)
        options.tracesSampleRate = kReleaseMode ? 0.1 : 0.0;

        // Attach screenshots on crash (helpful for UI issues)
        options.attachScreenshot = true;

        // Capture failed HTTP requests
        options.captureFailedRequests = true;

        // Maximum breadcrumbs to keep
        options.maxBreadcrumbs = 100;
      });

      _sentryInitialized = true;
      debugPrint('[LoggingService] Sentry initialized successfully');
    } catch (e) {
      debugPrint('[LoggingService] Failed to initialize Sentry: $e');
      // Continue with file-only logging
    }
  }

  Future<void> _initializeFileLogging() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory('${directory.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      final today = DateTime.now().toIso8601String().substring(0, 10);
      _logFile = File('${logsDir.path}/parachute_$today.log');

      // Rotate old logs if needed
      await _rotateLogsIfNeeded(logsDir);

      debugPrint(
        '[LoggingService] File logging initialized: ${_logFile!.path}',
      );
    } catch (e) {
      debugPrint('[LoggingService] Failed to initialize file logging: $e');
    }
  }

  Future<void> _rotateLogsIfNeeded(Directory logsDir) async {
    try {
      final logFiles = await logsDir
          .list()
          .where((f) => f is File && f.path.endsWith('.log'))
          .cast<File>()
          .toList();

      // Sort by modification time (newest first)
      logFiles.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      // Delete old files beyond the limit
      if (logFiles.length > maxLogFiles) {
        for (var i = maxLogFiles; i < logFiles.length; i++) {
          await logFiles[i].delete();
          debugPrint(
            '[LoggingService] Deleted old log file: ${logFiles[i].path}',
          );
        }
      }

      // Check if current log file is too large
      if (_logFile != null && await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > maxLogFileSize) {
          // Rename current file with timestamp
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final newPath = _logFile!.path.replaceAll('.log', '_$timestamp.log');
          await _logFile!.rename(newPath);
          _logFile = File(_logFile!.path); // Create new file
        }
      }
    } catch (e) {
      debugPrint('[LoggingService] Error rotating logs: $e');
    }
  }

  /// Log a message at the specified level
  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to in-memory buffer
    _buffer.add(entry);
    while (_buffer.length > maxBufferSize) {
      _buffer.removeFirst();
    }

    // Add to pending file writes
    _pendingFileWrites.add(entry);

    // Print to console in debug mode
    if (!kReleaseMode) {
      debugPrint(entry.formatted);
    }

    // Add as Sentry breadcrumb
    if (_sentryInitialized && _crashReportingEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: '[$tag] $message',
          level: _toSentryLevel(level),
          category: tag,
          timestamp: entry.timestamp,
          data: error != null ? {'error': error.toString()} : null,
        ),
      );
    }
  }

  SentryLevel _toSentryLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return SentryLevel.debug;
      case LogLevel.info:
        return SentryLevel.info;
      case LogLevel.warning:
        return SentryLevel.warning;
      case LogLevel.error:
        return SentryLevel.error;
    }
  }

  /// Convenience methods for each log level
  void debug(String tag, String message) => log(LogLevel.debug, tag, message);
  void info(String tag, String message) => log(LogLevel.info, tag, message);
  void warning(String tag, String message, {Object? error}) =>
      log(LogLevel.warning, tag, message, error: error);
  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);

  /// Capture an exception and send to Sentry
  Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? tag,
    Map<String, dynamic>? extras,
  }) async {
    // Log locally
    error(
      tag ?? 'Exception',
      exception.toString(),
      error: exception,
      stackTrace: stackTrace,
    );

    // Send to Sentry if enabled
    if (_sentryInitialized && _crashReportingEnabled) {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) {
          if (tag != null) scope.setTag('source', tag);
          if (extras != null) {
            extras.forEach((key, value) => scope.setContexts(key, value));
          }
          // Attach recent logs
          scope.setContexts(
            'recent_logs',
            {'logs': _buffer.take(50).map((e) => e.formatted).toList()},
          );
        },
      );
    }
  }

  /// Flush pending logs to file
  Future<void> flushToFile() async {
    if (_pendingFileWrites.isEmpty || _logFile == null) return;

    try {
      final entries = List<LogEntry>.from(_pendingFileWrites);
      _pendingFileWrites.clear();

      final content = '${entries.map((e) => e.formatted).join('\n')}\n';
      await _logFile!.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      debugPrint('[LoggingService] Failed to flush logs to file: $e');
    }
  }

  /// Get recent logs (for debugging UI or crash reports)
  List<LogEntry> getRecentLogs({int count = 100}) {
    return _buffer.toList().reversed.take(count).toList();
  }

  /// Get path to current log file
  String? get logFilePath => _logFile?.path;

  /// Get all log file paths
  Future<List<String>> getLogFilePaths() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final logsDir = Directory('${directory.path}/logs');
      if (!await logsDir.exists()) return [];

      final files = await logsDir
          .list()
          .where((f) => f is File && f.path.endsWith('.log'))
          .map((f) => f.path)
          .toList();

      files.sort((a, b) => b.compareTo(a)); // Newest first
      return files;
    } catch (e) {
      return [];
    }
  }

  /// Check if crash reporting is enabled
  bool get isCrashReportingEnabled => _crashReportingEnabled;

  /// Enable or disable crash reporting
  Future<void> setCrashReportingEnabled(bool enabled) async {
    _crashReportingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_crashReportingKey, enabled);

    if (!enabled && _sentryInitialized) {
      // Close Sentry connection
      await Sentry.close();
      _sentryInitialized = false;
      info('LoggingService', 'Crash reporting disabled');
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await flushToFile();
    if (_sentryInitialized) {
      await Sentry.close();
    }
  }
}

/// Global logging instance for convenience
final logger = LoggingService();
