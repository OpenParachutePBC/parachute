import 'package:flutter/foundation.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';

/// Manages BM25 index lifecycle
///
/// Handles index building, rebuilding, and invalidation.
/// Coordinates with StorageService to keep index in sync with recordings.
///
/// **Index Rebuild Triggers:**
/// - App startup (on first search)
/// - Recording added/updated/deleted
/// - User triggers refresh
///
/// **Usage:**
/// ```dart
/// final manager = BM25IndexManager(searchService, storageService);
///
/// // Ensure index is ready (builds if needed)
/// await manager.ensureIndexReady();
///
/// // Rebuild index (e.g., after recordings change)
/// await manager.rebuildIndex();
///
/// // Invalidate index (will rebuild on next search)
/// manager.invalidate();
/// ```
class BM25IndexManager {
  final BM25SearchService _searchService;
  final StorageService _storageService;

  bool _isBuilding = false;
  DateTime? _lastBuilt;

  BM25IndexManager(this._searchService, this._storageService);

  /// Check if index is currently being built
  bool get isBuilding => _isBuilding;

  /// Get timestamp of last index build
  DateTime? get lastBuilt => _lastBuilt;

  /// Check if index needs rebuilding
  bool get needsRebuild => _searchService.needsRebuild;

  /// Ensure index is ready for searching
  ///
  /// Builds the index if it hasn't been built yet.
  /// Returns immediately if index is already ready.
  ///
  /// **Example:**
  /// ```dart
  /// await manager.ensureIndexReady();
  /// final results = await searchService.search('query');
  /// ```
  Future<void> ensureIndexReady() async {
    if (_searchService.needsRebuild) {
      await rebuildIndex();
    } else {
      debugPrint('[BM25IndexManager] Index already ready');
    }
  }

  /// Rebuild index from all recordings
  ///
  /// Loads all recordings from StorageService and rebuilds the BM25 index.
  /// Safe to call concurrently - subsequent calls will wait for the first
  /// build to complete rather than starting duplicate builds.
  ///
  /// **Performance:** ~500ms for 1000 recordings (varies by device)
  ///
  /// **Example:**
  /// ```dart
  /// // After adding a recording
  /// await storageService.saveRecording(recording);
  /// await indexManager.rebuildIndex();
  /// ```
  Future<void> rebuildIndex() async {
    // If already building, wait for it to complete
    if (_isBuilding) {
      debugPrint('[BM25IndexManager] Build already in progress, waiting...');
      // Simple polling wait - could be improved with a Completer
      while (_isBuilding) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      debugPrint('[BM25IndexManager] Build completed by another caller');
      return;
    }

    _isBuilding = true;

    try {
      debugPrint('[BM25IndexManager] Rebuilding index...');
      final stopwatch = Stopwatch()..start();

      // Load all recordings from storage
      final recordings = await _storageService.getRecordings();

      // Build index
      await _searchService.buildIndex(recordings);

      _lastBuilt = DateTime.now();
      stopwatch.stop();

      debugPrint(
        '[BM25IndexManager] ✅ Index rebuilt successfully in '
        '${stopwatch.elapsedMilliseconds}ms '
        '(${recordings.length} recordings)',
      );
    } catch (e, stackTrace) {
      debugPrint('[BM25IndexManager] ❌ Error rebuilding index: $e');
      debugPrint('[BM25IndexManager] Stack trace: $stackTrace');
      rethrow;
    } finally {
      _isBuilding = false;
    }
  }

  /// Invalidate the index
  ///
  /// Clears the index and marks it as needing rebuild.
  /// The index will be rebuilt on the next search or when
  /// ensureIndexReady() is called.
  ///
  /// **When to invalidate:**
  /// - After recording is added/updated/deleted
  /// - After bulk operations on recordings
  /// - When user pulls to refresh
  ///
  /// **Example:**
  /// ```dart
  /// // In StorageService.saveRecording():
  /// await saveRecordingToFile(recording);
  /// indexManager.invalidate();
  /// ```
  void invalidate() {
    debugPrint('[BM25IndexManager] Invalidating index');
    _searchService.clear();
    _lastBuilt = null;
  }

  /// Get index statistics
  ///
  /// Returns a map with index metadata for debugging/monitoring.
  Map<String, dynamic> getStats() {
    return {
      'isBuilt': !_searchService.needsRebuild,
      'isBuilding': _isBuilding,
      'indexSize': _searchService.indexSize,
      'lastBuilt': _lastBuilt?.toIso8601String(),
    };
  }
}
