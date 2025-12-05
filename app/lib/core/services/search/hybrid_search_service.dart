import 'package:flutter/foundation.dart';
import 'package:app/core/services/search/vector_store.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';
import 'package:app/core/services/search/models/bm25_search_result.dart';
import 'package:app/core/services/search/models/search_result.dart';
import 'package:app/features/recorder/services/storage_service.dart';

/// Hybrid search service combining vector and keyword search
///
/// Provides unified search by combining:
/// - **Vector search** - Semantic similarity using embeddings
/// - **BM25 search** - Keyword matching using BM25 algorithm
///
/// Results are merged using **Reciprocal Rank Fusion (RRF)**, which elegantly
/// combines rankings from both methods without needing to normalize scores.
///
/// **Why Hybrid Search?**
///
/// | Query | Vector Search | BM25 Search | Hybrid |
/// |-------|---------------|-------------|--------|
/// | "feeling overwhelmed" | ✅ Finds "stressed out" | ❌ Misses semantic match | ✅ |
/// | "Project Alpha" | ❌ May miss exact term | ✅ Exact match | ✅ |
/// | "meeting about budgets" | ✅ Semantic context | ✅ Keyword "meeting" | ✅ Best of both |
///
/// **RRF Algorithm:**
/// ```
/// RRF_score(doc) = Σ 1 / (k + rank)
/// ```
/// Where k=60 is a constant that controls weight distribution.
///
/// **Example:**
/// ```dart
/// final hybridSearch = HybridSearchService(
///   vectorStore,
///   bm25Service,
///   embeddingService,
///   storageService,
/// );
///
/// final results = await hybridSearch.search(
///   'project alpha meeting',
///   limit: 20,
/// );
///
/// for (final result in results) {
///   print('${result.recording.title}: ${result.relevanceLabel}');
///   print('  RRF: ${result.rrfScore.toStringAsFixed(4)}');
///   if (result.isBothMatch) {
///     print('  ✓ Found by both vector and keyword search');
///   }
/// }
/// ```
class HybridSearchService {
  final VectorStore _vectorStore;
  final BM25SearchService _bm25Service;
  final EmbeddingService _embeddingService;
  final StorageService _storageService;

  static const int _defaultLimit = 20;
  static const double _rrfK = 60.0; // RRF constant

  HybridSearchService(
    this._vectorStore,
    this._bm25Service,
    this._embeddingService,
    this._storageService,
  );

  /// Perform hybrid search combining vector and keyword search
  ///
  /// **Parameters:**
  /// - [query] - Search query (e.g., "project alpha meeting")
  /// - [limit] - Maximum number of results to return (default: 20)
  ///
  /// **Returns:** List of [SearchResult] sorted by relevance (highest first)
  ///
  /// **Process:**
  /// 1. Embed the query for vector search
  /// 2. Run vector and BM25 searches in parallel (2x limit for better merging)
  /// 3. Merge results using Reciprocal Rank Fusion (RRF)
  /// 4. Deduplicate by recording ID (keep highest scored)
  /// 5. Enrich with full Recording objects
  /// 6. Return top N results
  ///
  /// **Throws:**
  /// - [StateError] if BM25 index not built
  /// - [Exception] if embedding fails
  /// - [SearchException] if both search methods fail
  Future<List<SearchResult>> search(
    String query, {
    int limit = _defaultLimit,
  }) async {
    if (query.trim().isEmpty) {
      debugPrint('[HybridSearch] Empty query, returning empty results');
      return [];
    }

    debugPrint('[HybridSearch] Searching for: "$query" (limit: $limit)');
    final stopwatch = Stopwatch()..start();

    List<VectorSearchResult>? vectorResults;
    List<BM25SearchResult>? keywordResults;

    // Try vector search
    try {
      debugPrint('[HybridSearch] Embedding query...');
      final queryEmbedding = await _embeddingService.embed(query);
      debugPrint('[HybridSearch] Running vector search...');
      vectorResults = await _vectorStore.search(
        queryEmbedding,
        limit: limit * 2, // Get more for better merging
      );
      debugPrint('[HybridSearch] Vector search: ${vectorResults.length} results');
    } catch (e) {
      debugPrint('[HybridSearch] Vector search failed: $e');
      // Continue with keyword only
    }

    // Try keyword search
    try {
      debugPrint('[HybridSearch] Running BM25 search...');
      keywordResults = await _bm25Service.search(
        query,
        limit: limit * 2, // Get more for better merging
      );
      debugPrint('[HybridSearch] BM25 search: ${keywordResults.length} results');
    } catch (e) {
      debugPrint('[HybridSearch] Keyword search failed: $e');
      // Continue with vector only
    }

    // Handle fallback cases
    if (vectorResults == null && keywordResults == null) {
      throw SearchException('Both search methods failed');
    }

    List<SearchResult> results;
    if (vectorResults == null) {
      debugPrint('[HybridSearch] Fallback: keyword-only results');
      results = await _keywordOnlyResults(keywordResults!, limit);
    } else if (keywordResults == null) {
      debugPrint('[HybridSearch] Fallback: vector-only results');
      results = await _vectorOnlyResults(vectorResults, limit);
    } else {
      // Both succeeded - merge with RRF
      debugPrint('[HybridSearch] Merging results with RRF...');
      results = await _mergeResults(vectorResults, keywordResults, limit);
    }

    stopwatch.stop();
    debugPrint(
      '[HybridSearch] Search complete: ${results.length} results in ${stopwatch.elapsedMilliseconds}ms',
    );

    return results;
  }

  /// Merge vector and keyword results using Reciprocal Rank Fusion
  Future<List<SearchResult>> _mergeResults(
    List<VectorSearchResult> vectorResults,
    List<BM25SearchResult> keywordResults,
    int limit,
  ) async {
    debugPrint('[HybridSearch] Merging ${vectorResults.length} vector + ${keywordResults.length} keyword results');

    // Compute RRF scores
    final merged = _computeRRFScores(vectorResults, keywordResults);

    // Sort by RRF score descending
    merged.sort((a, b) => b.rrfScore.compareTo(a.rrfScore));

    // Deduplicate by recording ID (keep highest scored)
    final deduplicated = _deduplicateByRecording(merged);

    debugPrint('[HybridSearch] After deduplication: ${deduplicated.length} unique recordings');

    // Enrich with full Recording objects
    final enriched = await _enrichResults(deduplicated);

    // Return top N
    final topResults = enriched.take(limit).toList();

    if (topResults.isNotEmpty) {
      debugPrint(
        '[HybridSearch] Top result: ${topResults.first.recording.title} '
        '(RRF: ${topResults.first.rrfScore.toStringAsFixed(4)}, '
        'bothMatch: ${topResults.first.isBothMatch})',
      );
    }

    return topResults;
  }

  /// Compute RRF scores for merged results
  ///
  /// RRF formula: score = 1 / (k + rank)
  /// where k = 60 (constant), rank starts at 0
  List<_MergedResult> _computeRRFScores(
    List<VectorSearchResult> vectorResults,
    List<BM25SearchResult> keywordResults,
  ) {
    final scores = <String, _MergedResult>{};

    // Score vector results (by chunk)
    for (int rank = 0; rank < vectorResults.length; rank++) {
      final r = vectorResults[rank];
      final key = '${r.recordingId}:${r.field}:${r.chunkIndex}';

      scores.putIfAbsent(
        key,
        () => _MergedResult(
          recordingId: r.recordingId,
          field: r.field,
          chunkIndex: r.chunkIndex,
          chunkText: r.chunkText,
        ),
      );

      final rrfContribution = 1.0 / (_rrfK + rank);
      scores[key]!.rrfScore += rrfContribution;
      scores[key]!.vectorScore = r.score;
      scores[key]!.vectorRank = rank;

      debugPrint(
        '[HybridSearch] Vector[$rank]: ${r.recordingId} (${r.field}:${r.chunkIndex}) '
        '+${rrfContribution.toStringAsFixed(6)} → ${scores[key]!.rrfScore.toStringAsFixed(6)}',
      );
    }

    // Score BM25 results (full recording)
    for (int rank = 0; rank < keywordResults.length; rank++) {
      final r = keywordResults[rank];
      final key = '${r.recording.id}:full:0';

      scores.putIfAbsent(
        key,
        () => _MergedResult(
          recordingId: r.recording.id,
          field: 'full',
          chunkIndex: 0,
          chunkText: null, // Full recording match
        ),
      );

      final rrfContribution = 1.0 / (_rrfK + rank);
      scores[key]!.rrfScore += rrfContribution;
      scores[key]!.keywordScore = r.score;
      scores[key]!.keywordRank = rank;
      scores[key]!.matchedFields = r.matchedFields;

      debugPrint(
        '[HybridSearch] BM25[$rank]: ${r.recording.id} '
        '+${rrfContribution.toStringAsFixed(6)} → ${scores[key]!.rrfScore.toStringAsFixed(6)}',
      );
    }

    return scores.values.toList();
  }

  /// Deduplicate results by recording ID
  ///
  /// When the same recording appears multiple times (e.g., multiple chunks
  /// from vector search, plus full recording from BM25), merge the scores
  /// and keep the best chunk text for display.
  List<_MergedResult> _deduplicateByRecording(List<_MergedResult> results) {
    final merged = <String, _MergedResult>{};

    for (final result in results) {
      final existing = merged[result.recordingId];
      if (existing == null) {
        // First time seeing this recording
        merged[result.recordingId] = result;
      } else {
        // Merge scores from this result into existing
        // Keep the higher RRF score as the base
        if (result.rrfScore > existing.rrfScore) {
          // New result has higher RRF score - copy its chunk text
          existing.chunkText = result.chunkText ?? existing.chunkText;
          existing.field = result.field;
          existing.chunkIndex = result.chunkIndex;
        }
        // Accumulate RRF scores from all entries for this recording
        existing.rrfScore += result.rrfScore;
        // Copy over vector scores if this entry has them
        if (result.vectorScore != null && existing.vectorScore == null) {
          existing.vectorScore = result.vectorScore;
          existing.vectorRank = result.vectorRank;
        }
        // Copy over keyword scores if this entry has them
        if (result.keywordScore != null && existing.keywordScore == null) {
          existing.keywordScore = result.keywordScore;
          existing.keywordRank = result.keywordRank;
          existing.matchedFields = result.matchedFields;
        }
      }
    }

    // Sort by merged RRF score and return
    final deduplicated = merged.values.toList();
    deduplicated.sort((a, b) => b.rrfScore.compareTo(a.rrfScore));
    return deduplicated;
  }

  /// Enrich merged results with full Recording objects
  Future<List<SearchResult>> _enrichResults(List<_MergedResult> results) async {
    final enriched = <SearchResult>[];

    for (final r in results) {
      final recording = await _storageService.getRecording(r.recordingId);
      if (recording == null) {
        debugPrint('[HybridSearch] Warning: Recording ${r.recordingId} not found, skipping');
        continue;
      }

      enriched.add(SearchResult(
        recording: recording,
        matchedChunk: r.chunkText,
        matchedField: r.field,
        matchedFields: r.matchedFields ?? {},
        rrfScore: r.rrfScore,
        vectorScore: r.vectorScore,
        keywordScore: r.keywordScore,
        vectorRank: r.vectorRank,
        keywordRank: r.keywordRank,
      ));
    }

    return enriched;
  }

  /// Fallback: return vector-only results
  Future<List<SearchResult>> _vectorOnlyResults(
    List<VectorSearchResult> vectorResults,
    int limit,
  ) async {
    final results = <SearchResult>[];
    final seen = <String>{};

    for (int i = 0; i < vectorResults.length && results.length < limit; i++) {
      final r = vectorResults[i];

      // Skip if we already have this recording
      if (seen.contains(r.recordingId)) continue;
      seen.add(r.recordingId);

      final recording = await _storageService.getRecording(r.recordingId);
      if (recording == null) continue;

      // RRF score with only one ranking
      final rrfScore = 1.0 / (_rrfK + i);

      results.add(SearchResult(
        recording: recording,
        matchedChunk: r.chunkText,
        matchedField: r.field,
        matchedFields: {},
        rrfScore: rrfScore,
        vectorScore: r.score,
        keywordScore: null,
        vectorRank: i,
        keywordRank: null,
      ));
    }

    return results;
  }

  /// Fallback: return keyword-only results
  Future<List<SearchResult>> _keywordOnlyResults(
    List<BM25SearchResult> keywordResults,
    int limit,
  ) async {
    final results = <SearchResult>[];

    for (int i = 0; i < keywordResults.length && i < limit; i++) {
      final r = keywordResults[i];

      // RRF score with only one ranking
      final rrfScore = 1.0 / (_rrfK + i);

      results.add(SearchResult(
        recording: r.recording,
        matchedChunk: null,
        matchedField: 'full',
        matchedFields: r.matchedFields,
        rrfScore: rrfScore,
        vectorScore: null,
        keywordScore: r.score,
        vectorRank: null,
        keywordRank: i,
      ));
    }

    return results;
  }
}

/// Internal class for merging search results before enrichment
class _MergedResult {
  final String recordingId;
  String field;
  int chunkIndex;
  String? chunkText;

  double rrfScore = 0.0;
  double? vectorScore;
  double? keywordScore;
  int? vectorRank;
  int? keywordRank;
  Set<String>? matchedFields;

  _MergedResult({
    required this.recordingId,
    required this.field,
    required this.chunkIndex,
    this.chunkText,
  });

  @override
  String toString() {
    return '_MergedResult($recordingId, $field:$chunkIndex, rrf=${rrfScore.toStringAsFixed(4)})';
  }
}

/// Exception thrown when search operations fail
class SearchException implements Exception {
  final String message;

  SearchException(this.message);

  @override
  String toString() => 'SearchException: $message';
}
