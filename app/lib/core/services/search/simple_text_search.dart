import 'package:flutter/foundation.dart';
import 'package:app/features/journal/services/journal_service.dart';
import 'package:app/features/chat/services/local_session_reader.dart';

/// Simple text search result
class SimpleSearchResult {
  /// Unique identifier for this result
  final String id;

  /// Type of content: 'journal' or 'chat'
  final String type;

  /// Title or identifier for display
  final String title;

  /// The matching text snippet
  final String snippet;

  /// The full text content (for "Ask AI" context)
  final String fullContent;

  /// Date associated with this content
  final DateTime date;

  /// Number of keyword matches
  final int matchCount;

  SimpleSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.snippet,
    required this.fullContent,
    required this.date,
    required this.matchCount,
  });
}

/// Simple text search service using keyword matching
///
/// Provides instant search across journals and chats without requiring
/// any model downloads or index building. Uses simple substring matching
/// with basic relevance scoring based on match count.
///
/// **Features:**
/// - No setup required - works immediately
/// - Searches journals and chat sessions
/// - Returns snippets with context around matches
/// - Basic relevance sorting by match count
///
/// **Limitations:**
/// - Only finds exact keyword matches (no semantic understanding)
/// - Performance scales linearly with vault size
/// - No fuzzy matching or stemming
class SimpleTextSearchService {
  final JournalService? _journalService;
  final LocalSessionReader? _sessionReader;

  SimpleTextSearchService({
    JournalService? journalService,
    LocalSessionReader? sessionReader,
  })  : _journalService = journalService,
        _sessionReader = sessionReader;

  /// Search across all content using keyword matching
  ///
  /// Returns results sorted by relevance (match count).
  Future<List<SimpleSearchResult>> search(
    String query, {
    int limit = 30,
    bool searchJournals = true,
    bool searchChats = true,
  }) async {
    if (query.trim().isEmpty) return [];

    final results = <SimpleSearchResult>[];
    final queryLower = query.toLowerCase();
    final queryTerms = queryLower
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 1)
        .toList();

    if (queryTerms.isEmpty) return [];

    debugPrint('[SimpleSearch] Searching for: "$query" (${queryTerms.length} terms)');
    final stopwatch = Stopwatch()..start();

    // Search journals and chats in parallel
    final futures = <Future<List<SimpleSearchResult>>>[];

    if (searchJournals && _journalService != null) {
      futures.add(_searchJournals(queryLower, queryTerms));
    }

    if (searchChats && _sessionReader != null) {
      futures.add(_searchChats(queryLower, queryTerms));
    }

    final allResults = await Future.wait(futures);
    for (final resultList in allResults) {
      results.addAll(resultList);
    }

    // Sort by match count (descending), then by date (newest first)
    results.sort((a, b) {
      final countCompare = b.matchCount.compareTo(a.matchCount);
      if (countCompare != 0) return countCompare;
      return b.date.compareTo(a.date);
    });

    stopwatch.stop();
    debugPrint(
      '[SimpleSearch] Found ${results.length} results in ${stopwatch.elapsedMilliseconds}ms',
    );

    return results.take(limit).toList();
  }

  /// Search journal entries (parallel loading for speed)
  Future<List<SimpleSearchResult>> _searchJournals(
    String queryLower,
    List<String> queryTerms,
  ) async {
    final results = <SimpleSearchResult>[];

    try {
      final journalService = _journalService!;
      final dates = await journalService.listJournalDates();

      // Load journals in parallel batches for speed
      const batchSize = 10;
      for (int i = 0; i < dates.length; i += batchSize) {
        final batch = dates.skip(i).take(batchSize).toList();
        final journals = await Future.wait(
          batch.map((date) => journalService.loadDay(date)),
        );

        for (int j = 0; j < journals.length; j++) {
          final date = batch[j];
          final journal = journals[j];

          for (final entry in journal.entries) {
            if (entry.id == 'preamble' || entry.content.isEmpty) continue;

            final contentLower = entry.content.toLowerCase();
            final matchCount = _countMatches(contentLower, queryTerms);

            if (matchCount > 0) {
              final snippet = _extractSnippet(entry.content, queryLower, queryTerms);
              final dateStr = _formatDate(date);

              results.add(SimpleSearchResult(
                id: 'journal:$dateStr:${entry.id}',
                type: 'journal',
                title: 'Journal $dateStr',
                snippet: snippet,
                fullContent: entry.content,
                date: date,
                matchCount: matchCount,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SimpleSearch] Error searching journals: $e');
    }

    return results;
  }

  /// Search chat sessions (parallel loading for speed)
  Future<List<SimpleSearchResult>> _searchChats(
    String queryLower,
    List<String> queryTerms,
  ) async {
    final results = <SimpleSearchResult>[];

    try {
      final sessions = await _sessionReader!.getLocalSessions();

      // Load sessions in parallel batches for speed
      const batchSize = 10;
      for (int i = 0; i < sessions.length; i += batchSize) {
        final batch = sessions.skip(i).take(batchSize).toList();
        final fullSessions = await Future.wait(
          batch.map((s) => _loadSessionWithMessages(s.id)),
        );

        for (int j = 0; j < fullSessions.length; j++) {
          final session = batch[j];
          final fullSession = fullSessions[j];
          if (fullSession == null) continue;

          // Combine all messages into searchable text
          final messagesText = fullSession.messages
              .map((m) => m.content)
              .join('\n');

          final contentLower = messagesText.toLowerCase();
          final matchCount = _countMatches(contentLower, queryTerms);

          if (matchCount > 0) {
            final snippet = _extractSnippet(messagesText, queryLower, queryTerms);

            results.add(SimpleSearchResult(
              id: 'chat:${session.id}',
              type: 'chat',
              title: session.title ?? 'Chat ${session.id.substring(0, 8)}',
              snippet: snippet,
              fullContent: messagesText,
              date: session.createdAt,
              matchCount: matchCount,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[SimpleSearch] Error searching chats: $e');
    }

    return results;
  }

  /// Load session with messages (reads markdown file)
  Future<ChatSessionWithLocalMessages?> _loadSessionWithMessages(String sessionId) async {
    try {
      return await _sessionReader!.getSession(sessionId);
    } catch (e) {
      debugPrint('[SimpleSearch] Error loading session $sessionId: $e');
      return null;
    }
  }

  /// Count how many query terms appear in the content
  int _countMatches(String contentLower, List<String> queryTerms) {
    int count = 0;
    for (final term in queryTerms) {
      // Count occurrences of this term
      int index = 0;
      while ((index = contentLower.indexOf(term, index)) != -1) {
        count++;
        index += term.length;
      }
    }
    return count;
  }

  /// Extract a snippet around the first match with context
  String _extractSnippet(
    String content,
    String queryLower,
    List<String> queryTerms,
  ) {
    final contentLower = content.toLowerCase();

    // Find first match position
    int firstMatchPos = content.length;
    for (final term in queryTerms) {
      final pos = contentLower.indexOf(term);
      if (pos != -1 && pos < firstMatchPos) {
        firstMatchPos = pos;
      }
    }

    if (firstMatchPos >= content.length) {
      // No match found (shouldn't happen), return beginning
      return content.substring(0, content.length.clamp(0, 200));
    }

    // Extract context around the match
    const contextChars = 80;
    final start = (firstMatchPos - contextChars).clamp(0, content.length);
    final end = (firstMatchPos + contextChars + 50).clamp(0, content.length);

    var snippet = content.substring(start, end);

    // Clean up the snippet
    snippet = snippet.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    // Add ellipsis if truncated
    if (start > 0) snippet = '...$snippet';
    if (end < content.length) snippet = '$snippet...';

    return snippet;
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
