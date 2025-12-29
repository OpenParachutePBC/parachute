import 'dart:async';
import 'dart:collection';
import 'logger_service.dart';

/// Priority levels for queued tasks
enum TaskPriority {
  high(0),
  normal(1),
  low(2);

  final int value;
  const TaskPriority(this.value);
}

/// Status of a queued task
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
}

/// A task in the queue
class QueuedTask<T> {
  final String id;
  final String name;
  final TaskPriority priority;
  final Future<T> Function() execute;
  final DateTime createdAt;

  TaskStatus _status = TaskStatus.pending;
  DateTime? startedAt;
  DateTime? completedAt;
  T? result;
  Object? error;
  StackTrace? stackTrace;

  final Completer<T> _completer = Completer<T>();

  QueuedTask({
    required this.id,
    required this.name,
    required this.execute,
    this.priority = TaskPriority.normal,
  }) : createdAt = DateTime.now();

  TaskStatus get status => _status;
  bool get isPending => _status == TaskStatus.pending;
  bool get isRunning => _status == TaskStatus.running;
  bool get isCompleted => _status == TaskStatus.completed;
  bool get isFailed => _status == TaskStatus.failed;
  bool get isCancelled => _status == TaskStatus.cancelled;
  bool get isDone => isCompleted || isFailed || isCancelled;

  /// Future that completes when this task finishes
  Future<T> get future => _completer.future;

  /// Duration the task ran (or has been running)
  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  void _markRunning() {
    _status = TaskStatus.running;
    startedAt = DateTime.now();
  }

  void _markCompleted(T value) {
    _status = TaskStatus.completed;
    completedAt = DateTime.now();
    result = value;
    _completer.complete(value);
  }

  void _markFailed(Object e, StackTrace st) {
    _status = TaskStatus.failed;
    completedAt = DateTime.now();
    error = e;
    stackTrace = st;
    _completer.completeError(e, st);
  }

  void _markCancelled() {
    _status = TaskStatus.cancelled;
    completedAt = DateTime.now();
    _completer.completeError(
      StateError('Task cancelled'),
      StackTrace.current,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priority': priority.name,
        'status': _status.name,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        if (error != null) 'error': error.toString(),
      };
}

/// Background task queue service
///
/// Manages a queue of async tasks with:
/// - Priority ordering (high > normal > low)
/// - Concurrent execution limit
/// - Automatic cleanup of completed tasks
/// - Task cancellation support
/// - Progress tracking
///
/// Modeled after parachute-agent's queue.js pattern.
///
/// Usage:
/// ```dart
/// final queue = TaskQueueService();
///
/// // Enqueue a task
/// final task = queue.enqueue(
///   id: 'transcribe-123',
///   name: 'Transcribe recording',
///   priority: TaskPriority.high,
///   execute: () => transcriptionService.transcribe(recording),
/// );
///
/// // Wait for result
/// final result = await task.future;
///
/// // Or monitor progress
/// queue.tasksStream.listen((tasks) {
///   print('Pending: ${tasks.where((t) => t.isPending).length}');
/// });
/// ```
class TaskQueueService {
  final int maxConcurrent;
  final int keepCompleted;
  final ComponentLogger _log;

  final Queue<QueuedTask> _queue = Queue<QueuedTask>();
  final List<QueuedTask> _completed = [];
  final Set<String> _runningIds = {};

  final _tasksController = StreamController<List<QueuedTask>>.broadcast();
  bool _isProcessing = false;

  TaskQueueService({
    this.maxConcurrent = 1,
    this.keepCompleted = 50,
  }) : _log = logger.createLogger('TaskQueue');

  /// Stream of all tasks (pending + running + recent completed)
  Stream<List<QueuedTask>> get tasksStream => _tasksController.stream;

  /// Current snapshot of all tasks
  List<QueuedTask> get tasks => [
        ..._queue,
        ..._completed,
      ];

  /// Number of pending tasks
  int get pendingCount => _queue.where((t) => t.isPending).length;

  /// Number of running tasks
  int get runningCount => _runningIds.length;

  /// Whether the queue is currently processing
  bool get isProcessing => _isProcessing;

  /// Enqueue a task for execution
  ///
  /// Returns the queued task which can be awaited via [task.future].
  QueuedTask<T> enqueue<T>({
    required String id,
    required String name,
    required Future<T> Function() execute,
    TaskPriority priority = TaskPriority.normal,
  }) {
    // Check for duplicate ID
    final existing = _queue.where((t) => t.id == id).firstOrNull;
    if (existing != null) {
      _log.warn('Task with ID already exists, returning existing', data: {'id': id});
      return existing as QueuedTask<T>;
    }

    final task = QueuedTask<T>(
      id: id,
      name: name,
      execute: execute,
      priority: priority,
    );

    // Insert in priority order
    final insertIndex = _queue.toList().indexWhere(
          (t) => t.priority.value > priority.value,
        );

    if (insertIndex == -1) {
      _queue.add(task);
    } else {
      final list = _queue.toList();
      list.insert(insertIndex, task);
      _queue.clear();
      _queue.addAll(list);
    }

    _log.debug('Task enqueued', data: {
      'id': id,
      'name': name,
      'priority': priority.name,
      'queueLength': _queue.length,
    });

    _notifyListeners();
    _processQueue();

    return task;
  }

  /// Cancel a pending task
  ///
  /// Returns true if task was found and cancelled.
  bool cancel(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null || !task.isPending) return false;

    task._markCancelled();
    _queue.remove(task);
    _completed.add(task);
    _cleanup();

    _log.info('Task cancelled', data: {'id': taskId});
    _notifyListeners();

    return true;
  }

  /// Cancel all pending tasks
  int cancelAll() {
    final pending = _queue.where((t) => t.isPending).toList();
    for (final task in pending) {
      task._markCancelled();
      _queue.remove(task);
      _completed.add(task);
    }
    _cleanup();
    _notifyListeners();

    _log.info('Cancelled all tasks', data: {'count': pending.length});
    return pending.length;
  }

  /// Clear completed/failed/cancelled tasks
  void clearCompleted() {
    _completed.clear();
    _notifyListeners();
  }

  /// Get task by ID
  QueuedTask? getTask(String id) {
    return _queue.where((t) => t.id == id).firstOrNull ??
        _completed.where((t) => t.id == id).firstOrNull;
  }

  /// Get queue statistics
  Map<String, dynamic> getStats() => {
        'pending': pendingCount,
        'running': runningCount,
        'completed': _completed.where((t) => t.isCompleted).length,
        'failed': _completed.where((t) => t.isFailed).length,
        'cancelled': _completed.where((t) => t.isCancelled).length,
        'total': _queue.length + _completed.length,
      };

  void _processQueue() {
    if (_isProcessing) return;
    _isProcessing = true;

    // Use microtask to avoid blocking
    Future.microtask(() async {
      while (_queue.isNotEmpty && _runningIds.length < maxConcurrent) {
        final task = _queue.firstWhere(
          (t) => t.isPending,
          orElse: () => _queue.first,
        );

        if (!task.isPending) break;

        await _executeTask(task);
      }
      _isProcessing = false;
    });
  }

  Future<void> _executeTask(QueuedTask task) async {
    task._markRunning();
    _runningIds.add(task.id);
    _notifyListeners();

    _log.debug('Task started', data: {'id': task.id, 'name': task.name});

    try {
      final result = await task.execute();
      task._markCompleted(result);
      _log.info('Task completed', data: {
        'id': task.id,
        'name': task.name,
        'durationMs': task.duration?.inMilliseconds,
      });
    } catch (e, st) {
      task._markFailed(e, st);
      _log.error('Task failed', data: {'id': task.id, 'name': task.name}, error: e, stackTrace: st);
    } finally {
      _runningIds.remove(task.id);
      _queue.remove(task);
      _completed.add(task);
      _cleanup();
      _notifyListeners();
    }
  }

  void _cleanup() {
    // Keep only the most recent completed tasks
    while (_completed.length > keepCompleted) {
      _completed.removeAt(0);
    }
  }

  void _notifyListeners() {
    _tasksController.add(tasks);
  }

  /// Dispose of resources
  void dispose() {
    _tasksController.close();
  }
}
