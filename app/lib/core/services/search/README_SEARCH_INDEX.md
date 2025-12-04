# Search Index Service

## Overview

The Search Index Service is the central orchestrator for the RAG (Retrieval-Augmented Generation) search indexing lifecycle in Parachute. It coordinates all search-related components to maintain synchronized vector and BM25 indexes.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│              SearchIndexService                          │
│  (Orchestrates the entire indexing pipeline)             │
└──────┬───────────────────────────────────────────┬───────┘
       │                                           │
       ▼                                           ▼
┌──────────────┐                          ┌────────────────┐
│ ContentHasher│                          │ StorageService │
│  (SHA-256)   │                          │  (Recordings)  │
└──────────────┘                          └────────────────┘
       │                                           │
       ▼                                           ▼
┌──────────────────────────────────────────────────────────┐
│                 Change Detection                         │
│     (Compare hashes to detect new/modified/deleted)      │
└──────┬───────────────────────────────────────────┬───────┘
       │                                           │
       ▼                                           ▼
┌──────────────┐     ┌──────────────┐     ┌────────────────┐
│ Recording    │────►│ Embedding    │────►│ Vector Store   │
│ Chunker      │     │ Service      │     │   (SQLite)     │
└──────────────┘     └──────────────┘     └────────────────┘
       │
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│             BM25 Index Manager                           │
│     (Rebuilds keyword search index)                      │
└──────────────────────────────────────────────────────────┘
```

## Components

### 1. ContentHasher (`content_hasher.dart`)

**Purpose:** Compute SHA-256 hashes of recording content for change detection.

**Why hashing?**
- File timestamps change on git sync even if content is identical
- Hash-based detection is reliable for distributed sync across devices
- SHA-256 provides strong uniqueness guarantees

**What's hashed:**
- Title
- Summary
- Context
- Tags (joined with commas)
- Transcript

**What's NOT hashed:**
- Timestamp
- Duration
- File size
- File path

These metadata fields don't affect searchability, so changes to them don't require re-indexing.

### 2. SearchIndexService (`search_index_service.dart`)

**Purpose:** Main orchestrator that coordinates the entire indexing lifecycle.

**Key Responsibilities:**
1. **Change Detection** - Compare content hashes to find new/modified/deleted recordings
2. **Indexing Pipeline** - Recording → Chunks → Embeddings → Vector Store
3. **BM25 Sync** - Keep keyword search index in sync
4. **Status Tracking** - Report progress for UI
5. **Incremental Updates** - Only re-index what changed

**Status States:**
- `idle` - No operation in progress
- `syncing` - Checking for changes (comparing hashes)
- `indexing` - Processing recordings (chunking + embedding)
- `error` - Error occurred during operation

**API:**

```dart
// Background sync (non-blocking)
await searchIndex.syncIndexes();

// Immediate indexing (blocking)
await searchIndex.indexRecording(recording);

// Remove from indexes
await searchIndex.removeRecording(recordingId);

// Force full rebuild (expensive)
await searchIndex.forceFullReindex();

// Monitor progress
searchIndex.addListener(() {
  print('Status: ${searchIndex.status}');
  print('Progress: ${searchIndex.progress}');
});
```

## Data Flow

### 1. New Recording

```
User saves recording
        │
        ▼
StorageService.saveRecording()
        │
        ▼
SearchIndexService.indexRecording()
        │
        ├──► ContentHasher.computeHash()
        │
        ├──► RecordingChunker.chunkRecording()
        │           │
        │           ├──► SemanticChunker (transcript)
        │           │         │
        │           │         └──► EmbeddingService.embed()
        │           │
        │           ├──► EmbeddingService.embed(title)
        │           ├──► EmbeddingService.embed(summary)
        │           └──► EmbeddingService.embed(context)
        │
        ├──► VectorStore.addChunks()
        │
        ├──► VectorStore.updateManifest(hash, chunkCount)
        │
        └──► BM25IndexManager.invalidate()
```

### 2. Sync on App Start

```
App starts
        │
        ▼
SearchIndexService.syncIndexes()
        │
        ├──► StorageService.getRecordings()
        │
        ├──► VectorStore.getIndexedRecordingIds()
        │
        ├──► For each recording:
        │      │
        │      ├──► ContentHasher.computeHash()
        │      │
        │      └──► Compare with stored hash
        │            │
        │            ├──► Same? → Skip
        │            │
        │            └──► Different? → Re-index
        │
        ├──► Find deleted recordings
        │      │
        │      └──► VectorStore.removeChunks()
        │
        └──► BM25IndexManager.rebuildIndex()
```

### 3. Recording Deleted

```
User deletes recording
        │
        ▼
StorageService.deleteRecording()
        │
        ▼
SearchIndexService.removeRecording()
        │
        ├──► VectorStore.removeChunks()
        │
        └──► BM25IndexManager.invalidate()
```

## Performance Characteristics

### Change Detection
- **Hash computation:** ~1ms per recording
- **Hash comparison:** ~0.1ms per recording
- **Typical full sync scan:** <100ms for 1000 recordings

### Indexing
- **Chunking:** ~50-100ms per recording (depends on transcript length)
- **Embedding:** ~200-400ms per chunk (depends on platform)
- **Vector storage:** ~10-20ms per recording
- **Total per recording:** ~500ms average

### BM25 Rebuild
- **Full rebuild:** ~500ms for 1000 recordings
- **Memory usage:** ~5-10MB for 1000 recordings

## Storage

### Vector Store Database
- **Location:** `{supportDir}/search/vector_store.db`
- **Size:** ~10MB for 10,000 chunks (256 dimensions)
- **Format:** SQLite with BLOB embeddings
- **Gitignored:** Yes (rebuilt per device)

### Index Manifest
Stored in vector store database:

```sql
CREATE TABLE index_manifest (
  recording_id TEXT PRIMARY KEY,
  content_hash TEXT NOT NULL,      -- SHA-256 hash for change detection
  indexed_at TEXT NOT NULL,        -- ISO 8601 timestamp
  chunk_count INTEGER NOT NULL     -- Number of chunks indexed
)
```

## Riverpod Providers

### Core Providers

```dart
// Vector store
final vectorStoreProvider = Provider<VectorStore>

// Content hasher
final contentHasherProvider = Provider<ContentHasher>

// Recording chunker
final recordingChunkerProvider = Provider<RecordingChunker>

// Main orchestrator
final searchIndexServiceProvider = Provider<SearchIndexService>
```

### State Providers (for UI)

```dart
// Indexing status (idle, syncing, indexing, error)
final indexingStatusProvider = StateProvider<IndexingStatus>

// Progress (0.0 to 1.0)
final indexingProgressProvider = StateProvider<double>

// Error message
final indexingErrorProvider = StateProvider<String?>

// Total and indexed counts
final indexingTotalProvider = StateProvider<int>
final indexingCountProvider = StateProvider<int>
```

## Testing

### Unit Tests

- **ContentHasher:** 15 tests covering hash consistency, change detection, field handling
- **SearchIndexService:** 30+ tests covering:
  - New recording indexing
  - Modified recording re-indexing
  - Unchanged recording skipping
  - Deleted recording removal
  - Status updates and progress tracking
  - Concurrent sync handling
  - Error handling and recovery
  - Listener notifications

### Integration Points

The service is designed to work with mocked dependencies for testing:
- `MockVectorStore`
- `MockBM25IndexManager`
- `MockRecordingChunker`
- `MockStorageService`
- `MockContentHasher`

## Error Handling

### Graceful Degradation

1. **Individual recording failure:** Continue indexing other recordings
2. **Vector store error:** Log and set error status, allow retry
3. **BM25 rebuild failure:** Log but don't fail entire sync
4. **Listener error:** Log and continue (don't break other listeners)

### Recovery

- **Stuck in syncing state:** Concurrent sync requests wait for completion
- **Partial failure:** Re-run `syncIndexes()` to retry failed recordings
- **Corrupted index:** Use `forceFullReindex()` to rebuild from scratch

## Usage Examples

### App Initialization

```dart
class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // Non-blocking background sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final searchIndex = ref.read(searchIndexServiceProvider);
      searchIndex.syncIndexes(); // Fire and forget
    });
  }
}
```

### Recording Operations

```dart
// Save recording
await storageService.saveRecording(recording);
await searchIndex.indexRecording(recording); // Immediate indexing

// Delete recording
await storageService.deleteRecording(recordingId);
await searchIndex.removeRecording(recordingId);

// Edit recording
final updated = recording.copyWith(transcript: newTranscript);
await storageService.saveRecording(updated);
await searchIndex.indexRecording(updated); // Re-indexes automatically
```

### Progress Monitoring

```dart
class IndexingProgressWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(indexingStatusProvider);
    final progress = ref.watch(indexingProgressProvider);

    if (status == IndexingStatus.indexing) {
      return LinearProgressIndicator(value: progress);
    } else if (status == IndexingStatus.error) {
      final error = ref.watch(indexingErrorProvider);
      return Text('Error: $error', style: TextStyle(color: Colors.red));
    } else {
      return SizedBox.shrink();
    }
  }
}
```

## Future Optimizations

### Batch Processing
- Process multiple recordings in parallel using isolates
- Implement work-stealing queue for better CPU utilization

### Incremental Indexing
- Track which chunks changed (not just which recordings)
- Only re-embed changed chunks

### Approximate Nearest Neighbor
- Implement LSH (Locality-Sensitive Hashing) for large datasets
- IVF (Inverted File) indexing for faster search

### Delta Sync
- Track file system events for real-time indexing
- Debounce rapid changes to avoid excessive re-indexing

## Debugging

### Enable Debug Logging

All components use `debugPrint` with prefixes:
- `[SearchIndex]` - Main orchestrator
- `[VectorStore]` - Vector storage operations
- `[BM25IndexManager]` - BM25 index operations
- `[RecordingChunker]` - Chunking operations

### Check Index Status

```dart
final stats = await searchIndex.getStats();
print('Vector Store: ${stats['vectorStore']}');
print('BM25: ${stats['bm25']}');
print('Status: ${stats['status']}');
```

### Manual Inspection

```sql
-- Open vector store database
sqlite3 {supportDir}/search/vector_store.db

-- Check manifest
SELECT * FROM index_manifest;

-- Count chunks
SELECT recording_id, COUNT(*) as chunks
FROM chunks
GROUP BY recording_id;

-- Check for orphaned chunks
SELECT DISTINCT recording_id
FROM chunks
WHERE recording_id NOT IN (SELECT recording_id FROM index_manifest);
```

## See Also

- [Vector Store](./vector_store.dart) - Vector storage interface
- [SQLite Vector Store](./sqlite_vector_store.dart) - SQLite implementation
- [BM25 Index Manager](./bm25_index_manager.dart) - BM25 lifecycle
- [Recording Chunker](./chunking/recording_chunker.dart) - Chunking service
- [Content Hasher](./content_hasher.dart) - Hash computation
