import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Log level enumeration
enum LogLevel {
  debug(0, 'DEBUG'),
  info(1, 'INFO'),
  warn(2, 'WARN'),
  error(3, 'ERROR');

  final int value;
  final String name;

  const LogLevel(this.value, this.name);
}

/// A single log entry
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String component;
  final String message;
  final Map<String, dynamic>? data;
  final Object? error;
  final StackTrace? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.component,
    required this.message,
    this.data,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'iso': timestamp.toIso8601String(),
        'level': level.value,
        'levelName': level.name,
        'component': component,
        'message': message,
        if (data != null) 'data': data,
        if (error != null) 'error': error.toString(),
      };

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}] ');
    buffer.write('[${level.name}] ');
    buffer.write('[$component] ');
    buffer.write(message);
    if (data != null) {
      buffer.write(' $data');
    }
    if (error != null) {
      buffer.write(' Error: $error');
    }
    return buffer.toString();
  }
}

/// Structured logging service with in-memory buffer
///
/// Provides leveled logging with component tags and an in-memory circular
/// buffer for debugging. Modeled after the parachute-agent logger pattern.
///
/// Usage:
/// ```dart
/// final logger = LoggerService.instance;
/// final log = logger.createLogger('MyComponent');
///
/// log.debug('Processing started', data: {'itemCount': 42});
/// log.info('Operation complete');
/// log.warn('Resource running low');
/// log.error('Failed to save', error: e, stackTrace: st);
/// ```
class LoggerService {
  static final LoggerService instance = LoggerService._();

  /// Maximum entries to keep in memory
  static const int maxBufferSize = 1000;

  /// Minimum log level to record (can be changed at runtime)
  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// In-memory circular buffer of recent logs
  final Queue<LogEntry> _buffer = Queue<LogEntry>();

  /// Whether to also print to debug console
  bool printToConsole = kDebugMode;

  LoggerService._();

  /// Create a component-specific logger
  ComponentLogger createLogger(String component) {
    return ComponentLogger._(this, component);
  }

  /// Log a message
  void log(
    LogLevel level,
    String component,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.value < minLevel.value) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      component: component,
      message: message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to buffer (circular)
    _buffer.add(entry);
    while (_buffer.length > maxBufferSize) {
      _buffer.removeFirst();
    }

    // Print to console in debug mode
    if (printToConsole) {
      debugPrint(entry.toString());
      if (stackTrace != null && level == LogLevel.error) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  /// Get recent log entries
  ///
  /// [level] - Minimum level to include (null = all)
  /// [component] - Filter by component (null = all)
  /// [since] - Only entries after this time (null = all)
  /// [limit] - Maximum entries to return (default 100)
  List<LogEntry> getLogs({
    LogLevel? level,
    String? component,
    DateTime? since,
    int limit = 100,
  }) {
    var entries = _buffer.toList();

    if (level != null) {
      entries = entries.where((e) => e.level.value >= level.value).toList();
    }
    if (component != null) {
      entries = entries.where((e) => e.component == component).toList();
    }
    if (since != null) {
      entries = entries.where((e) => e.timestamp.isAfter(since)).toList();
    }

    // Return most recent entries
    if (entries.length > limit) {
      entries = entries.sublist(entries.length - limit);
    }

    return entries;
  }

  /// Get log statistics
  Map<String, dynamic> getStats() {
    final byLevel = <String, int>{};
    final byComponent = <String, int>{};

    for (final entry in _buffer) {
      byLevel[entry.level.name] = (byLevel[entry.level.name] ?? 0) + 1;
      byComponent[entry.component] =
          (byComponent[entry.component] ?? 0) + 1;
    }

    return {
      'totalEntries': _buffer.length,
      'maxBufferSize': maxBufferSize,
      'byLevel': byLevel,
      'byComponent': byComponent,
      'oldestEntry': _buffer.isNotEmpty
          ? _buffer.first.timestamp.toIso8601String()
          : null,
      'newestEntry': _buffer.isNotEmpty
          ? _buffer.last.timestamp.toIso8601String()
          : null,
    };
  }

  /// Clear all log entries
  void clear() {
    _buffer.clear();
  }
}

/// Component-specific logger for convenient logging
class ComponentLogger {
  final LoggerService _service;
  final String component;

  ComponentLogger._(this._service, this.component);

  void debug(String message, {Map<String, dynamic>? data}) {
    _service.log(LogLevel.debug, component, message, data: data);
  }

  void info(String message, {Map<String, dynamic>? data}) {
    _service.log(LogLevel.info, component, message, data: data);
  }

  void warn(String message, {Map<String, dynamic>? data, Object? error}) {
    _service.log(LogLevel.warn, component, message, data: data, error: error);
  }

  void error(
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _service.log(
      LogLevel.error,
      component,
      message,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Global logger instance for convenience
final logger = LoggerService.instance;

/// Performance tracer for measuring execution time
///
/// Usage:
/// ```dart
/// final trace = PerformanceTrace.start('MyOperation');
/// // ... do work ...
/// trace.end(); // logs duration
/// ```
class PerformanceTrace {
  final String name;
  final Stopwatch _stopwatch;
  final Map<String, dynamic>? metadata;
  bool _ended = false;

  PerformanceTrace._(this.name, this.metadata) : _stopwatch = Stopwatch()..start();

  /// Start a new performance trace
  static PerformanceTrace start(String name, {Map<String, dynamic>? metadata}) {
    return PerformanceTrace._(name, metadata);
  }

  /// End the trace and log the duration
  /// Returns the elapsed milliseconds
  int end({Map<String, dynamic>? additionalData}) {
    if (_ended) return _stopwatch.elapsedMilliseconds;
    _ended = true;
    _stopwatch.stop();

    final ms = _stopwatch.elapsedMilliseconds;
    final data = {
      'durationMs': ms,
      if (metadata != null) ...metadata!,
      if (additionalData != null) ...additionalData,
    };

    // Log as warning if > 16ms (will cause frame drops), debug otherwise
    final level = ms > 16 ? LogLevel.warn : LogLevel.debug;
    logger.log(level, 'Perf', name, data: data);

    return ms;
  }

  /// Get elapsed time without ending the trace
  int get elapsedMs => _stopwatch.elapsedMilliseconds;
}

/// Throttle class to limit how often a function can be called
class Throttle {
  final Duration interval;
  DateTime? _lastCall;

  Throttle(this.interval);

  /// Returns true if enough time has passed since last call
  bool shouldProceed() {
    final now = DateTime.now();
    if (_lastCall == null || now.difference(_lastCall!) >= interval) {
      _lastCall = now;
      return true;
    }
    return false;
  }

  /// Reset the throttle
  void reset() {
    _lastCall = null;
  }
}
