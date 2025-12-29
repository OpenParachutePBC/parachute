import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'logger_service.dart';

/// Performance tracking service that logs to files readable by Claude Code
///
/// Writes performance data to:
/// - {vault}/.parachute/perf/current.jsonl - Rolling log of recent events
/// - {vault}/.parachute/perf/summary.json - Aggregated statistics
///
/// Usage:
/// ```dart
/// // Start tracking an operation
/// final trace = perf.trace('MyOperation');
/// // ... do work ...
/// trace.end();
///
/// // Or use the timeline integration
/// perf.timelineSync('BuildWidget', () {
///   // ... synchronous work ...
/// });
///
/// // Async version
/// await perf.timelineAsync('LoadData', () async {
///   // ... async work ...
/// });
/// ```
class PerformanceService {
  static final PerformanceService instance = PerformanceService._();

  /// Path to vault (set by app on startup)
  String? vaultPath;

  /// In-memory buffer of recent events (for quick access)
  final List<PerfEvent> _recentEvents = [];
  static const int _maxRecentEvents = 500;

  /// Aggregated stats by operation name
  final Map<String, PerfStats> _stats = {};

  /// Frame timing tracking
  int _slowFrameCount = 0;
  int _totalFrameCount = 0;
  DateTime? _frameTrackingStart;

  /// File write throttle (batch writes every 5 seconds)
  Timer? _writeTimer;
  bool _pendingWrite = false;

  /// Whether to also use Flutter's Timeline (visible in DevTools)
  bool useTimeline = kDebugMode;

  /// Threshold for "slow" operations (ms)
  int slowThresholdMs = 16; // One frame at 60fps

  PerformanceService._();

  /// Initialize with vault path
  void init(String path) {
    vaultPath = path;
    _ensurePerfDir();
    _startFrameTracking();
  }

  /// Create a performance trace
  PerfTrace trace(String name, {Map<String, dynamic>? metadata}) {
    return PerfTrace._(this, name, metadata);
  }

  /// Execute synchronous work with timeline tracking
  T timelineSync<T>(String name, T Function() work, {Map<String, dynamic>? metadata}) {
    if (useTimeline) {
      developer.Timeline.startSync(name, arguments: metadata);
    }
    final stopwatch = Stopwatch()..start();
    try {
      return work();
    } finally {
      stopwatch.stop();
      if (useTimeline) {
        developer.Timeline.finishSync();
      }
      _recordEvent(name, stopwatch.elapsedMilliseconds, metadata);
    }
  }

  /// Execute async work with timeline tracking
  Future<T> timelineAsync<T>(String name, Future<T> Function() work, {Map<String, dynamic>? metadata}) async {
    if (useTimeline) {
      developer.Timeline.startSync(name, arguments: metadata);
    }
    final stopwatch = Stopwatch()..start();
    try {
      return await work();
    } finally {
      stopwatch.stop();
      if (useTimeline) {
        developer.Timeline.finishSync();
      }
      _recordEvent(name, stopwatch.elapsedMilliseconds, metadata);
    }
  }

  /// Record a completed event
  void _recordEvent(String name, int durationMs, Map<String, dynamic>? metadata) {
    final event = PerfEvent(
      name: name,
      durationMs: durationMs,
      timestamp: DateTime.now(),
      metadata: metadata,
      isSlow: durationMs > slowThresholdMs,
    );

    // Add to recent events
    _recentEvents.add(event);
    while (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }

    // Update stats
    _stats.putIfAbsent(name, () => PerfStats(name));
    _stats[name]!.record(durationMs);

    // Log slow operations
    if (event.isSlow) {
      logger.log(LogLevel.warn, 'Perf', '$name took ${durationMs}ms', data: metadata);
    }

    // Schedule file write
    _schedulePendingWrite();
  }

  /// Start tracking frame timing
  void _startFrameTracking() {
    _frameTrackingStart = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _totalFrameCount++;
      final buildDuration = timing.buildDuration.inMilliseconds;
      final rasterDuration = timing.rasterDuration.inMilliseconds;
      final totalFrame = timing.totalSpan.inMilliseconds;

      if (totalFrame > 16) {
        _slowFrameCount++;
        // Log very slow frames
        if (totalFrame > 32) {
          logger.log(LogLevel.warn, 'Perf', 'Slow frame: ${totalFrame}ms', data: {
            'buildMs': buildDuration,
            'rasterMs': rasterDuration,
          });
        }
      }
    }
  }

  /// Schedule a batched file write
  void _schedulePendingWrite() {
    _pendingWrite = true;
    _writeTimer ??= Timer(const Duration(seconds: 5), () {
      _writeTimer = null;
      if (_pendingWrite) {
        _pendingWrite = false;
        _writeToFiles();
      }
    });
  }

  /// Force immediate write (call before app closes)
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;
    await _writeToFiles();
  }

  /// Ensure perf directory exists
  void _ensurePerfDir() {
    if (vaultPath == null) return;
    final dir = Directory('$vaultPath/.parachute/perf');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Write performance data to files
  Future<void> _writeToFiles() async {
    if (vaultPath == null) return;

    try {
      final perfDir = '$vaultPath/.parachute/perf';

      // Write recent events as JSONL (one JSON object per line)
      final eventsFile = File('$perfDir/current.jsonl');
      final eventLines = _recentEvents.map((e) => jsonEncode(e.toJson())).join('\n');
      await eventsFile.writeAsString('$eventLines\n');

      // Write summary as JSON
      final summaryFile = File('$perfDir/summary.json');
      await summaryFile.writeAsString(jsonEncode(getSummary()));

      debugPrint('[Perf] Wrote ${_recentEvents.length} events to $perfDir');
    } catch (e) {
      debugPrint('[Perf] Error writing perf files: $e');
    }
  }

  /// Get performance summary (also written to summary.json)
  Map<String, dynamic> getSummary() {
    final now = DateTime.now();
    final trackingDuration = _frameTrackingStart != null
        ? now.difference(_frameTrackingStart!).inSeconds
        : 0;

    return {
      'generatedAt': now.toIso8601String(),
      'trackingDurationSec': trackingDuration,
      'frames': {
        'total': _totalFrameCount,
        'slow': _slowFrameCount,
        'slowPercent': _totalFrameCount > 0
            ? (_slowFrameCount / _totalFrameCount * 100).toStringAsFixed(1)
            : '0',
      },
      'operations': _stats.map((name, stats) => MapEntry(name, stats.toJson())),
      'recentSlowEvents': _recentEvents
          .where((e) => e.isSlow)
          .toList()
          .reversed
          .take(20)
          .map((e) => e.toJson())
          .toList(),
    };
  }

  /// Get recent events for a specific operation
  List<PerfEvent> getEventsFor(String name, {int limit = 50}) {
    return _recentEvents
        .where((e) => e.name == name)
        .toList()
        .reversed
        .take(limit)
        .toList();
  }

  /// Get stats for a specific operation
  PerfStats? getStatsFor(String name) => _stats[name];

  /// Clear all recorded data
  void clear() {
    _recentEvents.clear();
    _stats.clear();
    _slowFrameCount = 0;
    _totalFrameCount = 0;
    _frameTrackingStart = DateTime.now();
  }

  /// Generate a text report (for logging/debugging)
  String generateReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== Performance Report ===');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();

    // Frame stats
    buffer.writeln('Frame Performance:');
    buffer.writeln('  Total frames: $_totalFrameCount');
    buffer.writeln('  Slow frames (>16ms): $_slowFrameCount');
    if (_totalFrameCount > 0) {
      final pct = (_slowFrameCount / _totalFrameCount * 100).toStringAsFixed(1);
      buffer.writeln('  Slow frame rate: $pct%');
    }
    buffer.writeln();

    // Operation stats (sorted by total time)
    buffer.writeln('Operations (sorted by total time):');
    final sortedStats = _stats.values.toList()
      ..sort((a, b) => b.totalMs.compareTo(a.totalMs));

    for (final stats in sortedStats.take(20)) {
      buffer.writeln('  ${stats.name}:');
      buffer.writeln('    Count: ${stats.count}');
      buffer.writeln('    Total: ${stats.totalMs}ms');
      buffer.writeln('    Avg: ${stats.avgMs.toStringAsFixed(1)}ms');
      buffer.writeln('    Max: ${stats.maxMs}ms');
      buffer.writeln('    Slow: ${stats.slowCount}');
    }

    return buffer.toString();
  }
}

/// A single performance event
class PerfEvent {
  final String name;
  final int durationMs;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final bool isSlow;

  PerfEvent({
    required this.name,
    required this.durationMs,
    required this.timestamp,
    this.metadata,
    this.isSlow = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'durationMs': durationMs,
        'timestamp': timestamp.toIso8601String(),
        'isSlow': isSlow,
        if (metadata != null) 'metadata': metadata,
      };
}

/// Aggregated stats for an operation
class PerfStats {
  final String name;
  int count = 0;
  int totalMs = 0;
  int minMs = 0;
  int maxMs = 0;
  int slowCount = 0;

  PerfStats(this.name);

  double get avgMs => count > 0 ? totalMs / count : 0;

  void record(int durationMs) {
    count++;
    totalMs += durationMs;
    if (count == 1 || durationMs < minMs) minMs = durationMs;
    if (durationMs > maxMs) maxMs = durationMs;
    if (durationMs > 16) slowCount++;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'count': count,
        'totalMs': totalMs,
        'avgMs': avgMs.toStringAsFixed(1),
        'minMs': minMs,
        'maxMs': maxMs,
        'slowCount': slowCount,
      };
}

/// Active performance trace (stopwatch-based)
class PerfTrace {
  final PerformanceService _service;
  final String name;
  final Map<String, dynamic>? metadata;
  final Stopwatch _stopwatch;
  bool _ended = false;

  PerfTrace._(this._service, this.name, this.metadata)
      : _stopwatch = Stopwatch()..start() {
    if (_service.useTimeline) {
      developer.Timeline.startSync(name, arguments: metadata);
    }
  }

  /// End the trace and record the duration
  int end({Map<String, dynamic>? additionalData}) {
    if (_ended) return _stopwatch.elapsedMilliseconds;
    _ended = true;
    _stopwatch.stop();

    if (_service.useTimeline) {
      developer.Timeline.finishSync();
    }

    final finalMetadata = {
      if (metadata != null) ...metadata!,
      if (additionalData != null) ...additionalData,
    };

    _service._recordEvent(
      name,
      _stopwatch.elapsedMilliseconds,
      finalMetadata.isNotEmpty ? finalMetadata : null,
    );

    return _stopwatch.elapsedMilliseconds;
  }

  /// Get elapsed time without ending
  int get elapsedMs => _stopwatch.elapsedMilliseconds;
}

/// Global performance service instance
final perf = PerformanceService.instance;
