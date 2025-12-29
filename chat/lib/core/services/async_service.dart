import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status of an async service initialization
enum ServiceStatus {
  uninitialized,
  initializing,
  ready,
  failed,
}

/// Mixin for services that require async initialization
///
/// Provides a standardized pattern for async service initialization
/// that prevents the fire-and-forget anti-pattern.
///
/// Usage:
/// ```dart
/// class MyService with AsyncService {
///   @override
///   Future<void> performInitialize() async {
///     await loadModels();
///     await connectToDatabase();
///   }
/// }
///
/// // In provider:
/// final myServiceProvider = FutureProvider((ref) async {
///   final service = MyService();
///   await service.initialize();
///   return service;
/// });
/// ```
mixin AsyncService {
  ServiceStatus _status = ServiceStatus.uninitialized;
  Object? _initError;
  StackTrace? _initStackTrace;
  Completer<void>? _initCompleter;

  /// Current status of the service
  ServiceStatus get status => _status;

  /// Whether the service is ready to use
  bool get isReady => _status == ServiceStatus.ready;

  /// Whether initialization failed
  bool get hasFailed => _status == ServiceStatus.failed;

  /// Error from failed initialization (if any)
  Object? get initError => _initError;

  /// Stack trace from failed initialization (if any)
  StackTrace? get initStackTrace => _initStackTrace;

  /// Initialize the service
  ///
  /// Safe to call multiple times - subsequent calls wait for the first
  /// initialization to complete.
  ///
  /// Throws if initialization fails.
  Future<void> initialize() async {
    // Already ready
    if (_status == ServiceStatus.ready) return;

    // Already failed - rethrow
    if (_status == ServiceStatus.failed) {
      throw _initError ?? StateError('Service initialization failed');
    }

    // Already initializing - wait for completion
    if (_status == ServiceStatus.initializing && _initCompleter != null) {
      return _initCompleter!.future;
    }

    // Start initialization
    _status = ServiceStatus.initializing;
    _initCompleter = Completer<void>();

    try {
      await performInitialize();
      _status = ServiceStatus.ready;
      _initCompleter!.complete();
    } catch (e, st) {
      _status = ServiceStatus.failed;
      _initError = e;
      _initStackTrace = st;
      _initCompleter!.completeError(e, st);
      rethrow;
    }
  }

  /// Override this method to perform actual initialization
  @protected
  Future<void> performInitialize();

  /// Reset the service to uninitialized state
  ///
  /// Useful for retry scenarios or testing.
  @protected
  void resetInitialization() {
    _status = ServiceStatus.uninitialized;
    _initError = null;
    _initStackTrace = null;
    _initCompleter = null;
  }

  /// Ensure service is initialized before proceeding
  ///
  /// Throws if service is not ready.
  void ensureInitialized() {
    if (_status != ServiceStatus.ready) {
      throw StateError(
        'Service not initialized. Call initialize() first. Status: $_status',
      );
    }
  }
}

/// Extension for creating async-safe providers
///
/// Example usage:
/// ```dart
/// final myServiceProvider = AsyncServiceProvider.create(
///   (ref) => MyService(),
/// );
///
/// // In widget:
/// final service = await ref.watch(myServiceProvider.future);
/// ```
class AsyncServiceProvider {
  /// Create a FutureProvider that properly initializes an AsyncService
  static FutureProvider<T> create<T extends AsyncService>(
    T Function() factory,
  ) {
    return FutureProvider<T>((ref) async {
      final service = factory();
      await service.initialize();
      return service;
    });
  }
}
