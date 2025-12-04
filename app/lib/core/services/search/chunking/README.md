# Text Chunking Services

This directory contains services for chunking text into semantically coherent pieces for RAG search indexing.

## Overview

The chunking pipeline transforms voice recording transcripts into searchable chunks:

1. **SentenceSplitter** - Splits text into sentences with edge case handling
2. **SemanticChunker** - Groups sentences by semantic similarity
3. **RecordingChunker** - High-level interface for chunking recordings

## Architecture

```
Recording
    ↓
RecordingChunker
    ↓
SemanticChunker → EmbeddingService
    ↓                    ↓
SentenceSplitter    Embed sentences
    ↓                    ↓
Sentences           Find boundaries
    ↓                    ↓
Mean-pool embeddings ← Chunk
    ↓
List<IndexedChunk>
```

## Key Design Decisions

### No Wasted Embeddings

We embed sentences once, then:
- Use those embeddings to detect chunk boundaries (cosine similarity)
- Mean-pool them to create the final chunk embedding
- No need to re-embed the chunks separately

### Semantic Coherence

Instead of naive fixed-size chunking, we use semantic similarity to detect topic shifts:
- When adjacent sentence similarity drops below threshold → new chunk
- Preserves thought boundaries (don't split mid-idea)
- Better retrieval precision

### Size Constraints

Even with semantic boundaries, we enforce max token limits:
- Default: 500 tokens per chunk (~2000 characters)
- Force-split at sentence boundary if exceeded
- Prevents extremely long chunks that hurt retrieval

## Usage

### Basic Usage

```dart
final embeddingService = EmbeddingGemmaService(); // or OllamaEmbeddingService
final chunker = RecordingChunker(embeddingService);

final recording = await storageService.getRecording(recordingId);
final chunks = await chunker.chunkRecording(recording);

// chunks is List<IndexedChunk> ready for database insertion
for (final chunk in chunks) {
  await searchIndexService.indexChunk(chunk);
}
```

### Batch Processing

```dart
final recordings = await storageService.getRecordings();
final allChunks = await chunker.chunkRecordings(recordings);

// Index all chunks at once
await searchIndexService.indexChunks(allChunks);
```

### Custom Configuration

```dart
final chunker = RecordingChunker(
  embeddingService,
  similarityThreshold: 0.3,  // More aggressive splitting
  maxChunkTokens: 300,       // Smaller chunks
);
```

## Components

### SentenceSplitter

Splits text into sentences using punctuation rules.

**Edge Cases Handled:**
- Abbreviations (Dr., Mr., Mrs., etc.)
- Decimal numbers (3.14, 2.5)
- URLs and email addresses
- Multiple punctuation marks
- Quotes at end of sentence

**Example:**
```dart
final splitter = SentenceSplitter();
final sentences = splitter.split('Dr. Smith called. He wants to talk.');
// ['Dr. Smith called.', 'He wants to talk.']
```

### SemanticChunker

Groups sentences by semantic similarity using embeddings.

**Parameters:**
- `similarityThreshold` (default: 0.5) - Lower = more chunks, higher = fewer chunks
  - 0.3 = Aggressive splitting
  - 0.5 = Balanced
  - 0.7 = Conservative
- `maxChunkTokens` (default: 500) - Soft limit on chunk size

**Algorithm:**
1. Split text into sentences
2. Embed all sentences (batch for efficiency)
3. Find chunk boundaries where similarity drops below threshold
4. Mean-pool sentence embeddings to create chunk embeddings

**Example:**
```dart
final chunker = SemanticChunker(embeddingService);
final chunks = await chunker.chunkTranscript(transcript);

for (final chunk in chunks) {
  print('Chunk: ${chunk.text}');
  print('Tokens: ${chunk.tokenCount}');
  print('Sentences: ${chunk.sentenceRange}');
}
```

### RecordingChunker

High-level interface for chunking entire recordings.

**What it chunks:**
- **Transcript** - Multiple chunks (semantically segmented)
- **Title** - Single chunk
- **Summary** - Single chunk (if present)
- **Context** - Single chunk (if present)

**Returns:** `List<IndexedChunk>` ready for database insertion

**Example:**
```dart
final chunker = RecordingChunker(embeddingService);
final chunks = await chunker.chunkRecording(recording);

// Chunks are organized by field
final transcriptChunks = chunks.where((c) => c.field == 'transcript');
final titleChunk = chunks.firstWhere((c) => c.field == 'title');
```

## Testing

### Unit Tests

All components have comprehensive unit tests:

```bash
cd app
flutter test test/core/services/search/chunking/
```

**Test Coverage:**
- `sentence_splitter_test.dart` - 30+ edge cases
- `semantic_chunker_test.dart` - Mock embedding service
- `recording_chunker_test.dart` - End-to-end chunking

### Mock Embedding Service

Tests use `MockEmbeddingService` to avoid model dependencies:

```dart
class MockEmbeddingService implements EmbeddingService {
  @override
  Future<List<double>> embed(String text) async {
    // Generate deterministic embedding based on text hash
    final seed = text.hashCode.abs();
    final embedding = List<double>.generate(256, (i) {
      return ((seed + i * 17) % 1000) / 1000.0 - 0.5;
    });
    return _normalize(embedding);
  }
  // ... other methods
}
```

## Performance Considerations

### Batch Embedding

Always embed sentences in batch for efficiency:

```dart
// ✅ Good - batch embedding
final embeddings = await embeddingService.embedBatch(sentences);

// ❌ Bad - sequential embedding
for (final sentence in sentences) {
  final embedding = await embeddingService.embed(sentence);
}
```

### Typical Performance

For a 5-minute recording (~500 words, ~30 sentences):
- Sentence embedding: 30 × 50ms = 1.5 seconds
- Chunking overhead: ~100ms
- Total: ~1.6 seconds

This is acceptable for background indexing.

### Scaling to Large Corpora

For indexing many recordings:
- Use `chunkRecordings()` batch method
- Consider isolate-based parallelism
- Add progress reporting
- Support cancellation

## Chunk Size Recommendations

Based on testing with voice transcripts:

| Tokens | Characters | Use Case |
|--------|-----------|----------|
| 200-300 | 800-1200 | High precision, more chunks |
| 400-600 | 1600-2400 | Balanced (recommended) |
| 700-1000 | 2800-4000 | Fewer chunks, may lose precision |

**Recommendation:** Start with default 500 tokens, tune based on retrieval quality.

## Similarity Threshold Tuning

The threshold affects semantic coherence vs chunk count:

| Threshold | Behavior | Use Case |
|-----------|----------|----------|
| 0.3-0.4 | Aggressive splitting | Short, focused chunks |
| 0.5-0.6 | Balanced | General use (recommended) |
| 0.7-0.8 | Conservative | Longer, more context |

**Recommendation:** Start with 0.5, tune based on search results.

## Future Enhancements

### Potential Improvements

1. **VAD Integration** - Use voice activity detection segments as chunking hints
2. **Multi-language Support** - Language-specific sentence splitting rules
3. **Overlap Strategy** - Add configurable overlap between chunks for context preservation
4. **Hierarchical Chunking** - Create chunk hierarchies (paragraph → sentence)
5. **Custom Boundary Hints** - Allow manual chunk boundaries in transcript

### Known Limitations

1. **Voice Transcript Specific** - Optimized for voice, not complex documents
2. **No Paragraph Detection** - Treats all text as continuous
3. **Simple Token Estimation** - Uses 1 token ≈ 4 characters heuristic
4. **No Caching** - Re-chunks on every call (consider caching for production)

## References

- **Matryoshka Embeddings:** https://arxiv.org/abs/2205.13147
- **Semantic Chunking:** https://python.langchain.com/docs/modules/data_connection/document_transformers/semantic-chunker
- **RAG Best Practices:** https://www.pinecone.io/learn/chunking-strategies/

## Related Files

- `app/lib/core/services/embedding/embedding_service.dart` - Embedding interface
- `app/lib/core/services/search/models/indexed_chunk.dart` - Chunk model
- `app/lib/features/recorder/models/recording.dart` - Recording model
- `docs/rag-search-orchestration.md` - Overall RAG architecture

## Support

For questions or issues, see:
- GitHub Issue #23 (this implementation)
- RAG Search Epic documentation
- `CLAUDE.md` in project root
