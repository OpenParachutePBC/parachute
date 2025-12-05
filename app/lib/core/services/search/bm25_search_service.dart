import 'package:flutter/foundation.dart';
import 'package:bm25/bm25.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/search/models/bm25_search_result.dart';

/// BM25 keyword search service for recordings
///
/// Provides fast keyword-based search using the BM25 ranking algorithm.
/// Complements vector search by catching exact term matches that semantic
/// search might miss (e.g., "Project Alpha" → "Project Alpha").
///
/// **Field Weighting:**
/// - Title: 2x weight (by including twice in document)
/// - Summary: 1x weight
/// - Context: 1x weight
/// - Tags: 1x weight
/// - Transcript: 1x weight
///
/// **Index Management:**
/// - In-memory index (fast to rebuild)
/// - Rebuild from recordings list when needed
/// - Typically <1s for 1000 recordings
///
/// **Usage:**
/// ```dart
/// final service = BM25SearchService();
/// await service.buildIndex(recordings);
/// final results = await service.search('project alpha', limit: 20);
/// ```
class BM25SearchService {
  BM25? _index;
  List<Recording>? _indexedRecordings;
  bool _indexBuilt = false;

  /// Build or rebuild the BM25 index from recordings
  ///
  /// Creates searchable text documents from each recording and builds
  /// the BM25 index. This should be called:
  /// - On app startup
  /// - After recordings are added/updated/deleted
  /// - When user triggers refresh
  ///
  /// Performance: ~500ms for 1000 recordings (varies by device)
  Future<void> buildIndex(List<Recording> recordings) async {
    debugPrint('[BM25Search] Building index for ${recordings.length} recordings...');
    final stopwatch = Stopwatch()..start();

    _indexedRecordings = recordings;

    // Handle empty recordings list - BM25 package requires at least one document
    if (recordings.isEmpty) {
      _index = null; // No index needed for empty corpus
      _indexedRecordings = [];
      _indexBuilt = true; // Mark as built (no rebuild needed)
      debugPrint('[BM25Search] Index built (empty) in ${stopwatch.elapsedMilliseconds}ms');
      return;
    }

    // Create searchable documents from recordings
    final documents = recordings.map((r) => _recordingToDocument(r)).toList();

    // Build BM25 index
    // Note: BM25 package uses isolates for parallel processing
    _index = await BM25.build(documents);
    _indexBuilt = true;

    stopwatch.stop();
    debugPrint(
      '[BM25Search] Index built in ${stopwatch.elapsedMilliseconds}ms '
      '(${recordings.length} recordings)',
    );
  }

  /// Convert recording to searchable text document
  ///
  /// Concatenates all searchable fields into a single text document.
  /// Title is included twice to give it 2x weight in search results.
  String _recordingToDocument(Recording recording) {
    final parts = <String>[];

    // Title (weighted higher by repeating)
    if (recording.title.isNotEmpty) {
      parts.add(recording.title);
      parts.add(recording.title); // Repeat for 2x weight
    }

    // Summary
    if (recording.summary.isNotEmpty) {
      parts.add(recording.summary);
    }

    // Context
    if (recording.context.isNotEmpty) {
      parts.add(recording.context);
    }

    // Tags (as searchable text)
    if (recording.tags.isNotEmpty) {
      parts.add(recording.tags.join(' '));
    }

    // Transcript (main content)
    if (recording.transcript.isNotEmpty) {
      parts.add(recording.transcript);
    }

    return parts.join('\n');
  }

  /// Search for recordings matching query
  ///
  /// Returns results sorted by BM25 relevance score (highest first).
  ///
  /// **Parameters:**
  /// - [query]: Search terms (e.g., "project alpha meeting")
  /// - [limit]: Max number of results to return (default: 20)
  ///
  /// **Returns:** List of [BM25SearchResult] with scores and matched fields
  ///
  /// **Throws:** [StateError] if index not built
  ///
  /// **Example:**
  /// ```dart
  /// final results = await service.search('project alpha', limit: 10);
  /// for (final result in results) {
  ///   print('${result.recording.title}: ${result.score}');
  ///   print('Matched fields: ${result.matchedFields.join(", ")}');
  /// }
  /// ```
  Future<List<BM25SearchResult>> search(
    String query, {
    int limit = 20,
  }) async {
    if (!_indexBuilt) {
      throw StateError('Index not built. Call buildIndex() first.');
    }

    // Handle empty index (built with empty recordings)
    if (_index == null || _indexedRecordings == null || _indexedRecordings!.isEmpty) {
      debugPrint('[BM25Search] Empty index, returning empty results');
      return [];
    }

    if (query.trim().isEmpty) {
      debugPrint('[BM25Search] Empty query, returning empty results');
      return [];
    }

    debugPrint('[BM25Search] Searching for: "$query" (limit: $limit)');
    final stopwatch = Stopwatch()..start();

    // Perform BM25 search
    final searchResults = await _index!.search(query, limit: limit);

    // Convert to BM25SearchResult with matched fields
    final results = <BM25SearchResult>[];
    for (final result in searchResults) {
      if (result.doc.id >= _indexedRecordings!.length) {
        debugPrint(
          '[BM25Search] Warning: Invalid docId ${result.doc.id}, skipping',
        );
        continue;
      }

      final recording = _indexedRecordings![result.doc.id];
      final matchedFields = _findMatchedFields(recording, query);

      results.add(BM25SearchResult(
        recording: recording,
        score: result.score,
        matchedFields: matchedFields,
      ));
    }

    stopwatch.stop();
    debugPrint(
      '[BM25Search] Found ${results.length} results in ${stopwatch.elapsedMilliseconds}ms',
    );

    return results;
  }

  /// Determine which fields contain the search terms
  ///
  /// Used for highlighting matched fields in the UI.
  /// Performs case-insensitive substring matching.
  Set<String> _findMatchedFields(Recording recording, String query) {
    // Tokenize query into terms (simple split on whitespace)
    final terms = query.toLowerCase().split(RegExp(r'\s+'));
    final matched = <String>{};

    for (final term in terms) {
      if (term.isEmpty) continue;

      if (recording.title.toLowerCase().contains(term)) {
        matched.add('title');
      }
      if (recording.summary.toLowerCase().contains(term)) {
        matched.add('summary');
      }
      if (recording.context.toLowerCase().contains(term)) {
        matched.add('context');
      }
      if (recording.transcript.toLowerCase().contains(term)) {
        matched.add('transcript');
      }
      if (recording.tags.any((t) => t.toLowerCase().contains(term))) {
        matched.add('tags');
      }
    }

    return matched;
  }

  /// Check if index needs rebuilding
  bool get needsRebuild => !_indexBuilt;

  /// Get number of indexed recordings
  int get indexSize => _indexedRecordings?.length ?? 0;

  /// Clear the index
  ///
  /// Frees memory and marks index as needing rebuild.
  /// Useful when switching contexts or resetting state.
  void clear() {
    debugPrint('[BM25Search] Clearing index');
    _index = null;
    _indexedRecordings = null;
    _indexBuilt = false;
  }
}
