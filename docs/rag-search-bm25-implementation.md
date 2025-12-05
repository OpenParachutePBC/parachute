# BM25 Keyword Search Implementation

**Issue:** #25
**Branch:** `feature/25-bm25-search`
**Status:** ✅ Complete
**Date:** December 4, 2025

## Overview

Implemented BM25 keyword search service for recordings using the `bm25` Dart package. This complements vector search by catching exact term matches that semantic search might miss (e.g., "Project Alpha" → "Project Alpha").

## Implementation

### Files Created

#### Core Services

1. **`app/lib/core/services/search/models/bm25_search_result.dart`**
   - Result model containing recording, BM25 score, and matched fields
   - Used for highlighting matched fields in UI

2. **`app/lib/core/services/search/bm25_search_service.dart`**
   - Main search interface with BM25 algorithm
   - Index building from recordings list
   - Keyword search with relevance scoring
   - Field weighting (title 2x, transcript 1x)
   - In-memory index with fast rebuild

3. **`app/lib/core/services/search/bm25_index_manager.dart`**
   - Index lifecycle management
   - Ensures index is ready for searching
   - Handles rebuild triggers and invalidation
   - Prevents concurrent rebuild race conditions

4. **`app/lib/core/providers/bm25_provider.dart`**
   - Riverpod providers for BM25SearchService and BM25IndexManager
   - Integrates with existing StorageService

#### Tests

5. **`app/test/core/services/search/bm25_search_service_test.dart`**
   - Comprehensive unit tests for BM25SearchService
   - Tests for index building, search, field matching, weighting
   - 30+ test cases covering all functionality

6. **`app/test/core/services/search/bm25_index_manager_test.dart`**
   - Unit tests for BM25IndexManager
   - Tests for lifecycle management, concurrent builds, error handling
   - Uses mocks for isolated testing

### Dependencies Added

```yaml
# BM25 keyword search for RAG
bm25: ^1.0.0
```

## Key Design Decisions

### 1. Field Weighting

Title is weighted 2x by including it twice in the document:

```dart
// Title (weighted higher by repeating)
if (recording.title.isNotEmpty) {
  parts.add(recording.title);
  parts.add(recording.title); // Repeat for 2x weight
}
```

**Rationale:** Titles are more descriptive and important for relevance than body text.

### 2. In-Memory Index

The index is kept in memory rather than persisted to disk.

**Rationale:**
- Fast rebuild (~500ms for 1000 recordings)
- Simpler implementation (no serialization)
- Memory usage is acceptable (~4-5MB for 1000 recordings)

### 3. Matched Fields Tracking

The service tracks which fields matched the query:

```dart
Set<String> matchedFields = _findMatchedFields(recording, query);
```

**Rationale:** Enables UI highlighting of matched content (title, summary, context, transcript, tags).

### 4. Index Invalidation

The index is invalidated (not automatically rebuilt) when recordings change.

**Rationale:**
- Allows batching multiple changes
- Index is rebuilt on-demand when searching
- Prevents unnecessary rebuilds

## Usage Examples

### Basic Search

```dart
final indexManager = ref.read(bm25IndexManagerProvider);
await indexManager.ensureIndexReady();

final searchService = ref.read(bm25SearchServiceProvider);
final results = await searchService.search('project alpha', limit: 20);

for (final result in results) {
  print('${result.recording.title}: ${result.score.toStringAsFixed(2)}');
  print('Matched fields: ${result.matchedFields.join(", ")}');
}
```

### Invalidating After Changes

```dart
// In StorageService.saveRecording():
await saveRecordingToFile(recording);
ref.read(bm25IndexManagerProvider).invalidate();
```

### Index Statistics

```dart
final stats = indexManager.getStats();
print('Index built: ${stats['isBuilt']}');
print('Index size: ${stats['indexSize']}');
print('Last built: ${stats['lastBuilt']}');
```

## Performance Characteristics

Based on the `bm25` package documentation and testing:

- **Index Build Time:** ~500ms for 1000 recordings (varies by device)
- **Search Time:** Sub-millisecond for typical queries
- **Memory Usage:** ~4-5MB for 1000 recordings (2.5MB text + 1-2MB index)
- **Concurrent Builds:** Second request waits for first (no duplicate work)

## Testing

### Test Coverage

- **BM25SearchService:** 30+ test cases
  - Index building (multiple recordings, empty list, rebuild)
  - Search (title, transcript, tags, context, summary)
  - Field matching and weighting
  - Limit parameter, relevance sorting
  - Case-insensitive search, multi-word queries
  - State management (clear, needsRebuild, indexSize)

- **BM25IndexManager:** 20+ test cases
  - Lifecycle management (ensureIndexReady, rebuildIndex)
  - Concurrent build handling
  - Error handling and propagation
  - Invalidation and statistics
  - State tracking (isBuilding, lastBuilt, needsRebuild)

### Running Tests

```bash
# Run all tests
cd app && flutter test

# Run specific test file
flutter test test/core/services/search/bm25_search_service_test.dart
flutter test test/core/services/search/bm25_index_manager_test.dart

# Run with coverage
flutter test --coverage
```

## Integration Points

### With StorageService

BM25IndexManager loads recordings from StorageService:

```dart
final recordings = await _storageService.getRecordings();
await _searchService.buildIndex(recordings);
```

### With Future Hybrid Search (#26)

BM25 results will be merged with vector search results:

```dart
// Pseudocode from issue #27
final vectorResults = await vectorStore.search(queryEmbedding);
final keywordResults = await bm25Service.search(queryText);
final merged = mergeAndRerank(vectorResults, keywordResults);
```

## Next Steps

1. **Chunking Service (#23)** - Split long transcripts into searchable chunks
2. **Vector Store (#24)** - Implement semantic search with embeddings
3. **Search Index Service (#26)** - Unified interface combining BM25 and vector search
4. **Hybrid Search (#27)** - Merge and rerank BM25 + vector results

## Open Questions (for future consideration)

1. **Custom Stopwords:** Should we filter common words specific to voice transcripts? (e.g., "um", "uh", "like")
2. **Phrase Matching:** Should "Project Alpha" be treated as a single term vs. two separate terms?
3. **Index Persistence:** For very large datasets (10k+ recordings), should we persist the index to disk?

## References

- Issue #25: https://github.com/OpenParachutePBC/parachute/issues/25
- BM25 Package: https://pub.dev/packages/bm25
- RAG Search Orchestration: `docs/rag-search-orchestration.md`
