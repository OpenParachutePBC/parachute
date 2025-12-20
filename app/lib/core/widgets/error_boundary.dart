import 'package:flutter/material.dart';
import '../services/logger_service.dart';
import '../errors/app_error.dart';

/// Error boundary widget that catches and displays errors gracefully
///
/// Wraps a widget tree and catches any errors that occur during build,
/// displaying a fallback UI instead of crashing the app.
///
/// Usage:
/// ```dart
/// ErrorBoundary(
///   onError: (error, stack) => analytics.logError(error, stack),
///   child: MyComplexWidget(),
/// )
/// ```
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, StackTrace? stackTrace)? fallbackBuilder;
  final void Function(Object error, StackTrace? stackTrace)? onError;
  final bool showRetry;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallbackBuilder,
    this.onError,
    this.showRetry = true,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;
  final _log = logger.createLogger('ErrorBoundary');

  @override
  void initState() {
    super.initState();
  }

  void _handleError(Object error, StackTrace? stackTrace) {
    _log.error('Caught error in boundary', error: error, stackTrace: stackTrace);
    widget.onError?.call(error, stackTrace);

    if (mounted) {
      setState(() {
        _error = error;
        _stackTrace = stackTrace;
      });
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _stackTrace = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.fallbackBuilder != null) {
        return widget.fallbackBuilder!(_error!, _stackTrace);
      }
      return _DefaultErrorWidget(
        error: _error!,
        stackTrace: _stackTrace,
        onRetry: widget.showRetry ? _retry : null,
      );
    }

    return _ErrorCatcher(
      onError: _handleError,
      child: widget.child,
    );
  }
}

/// Internal widget that catches errors during build
class _ErrorCatcher extends StatelessWidget {
  final Widget child;
  final void Function(Object error, StackTrace? stackTrace) onError;

  const _ErrorCatcher({
    required this.child,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    // Flutter's error handling - catches build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      onError(details.exception, details.stack);
      return const SizedBox.shrink();
    };

    return child;
  }
}

/// Default error display widget
class _DefaultErrorWidget extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;

  const _DefaultErrorWidget({
    required this.error,
    this.stackTrace,
    this.onRetry,
  });

  String get _errorMessage {
    if (error is AppError) {
      return (error as AppError).message;
    }
    return error.toString();
  }

  String get _errorCode {
    if (error is AppError) {
      return (error as AppError).code;
    }
    return 'UNKNOWN_ERROR';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: isDark ? Colors.red[300] : Colors.red[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Error code: $_errorCode',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[500] : Colors.grey[500],
                fontFamily: 'monospace',
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Screen-level error boundary with consistent styling
///
/// Use this to wrap entire screens:
/// ```dart
/// class MyScreen extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return ScreenErrorBoundary(
///       child: Scaffold(...),
///     );
///   }
/// }
/// ```
class ScreenErrorBoundary extends StatelessWidget {
  final Widget child;
  final void Function(Object error, StackTrace? stackTrace)? onError;

  const ScreenErrorBoundary({
    super.key,
    required this.child,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      onError: onError,
      fallbackBuilder: (error, stackTrace) => Scaffold(
        appBar: AppBar(
          title: const Text('Error'),
        ),
        body: _DefaultErrorWidget(
          error: error,
          stackTrace: stackTrace,
          onRetry: () {
            // Force rebuild by navigating to same route
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ScreenErrorBoundary(
                  onError: onError,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
      child: child,
    );
  }
}

/// Provider error boundary for Riverpod AsyncValue errors
///
/// Usage with Riverpod:
/// ```dart
/// Consumer(
///   builder: (context, ref, child) {
///     final asyncData = ref.watch(myProvider);
///     return AsyncErrorBoundary(
///       asyncValue: asyncData,
///       builder: (data) => MyWidget(data: data),
///     );
///   },
/// )
/// ```
class AsyncErrorBoundary<T> extends StatelessWidget {
  final AsyncValue<T> asyncValue;
  final Widget Function(T data) builder;
  final Widget Function()? loadingBuilder;
  final Widget Function(Object error, StackTrace? stackTrace)? errorBuilder;
  final VoidCallback? onRetry;

  const AsyncErrorBoundary({
    super.key,
    required this.asyncValue,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: builder,
      loading: () => loadingBuilder?.call() ?? const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stackTrace) => errorBuilder?.call(error, stackTrace) ??
          _DefaultErrorWidget(
            error: error,
            stackTrace: stackTrace,
            onRetry: onRetry,
          ),
    );
  }
}

/// Type alias for Riverpod's AsyncValue
typedef AsyncValue<T> = _AsyncValue<T>;

/// Simple AsyncValue implementation for non-Riverpod usage
class _AsyncValue<T> {
  final T? _data;
  final Object? _error;
  final StackTrace? _stackTrace;
  final bool _isLoading;

  const _AsyncValue.data(T data)
      : _data = data,
        _error = null,
        _stackTrace = null,
        _isLoading = false;

  const _AsyncValue.loading()
      : _data = null,
        _error = null,
        _stackTrace = null,
        _isLoading = true;

  const _AsyncValue.error(Object error, [StackTrace? stackTrace])
      : _data = null,
        _error = error,
        _stackTrace = stackTrace,
        _isLoading = false;

  R when<R>({
    required R Function(T data) data,
    required R Function() loading,
    required R Function(Object error, StackTrace? stackTrace) error,
  }) {
    if (_isLoading) return loading();
    if (_error != null) return error(_error!, _stackTrace);
    return data(_data as T);
  }
}
