import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/bm25_index_manager.dart';
import 'package:app/core/services/search/chunking/recording_chunker.dart';
import 'package:app/core/services/search/chunking/journal_chunker.dart';
import 'package:app/core/services/search/chunking/chat_chunker.dart';
import 'package:app/core/services/search/content_hasher.dart';
import 'package:app/core/services/search/models/indexed_chunk.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/journal/services/journal_service.dart';
import 'package:app/features/journal/models/journal_day.dart';
import 'package:app/features/journal/models/journal_entry.dart';
import 'package:app/features/chat/services/local_session_reader.dart';

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

  // Optional journal support (null if not configured)
  JournalService? _journalService;
  JournalChunker? _journalChunker;

  // Optional chat session support (null if not configured)
  LocalSessionReader? _sessionReader;
  ChatChunker? _chatChunker;

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

  /// Configure journal indexing support
  ///
  /// Call this after constructing the service to enable journal indexing.
  void configureJournalIndexing(
    JournalService journalService,
    JournalChunker journalChunker,
  ) {
    _journalService = journalService;
    _journalChunker = journalChunker;
    debugPrint('[SearchIndex] Journal indexing configured');
  }

  /// Check if journal indexing is configured
  bool get hasJournalSupport => _journalService != null && _journalChunker != null;

  /// Configure chat session indexing support
  ///
  /// Call this after constructing the service to enable chat indexing.
  void configureChatIndexing(
    LocalSessionReader sessionReader,
    ChatChunker chatChunker,
  ) {
    _sessionReader = sessionReader;
    _chatChunker = chatChunker;
    debugPrint('[SearchIndex] Chat indexing configured');
  }

  /// Check if chat indexing is configured
  bool get hasChatSupport => _sessionReader != null && _chatChunker != null;

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

  // ========================================================================
  // Rebuild Operations (Full Scan)
  // ========================================================================
  //
  // These methods perform full scans of all content and are intended for:
  // - Initial index build on first launch
  // - Repair operations (forceFullReindex)
  // - Debug/maintenance
  //
  // For normal operation, use the event-driven methods instead:
  // - indexRecording() / removeRecording() for recordings
  // - indexJournalEntry() / removeJournalEntry() for journals
  // - indexChatSessionById() / removeChatSession() for chats
  //
  // The SQLite database syncs via Syncthing, so if device A indexes
  // content, device B gets the updated database automatically.
  // ========================================================================

  /// **REBUILD ONLY** - Sync indexes with source recordings
  ///
  /// Performs a full scan of all recordings, compares content hashes,
  /// and re-indexes any that have changed or are new. Also removes
  /// recordings that have been deleted.
  ///
  /// ⚠️ **Note:** This is a scan-based rebuild operation. For normal
  /// operation, call `indexRecording()` when saving and `removeRecording()`
  /// when deleting. The index database syncs via Syncthing.
  ///
  /// **When to call:**
  /// - On first app launch (initial index build)
  /// - Via forceFullReindex() for repair operations
  ///
  /// **Safe to call concurrently** - subsequent calls will wait for
  /// the first sync to complete rather than starting duplicate work.
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
      // Complete with error for any waiters
      // Ignore the future to prevent unhandled exception reporting
      // since we're going to rethrow anyway
      _syncCompleter!.completeError(e);
      // ignore: unawaited_futures
      _syncCompleter!.future.catchError((_) {});
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

  // ========================================================================
  // Journal Indexing
  // ========================================================================

  /// **REBUILD ONLY** - Sync all journal indexes
  ///
  /// Scans all journal days, compares content hashes, and re-indexes
  /// any that have changed. Requires journal support to be configured.
  ///
  /// ⚠️ **Note:** This is a scan-based rebuild operation. For normal
  /// operation, call `indexJournalEntry()` when creating/updating entries.
  /// The index database syncs via Syncthing.
  ///
  /// **When to call:**
  /// - On first app launch (initial index build)
  /// - Via forceFullReindex() for repair operations
  Future<void> syncJournals() async {
    if (!hasJournalSupport) {
      debugPrint('[SearchIndex] Journal support not configured, skipping');
      return;
    }

    try {
      debugPrint('[SearchIndex] Starting journal sync...');
      _status = IndexingStatus.syncing;
      _notifyListeners();

      // Get all journal dates
      final dates = await _journalService!.listJournalDates();
      debugPrint('[SearchIndex] Found ${dates.length} journal days');

      // Check each journal for changes
      final toIndex = <JournalDay>[];

      for (final date in dates) {
        final journal = await _journalService!.loadDay(date);
        if (journal.entries.isEmpty) continue;

        // Create content ID for the journal day
        final dateStr = _formatDate(date);

        // Check each entry in the journal
        for (final entry in journal.entries) {
          if (entry.id == 'preamble' || entry.content.isEmpty) continue;

          final contentId = 'journal:$dateStr:${entry.id}';
          final currentHash = _hasher.computeJournalEntryHash(entry);
          final storedHash = await _vectorStore.getContentHash(contentId);

          if (storedHash == null || storedHash != currentHash) {
            // Need to index this entry (as part of the journal day)
            if (!toIndex.any((j) => _formatDate(j.date) == dateStr)) {
              toIndex.add(journal);
            }
            break; // Already added this journal day
          }
        }
      }

      debugPrint(
        '[SearchIndex] Journal changes: ${toIndex.length} days to index',
      );

      // Index changed journal days
      _status = IndexingStatus.indexing;
      _totalToIndex = toIndex.length;
      _indexedCount = 0;
      _notifyListeners();

      for (var i = 0; i < toIndex.length; i++) {
        final journal = toIndex[i];
        try {
          debugPrint(
            '[SearchIndex] Indexing journal ${i + 1}/${toIndex.length}: ${journal.dateString}',
          );
          await _indexJournalDay(journal);
          _indexedCount++;
          _notifyListeners();
        } catch (e, stackTrace) {
          debugPrint('[SearchIndex] Error indexing journal ${journal.dateString}: $e');
          debugPrint('[SearchIndex] Stack trace: $stackTrace');
        }
      }

      _status = IndexingStatus.idle;
      _notifyListeners();

      debugPrint('[SearchIndex] ✅ Journal sync complete: ${toIndex.length} days indexed');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Journal sync error: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      _status = IndexingStatus.error;
      _errorMessage = e.toString();
      _notifyListeners();
      rethrow;
    }
  }

  /// **REBUILD ONLY** - Index a single journal day
  Future<void> indexJournalDay(JournalDay journal) async {
    if (!hasJournalSupport) {
      throw StateError('Journal support not configured');
    }

    debugPrint('[SearchIndex] Indexing journal day: ${journal.dateString}');

    try {
      await _indexJournalDay(journal);
      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Journal day indexed: ${journal.dateString}');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error indexing journal day: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ------------------------------------------------------------------------
  // Event-Driven Journal Indexing (Preferred)
  // ------------------------------------------------------------------------

  /// Index a single journal entry (event-driven)
  ///
  /// **Preferred method** - Call this from JournalService when an entry
  /// is added or modified. This is much more efficient than scanning
  /// all journals.
  ///
  /// The index database syncs via Syncthing, so other devices will
  /// receive the indexed content automatically.
  Future<void> indexJournalEntry(
    JournalEntry entry,
    DateTime date,
    String journalFilePath,
  ) async {
    if (!hasJournalSupport) {
      debugPrint('[SearchIndex] Journal support not configured, skipping');
      return;
    }

    // Skip preamble and empty content
    if (entry.id == 'preamble' || entry.content.isEmpty) {
      return;
    }

    final dateStr = _formatDate(date);
    final contentId = 'journal:$dateStr:${entry.id}';

    debugPrint('[SearchIndex] Indexing journal entry: $contentId');

    try {
      // Remove old chunks for this entry
      await _vectorStore.removeChunks(contentId);

      // Chunk the entry
      final chunks = await _journalChunker!.chunkEntry(entry, date);

      if (chunks.isEmpty) {
        debugPrint('[SearchIndex] Warning: No chunks for entry $contentId');
        return;
      }

      // Store chunks
      await _vectorStore.addChunks(chunks);

      // Update manifest
      final hash = _hasher.computeJournalEntryHash(entry);
      await _vectorStore.updateManifest(
        contentId,
        hash,
        chunks.length,
        contentType: ContentType.journal,
        sourcePath: journalFilePath,
      );

      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Entry indexed: $contentId (${chunks.length} chunks)');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error indexing entry $contentId: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      // Don't rethrow - indexing failure shouldn't break the app
    }
  }

  /// Remove a single journal entry from the index
  Future<void> removeJournalEntry(String entryId, DateTime date) async {
    final dateStr = _formatDate(date);
    final contentId = 'journal:$dateStr:$entryId';

    debugPrint('[SearchIndex] Removing journal entry: $contentId');

    try {
      await _vectorStore.removeChunks(contentId);
      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Entry removed: $contentId');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error removing entry: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
    }
  }

  /// Internal implementation of journal day indexing
  Future<void> _indexJournalDay(JournalDay journal) async {
    final dateStr = _formatDate(journal.date);
    final sourcePath = journal.filePath;

    for (final entry in journal.entries) {
      if (entry.id == 'preamble' || entry.content.isEmpty) continue;

      final contentId = 'journal:$dateStr:${entry.id}';

      // Remove old chunks for this entry
      await _vectorStore.removeChunks(contentId);

      // Chunk the entry
      final chunks = await _journalChunker!.chunkEntry(entry, journal.date);

      if (chunks.isEmpty) {
        debugPrint('[SearchIndex] Warning: No chunks for entry $contentId');
        continue;
      }

      // Store chunks
      await _vectorStore.addChunks(chunks);

      // Update manifest with content hash, type, and source path
      final hash = _hasher.computeJournalEntryHash(entry);
      await _vectorStore.updateManifest(
        contentId,
        hash,
        chunks.length,
        contentType: ContentType.journal,
        sourcePath: sourcePath,
      );

      debugPrint(
        '[SearchIndex] Entry $contentId indexed: ${chunks.length} chunks',
      );
    }
  }

  /// Remove a journal day from the index
  Future<void> removeJournalDay(DateTime date) async {
    final dateStr = _formatDate(date);
    debugPrint('[SearchIndex] Removing journal day: $dateStr');

    try {
      // Get all indexed IDs that match this date pattern
      final indexedIds = await _vectorStore.getIndexedRecordingIds();
      final prefix = 'journal:$dateStr:';

      for (final id in indexedIds) {
        if (id.startsWith(prefix)) {
          await _vectorStore.removeChunks(id);
        }
      }

      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Journal day removed: $dateStr');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error removing journal day: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Format date as YYYY-MM-DD
  static String _formatDate(DateTime date) {
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // ========================================================================
  // Chat Session Indexing
  // ========================================================================

  /// **REBUILD ONLY** - Sync all chat session indexes
  ///
  /// Scans all chat sessions, compares content hashes, and re-indexes
  /// any that have changed. Requires chat support to be configured.
  ///
  /// ⚠️ **Note:** This is a scan-based rebuild operation. For normal
  /// operation, call `indexChatSessionById()` when a chat stream completes.
  /// The index database syncs via Syncthing.
  ///
  /// **When to call:**
  /// - On first app launch (initial index build)
  /// - Via forceFullReindex() for repair operations
  Future<void> syncChats() async {
    if (!hasChatSupport) {
      debugPrint('[SearchIndex] Chat support not configured, skipping');
      return;
    }

    try {
      debugPrint('[SearchIndex] Starting chat sync...');
      _status = IndexingStatus.syncing;
      _notifyListeners();

      // Get all local sessions
      final sessions = await _sessionReader!.getLocalSessions();
      debugPrint('[SearchIndex] Found ${sessions.length} chat sessions');

      // Check each session for changes
      final toIndex = <ChatSessionWithLocalMessages>[];

      for (final session in sessions) {
        final contentId = 'chat:${session.id}';

        // Load full session with messages
        final fullSession = await _sessionReader!.getSession(session.id);
        if (fullSession == null || fullSession.messages.isEmpty) continue;

        final currentHash = _hasher.computeChatSessionHash(fullSession);
        final storedHash = await _vectorStore.getContentHash(contentId);

        if (storedHash == null || storedHash != currentHash) {
          toIndex.add(fullSession);
        }
      }

      debugPrint(
        '[SearchIndex] Chat changes: ${toIndex.length} sessions to index',
      );

      // Index changed sessions
      _status = IndexingStatus.indexing;
      _totalToIndex = toIndex.length;
      _indexedCount = 0;
      _notifyListeners();

      for (var i = 0; i < toIndex.length; i++) {
        final sessionData = toIndex[i];
        try {
          debugPrint(
            '[SearchIndex] Indexing chat ${i + 1}/${toIndex.length}: ${sessionData.session.title ?? sessionData.session.id}',
          );
          await _indexChatSession(sessionData);
          _indexedCount++;
          _notifyListeners();
        } catch (e, stackTrace) {
          debugPrint(
            '[SearchIndex] Error indexing chat ${sessionData.session.id}: $e',
          );
          debugPrint('[SearchIndex] Stack trace: $stackTrace');
        }
      }

      _status = IndexingStatus.idle;
      _notifyListeners();

      debugPrint(
        '[SearchIndex] ✅ Chat sync complete: ${toIndex.length} sessions indexed',
      );
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Chat sync error: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      _status = IndexingStatus.error;
      _errorMessage = e.toString();
      _notifyListeners();
      rethrow;
    }
  }

  /// **REBUILD ONLY** - Index a single chat session from full data
  Future<void> indexChatSession(ChatSessionWithLocalMessages sessionData) async {
    if (!hasChatSupport) {
      throw StateError('Chat support not configured');
    }

    debugPrint('[SearchIndex] Indexing chat session: ${sessionData.session.id}');

    try {
      await _indexChatSession(sessionData);
      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Chat session indexed: ${sessionData.session.id}');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error indexing chat session: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // ------------------------------------------------------------------------
  // Event-Driven Chat Indexing (Preferred)
  // ------------------------------------------------------------------------

  /// Index a chat session by ID (event-driven)
  ///
  /// **Preferred method** - Call this from ChatMessagesNotifier when a
  /// streaming response completes. This is much more efficient than
  /// scanning all sessions.
  ///
  /// The index database syncs via Syncthing, so other devices will
  /// receive the indexed content automatically.
  Future<void> indexChatSessionById(String sessionId) async {
    if (!hasChatSupport) {
      debugPrint('[SearchIndex] Chat support not configured, skipping');
      return;
    }

    debugPrint('[SearchIndex] Indexing chat session by ID: $sessionId');

    try {
      // Load the full session with messages
      final sessionData = await _sessionReader!.getSession(sessionId);
      if (sessionData == null || sessionData.messages.isEmpty) {
        debugPrint('[SearchIndex] Session not found or empty: $sessionId');
        return;
      }

      await _indexChatSession(sessionData);
      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Chat session indexed: $sessionId');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error indexing chat session $sessionId: $e');
      debugPrint('[SearchIndex] Stack trace: $stackTrace');
      // Don't rethrow - indexing failure shouldn't break the app
    }
  }

  /// Internal implementation of chat session indexing
  Future<void> _indexChatSession(ChatSessionWithLocalMessages sessionData) async {
    final session = sessionData.session;
    final contentId = 'chat:${session.id}';

    // Remove old chunks for this session
    await _vectorStore.removeChunks(contentId);

    // Determine source path
    final sessionsPath = await _sessionReader!.sessionsPath;
    final sourcePath = sessionsPath != null
        ? '${_sessionReader!.sessionsFolderName}/${session.id}.md'
        : null;

    // Chunk the session
    final chunks = await _chatChunker!.chunkChatSession(sessionData, sourcePath ?? '');

    if (chunks.isEmpty) {
      debugPrint('[SearchIndex] Warning: No chunks for chat $contentId');
      return;
    }

    // Store chunks
    await _vectorStore.addChunks(chunks);

    // Update manifest with content hash, type, and source path
    final hash = _hasher.computeChatSessionHash(sessionData);
    await _vectorStore.updateManifest(
      contentId,
      hash,
      chunks.length,
      contentType: ContentType.chat,
      sourcePath: sourcePath,
    );

    debugPrint(
      '[SearchIndex] Chat $contentId indexed: ${chunks.length} chunks',
    );
  }

  /// Remove a chat session from the index
  Future<void> removeChatSession(String sessionId) async {
    final contentId = 'chat:$sessionId';
    debugPrint('[SearchIndex] Removing chat session: $sessionId');

    try {
      await _vectorStore.removeChunks(contentId);
      _bm25Manager.invalidate();
      debugPrint('[SearchIndex] ✅ Chat session removed: $sessionId');
    } catch (e, stackTrace) {
      debugPrint('[SearchIndex] ❌ Error removing chat session: $e');
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
  /// re-embed all recordings, journals, and chats. Use sparingly.
  Future<void> forceFullReindex() async {
    debugPrint('[SearchIndex] Force full reindex requested');

    try {
      await _vectorStore.clear();
      _bm25Manager.invalidate();

      // Sync recordings
      await syncIndexes();

      // Sync journals if configured
      if (hasJournalSupport) {
        await syncJournals();
      }

      // Sync chats if configured
      if (hasChatSupport) {
        await syncChats();
      }

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
