import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/bm25_index_manager.dart';
import 'package:app/core/services/search/chunking/recording_chunker.dart';
import 'package:app/core/services/search/content_hasher.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/models/recording.dart';

/// Status of the search indexing process
enum IndexingStatus {
  /// No indexing operation in progress
  idle,

  /// Checking for changes (comparing hashes)
  syncing,

  /// Processing recordings (chunking + embedding + storage)
  indexing,

  /// Error occurred during indexing
  error,
}

/// Search Index Service - Orchestrates the RAG search indexing lifecycle
///
/// This service is the central coordinator for maintaining search indexes.
/// It watches for recording changes, manages content hashing for change
/// detection, and ensures both vector and BM25 indexes stay in sync.
///
/// **Key Responsibilities:**
/// 1. **Change Detection** - Hash-based detection of recording changes
/// 2. **Indexing Pipeline** - Recording → Chunks → Embeddings → Vector Store
/// 3. **BM25 Sync** - Keep BM25 index in sync with recordings
/// 4. **Status Tracking** - Report indexing progress for UI
/// 5. **Initialization** - Build initial index on app start
/// 6. **Incremental Updates** - Only re-index changed recordings
///
/// **Data Flow:**
/// ```
/// Recording Changed
///       │
///       ▼
/// SearchIndexService.onRecordingChanged(recordingId)
///       │
///       ├──► RecordingChunker.chunkRecording()
///       │          │
///       │          ▼
///       │    EmbeddingService.embedBatch(chunks)
///       │          │
///       │          ▼
///       │    VectorStore.addChunks(indexedChunks)
///       │
///       └──► BM25IndexManager.rebuildIndex()
/// ```
///
/// **Usage:**
/// ```dart
/// // On app start
/// final searchIndex = ref.read(searchIndexServiceProvider);
/// searchIndex.syncIndexes(); // Non-blocking background sync
///
/// // On recording save
/// await storageService.saveRecording(recording);
/// await searchIndex.indexRecording(recording);
///
/// // On recording delete
/// await storageService.deleteRecording(recordingId);
/// await searchIndex.removeRecording(recordingId);
///
/// // Monitor progress
/// searchIndex.addListener(() {
///   print('Status: ${searchIndex.status}');
///   print('Progress: ${searchIndex.progress}');
/// });
/// ```
class SearchIndexService {
  final VectorStore _vectorStore;
  final BM25IndexManager _bm25Manager;
  final RecordingChunker _chunker;
  final StorageService _storageService;
  final ContentHasher _hasher;

  // Status tracking
  IndexingStatus _status = IndexingStatus.idle;
  String? _errorMessage;
  int _totalToIndex = 0;
  int _indexedCount = 0;

  // Prevent concurrent sync operations
  bool _isSyncing = false;
  Completer<void>? _syncCompleter;

  SearchIndexService(
    this._vectorStore,
    this._bm25Manager,
    this._chunker,
    this._storageService,
    this._hasher,
  );

  /// Current indexing status
  IndexingStatus get status => _status;

  /// Error message if status is error
  String? get errorMessage => _errorMessage;

  /// Total number of recordings to process in current operation
  int get totalToIndex => _totalToIndex;

  /// Number of recordings processed so far
  int get indexedCount => _indexedCount;

  /// Progress as a value from 0.0 to 1.0
  double get progress =>
      _totalToIndex > 0 ? _indexedCount / _totalToIndex : 0.0;

  /// Check if sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Sync indexes with source recordings
  ///
  /// Performs a full scan of all recordings, compares content hashes,
  /// and re-indexes any that have changed or are new. Also removes
  /// recordings that have been deleted.
  ///
  /// **When to call:**
  /// - On app start (non-blocking background task)
  /// - After pull-to-refresh
  /// - After bulk operations
  ///
  /// **Safe to call concurrently** - subsequent calls will wait for
  /// the first sync to complete rather than starting duplicate work.
  ///
  /// **Performance:** Depends on number of changed recordings.
  /// - Checking hashes: ~1ms per recording
  /// - Indexing: ~500ms per recording (embedding generation)
  Future<void> syncIndexes() async {
    // If already syncing, wait for it to complete
    if (_isSyncing) {
      debugPrint('[SearchIndex] Sync already in progress, waiting...');
      if (_syncCompleter != null) {
        await _syncCompleter!.future;
      }
      debugPrint('[SearchIndex] Sync completed by another caller');
      return;
    }

    _isSyncing = true;
    _syncCompleter = Completer<void>();

    try {
      await _doSyncIndexes();
      _syncCompleter!.complete();
    } catch (e) {
      _syncCompleter!.completeError(e);
      rethrow;
    } finally {
      _isSyncing = false;
      _syncCompleter = null;
    }
  }

  /// Internal implementation of index sync
  Future<void> _doSyncIndexes() async {
    try {
      debugPrint('[SearchIndex] Starting index sync...');
      _status = IndexingStatus.syncing;
      _errorMessage = null;
      _notifyListeners();

      // 1. Get all recordings from storage
      final recordings = await _storageService.getRecordings();
      final recordingMap = {for (var r in recordings) r.id: r};
      debugPrint('[SearchIndex] Found ${recordings.length} recordings');

      // 2. Get indexed recording IDs from vector store
      final indexedIds = await _vectorStore.getIndexedRecordingIds();
      debugPrint('[SearchIndex] Found ${indexedIds.length} indexed recordings');

      // 3. Determine what needs updating
      final toIndex = <Recording>[];
      final toRemove = <String>[];

      // Check each recording for changes
      for (final recording in recordings) {
        final currentHash = _hasher.computeHash(recording);
        final storedHash = await _vectorStore.getContentHash(recording.id);

        if (storedHash == null) {
          // New recording
          debugPrint('[SearchIndex] New recording: ${recording.id}');
          toIndex.add(recording);
        } else if (storedHash != currentHash) {
          // Modified recording
          debugPrint(
            '[SearchIndex] Modified recording: ${recording.id} '
            '(hash: $storedHash → $currentHash)',
          );
          toIndex.add(recording);
        }
      }

      // Find deleted recordings
      for (final indexedId in indexedIds) {
        if (!recordingMap.containsKey(indexedId)) {
          debugPrint('[SearchIndex] Deleted recording: $indexedId');
          toRemove.add(indexedId);
        }
      }

      debugPrint(
        '[SearchIndex] Changes detected: ${toIndex.length} to index, '
        '${toRemove.length} to remove',
      );

      // 4. Process changes
      _status = IndexingStatus.indexing;
      _totalToIndex = toIndex.length + toRemove.length;
      _indexedCount = 0;
      _notifyListeners();

      // Remove deleted recordings
      for (final id in toRemove) {
        await _vectorStore.removeChunks(id);
        _indexedCount++;
        _notifyListeners();
      }

      // Index new/changed recordings
      for (final recording in toIndex) {
        try {
          await _indexRecording(recording);
          _indexedCount++;
          _notifyListeners();
        } catch (e, stackTrace) {
          debugPrint(
            '[SearchIndex] Error indexing ${recording.id}: $e',
          );
          debugPrint('[SearchIndex] Stack trace: $stackTrace');
          // Continue with other recordings rather than failing completely
        }
      }

      // 5. Rebuild BM25 index
      // Fast operation (~500ms for 1000 recordings), just rebuild from scratch
      debugPrint('[SearchIndex] Rebuilding BM25 index...');
      await _bm25Manager.rebuildIndex();

      _status = IndexingStatus.idle;
      _errorMessage = null;
      _notifyListeners();

      debugPrint(
        '[SearchIndex] ✅ Sync complete. '
        'Indexed: ${toIndex.length}, Removed: ${toRemove.length}',
      );
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error during sync: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      _status = IndexingStatus.error;
      _errorMessage = e.toString();
      _notifyListeners();
      rethrow;
    }
  }

  /// Index a single recording
  ///
  /// Used for immediate indexing when a recording is saved.
  /// Blocks until indexing is complete to ensure data consistency.
  ///
  /// **When to call:**
  /// - After saving a recording
  /// - After editing a recording
  ///
  /// **Example:**
  /// ```dart
  /// await storageService.saveRecording(recording);
  /// await searchIndex.indexRecording(recording);
  /// ```
  Future<void> indexRecording(Recording recording) async {
    debugPrint('[SearchIndex] Indexing single recording: ${recording.id}');

    try {
      await _indexRecording(recording);

      // Invalidate BM25 index (will rebuild on next search)
      _bm25Manager.invalidate();

      debugPrint('[SearchIndex] ✅ Recording indexed: ${recording.id}');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error indexing recording: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Internal implementation of recording indexing
  Future<void> _indexRecording(Recording recording) async {
    // 1. Remove old chunks if any (handles re-indexing)
    await _vectorStore.removeChunks(recording.id);

    // 2. Chunk the recording (includes embedding generation)
    final chunks = await _chunker.chunkRecording(recording);

    if (chunks.isEmpty) {
      debugPrint(
        '[SearchIndex] Warning: No chunks generated for ${recording.id}',
      );
      return;
    }

    // 3. Store chunks in vector store
    await _vectorStore.addChunks(chunks);

    // 4. Update manifest with content hash
    final hash = _hasher.computeHash(recording);
    await _vectorStore.updateManifest(recording.id, hash, chunks.length);

    debugPrint(
      '[SearchIndex] Recording ${recording.id} indexed: '
      '${chunks.length} chunks, hash: $hash',
    );
  }

  /// Remove a recording from indexes
  ///
  /// Used when a recording is deleted.
  ///
  /// **Example:**
  /// ```dart
  /// await storageService.deleteRecording(recordingId);
  /// await searchIndex.removeRecording(recordingId);
  /// ```
  Future<void> removeRecording(String recordingId) async {
    debugPrint('[SearchIndex] Removing recording: $recordingId');

    try {
      await _vectorStore.removeChunks(recordingId);
      _bm25Manager.invalidate();

      debugPrint('[SearchIndex] ✅ Recording removed: $recordingId');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error removing recording: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Force full reindex
  ///
  /// Clears all indexes and rebuilds from scratch.
  /// Use for debugging or repair operations.
  ///
  /// **Warning:** This is an expensive operation that will
  /// re-embed all recordings. Use sparingly.
  Future<void> forceFullReindex() async {
    debugPrint('[SearchIndex] Force full reindex requested');

    try {
      await _vectorStore.clear();
      _bm25Manager.invalidate();
      await syncIndexes();

      debugPrint('[SearchIndex] ✅ Full reindex complete');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error during full reindex: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get index statistics
  ///
  /// Returns a map with:
  /// - 'vectorStore': Vector store stats (totalChunks, totalRecordings, totalSize)
  /// - 'bm25': BM25 index stats (isBuilt, indexSize, lastBuilt)
  /// - 'status': Current indexing status
  /// - 'progress': Current progress (0.0-1.0)
  Future<Map<String, dynamic>> getStats() async {
    final vectorStats = await _vectorStore.getStats();
    final bm25Stats = _bm25Manager.getStats();

    return {
      'vectorStore': vectorStats,
      'bm25': bm25Stats,
      'status': _status.toString(),
      'progress': progress,
      'error': _errorMessage,
    };
  }

  // ========================================================================
  // Listener Pattern for Status Updates
  // ========================================================================

  final _listeners = <VoidCallback>[];

  /// Add a listener for status updates
  ///
  /// The listener will be called whenever the status, progress,
  /// or error message changes.
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// Remove a previously added listener
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Notify all listeners of a status change
  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        debugPrint('[SearchIndex] Error in listener: $e');
      }
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    _listeners.clear();
    await _vectorStore.close();
  }
}
