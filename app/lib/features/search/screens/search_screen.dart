import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/core/providers/vector_store_provider.dart';
import 'package:app/core/providers/search_providers.dart' hide localSessionReaderProvider;
import 'package:app/core/services/search/search_index_service.dart';
import 'package:app/core/services/search/models/vector_search_result.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/chat/providers/chat_providers.dart';
import 'package:app/features/chat/screens/chat_screen.dart';
import 'package:app/features/journal/providers/journal_providers.dart';

/// Search mode enum
enum SearchMode {
  keyword, // Simple text search (default, no model needed)
  semantic, // Vector search (requires embedding model + index)
}

/// Search screen for vault content
///
/// Supports two modes:
/// - **Keyword**: Simple text matching, works immediately, no setup required
/// - **Semantic**: AI-powered search, requires embedding model download and indexing
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  // Search mode - default to keyword (no setup required)
  SearchMode _searchMode = SearchMode.keyword;

  // Search results (unified for both modes)
  List<dynamic>? _results; // Can be SimpleSearchResult or VectorSearchResult
  bool _isSearching = false;
  String? _error;
  int? _searchTimeMs;

  // For semantic search stats
  Map<String, dynamic>? _stats;
  bool _isLoadingStats = true;
  bool _isVectorStoreReady = false;

  // For embedding model status (semantic mode only)
  bool _isEmbeddingReady = false;
  bool _isCheckingEmbedding = true;
  bool _isDownloadingEmbedding = false;
  double _embeddingDownloadProgress = 0.0;
  String? _embeddingError;

  // For listening to search index changes
  SearchIndexService? _searchIndex;
  VoidCallback? _indexingListener;

  @override
  void initState() {
    super.initState();
    _checkEmbeddingStatus();
    _waitForVectorStore();
    _setupIndexingListener();
  }

  @override
  void dispose() {
    _removeIndexingListener();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Set up listener for search index status changes
  void _setupIndexingListener() async {
    try {
      final searchIndex = await ref.read(configuredSearchIndexProvider.future);
      if (!mounted) return;

      _searchIndex = searchIndex;
      _indexingListener = () {
        if (mounted) {
          setState(() {}); // Trigger rebuild when indexing status changes
        }
      };
      searchIndex.addListener(_indexingListener!);
    } catch (e) {
      debugPrint('[SearchScreen] Error setting up indexing listener: $e');
    }
  }

  /// Remove the indexing listener
  void _removeIndexingListener() {
    if (_searchIndex != null && _indexingListener != null) {
      _searchIndex!.removeListener(_indexingListener!);
    }
  }

  /// Check if embedding model is ready
  Future<void> _checkEmbeddingStatus() async {
    try {
      final embeddingService = ref.read(embeddingServiceProvider);
      final isReady = await embeddingService.isReady();

      if (mounted) {
        setState(() {
          _isEmbeddingReady = isReady;
          _isCheckingEmbedding = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmbeddingReady = false;
          _isCheckingEmbedding = false;
          _embeddingError = e.toString();
        });
      }
    }
  }

  /// Download the embedding model
  Future<void> _downloadEmbeddingModel() async {
    if (_isDownloadingEmbedding) return;

    setState(() {
      _isDownloadingEmbedding = true;
      _embeddingDownloadProgress = 0.0;
      _embeddingError = null;
    });

    try {
      final embeddingService = ref.read(embeddingServiceProvider);

      await for (final progress in embeddingService.downloadModel()) {
        if (mounted) {
          setState(() {
            _embeddingDownloadProgress = progress;
          });
        }
      }

      if (mounted) {
        setState(() {
          _isDownloadingEmbedding = false;
          _isEmbeddingReady = true;
        });

        // Trigger search index sync now that embedding is ready
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Embedding model ready! Starting indexing...'),
            duration: Duration(seconds: 3),
          ),
        );

        // Actually trigger the indexing
        _triggerSearchIndexSync();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingEmbedding = false;
          _embeddingError = e.toString();
        });
      }
    }
  }

  /// Trigger search index sync after embedding model is downloaded
  Future<void> _triggerSearchIndexSync() async {
    try {
      debugPrint('[SearchScreen] Triggering search index sync after model download...');

      // Get the configured search index (with journal support)
      final searchIndex = await ref.read(configuredSearchIndexProvider.future);

      // Run indexing in background
      debugPrint('[SearchScreen] Starting journal sync...');
      await searchIndex.syncJournals();

      debugPrint('[SearchScreen] Starting chat sync...');
      await searchIndex.syncChats();

      debugPrint('[SearchScreen] ✅ Search index sync complete');

      // Refresh stats
      if (mounted) {
        _loadStats();
      }
    } catch (e) {
      debugPrint('[SearchScreen] Error during index sync: $e');
    }
  }

  /// Wait for the vector store to be ready before loading stats
  Future<void> _waitForVectorStore() async {
    // Wait for the database path to be ready first
    try {
      await ref.read(vectorStorePathProvider.future);
      if (mounted) {
        setState(() => _isVectorStoreReady = true);
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Vector store initialization failed: $e';
          _isLoadingStats = false;
        });
      }
    }
  }

  Future<void> _loadStats() async {
    if (!_isVectorStoreReady) return;

    try {
      final vectorStore = ref.read(vectorStoreProvider);
      final stats = await vectorStore.getStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load stats: $e';
          _isLoadingStats = false;
        });
      }
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = null;
        _error = null;
        _searchTimeMs = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      if (_searchMode == SearchMode.keyword) {
        await _keywordSearch(query);
      } else {
        await _semanticSearch(query);
      }
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchTimeMs = stopwatch.elapsedMilliseconds;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
          _searchTimeMs = stopwatch.elapsedMilliseconds;
        });
      }
    }
  }

  /// Keyword search using simple text matching
  Future<void> _keywordSearch(String query) async {
    final simpleSearch = await ref.read(simpleTextSearchProvider.future);
    final results = await simpleSearch.search(query, limit: 30);

    if (mounted) {
      setState(() {
        _results = results;
      });
    }
  }

  /// Semantic search using vector embeddings
  Future<void> _semanticSearch(String query) async {
    if (!_isVectorStoreReady) {
      throw Exception('Search index is still loading...');
    }

    if (!_isEmbeddingReady) {
      throw Exception('Embedding model not ready. Please download it first.');
    }

    // Get embedding service and vector store
    final embeddingService = ref.read(embeddingServiceProvider);
    final vectorStore = ref.read(vectorStoreProvider);

    // Embed the query
    final queryEmbedding = await embeddingService.embed(query);

    // Search (get more results for deduplication)
    final allResults = await vectorStore.search(
      queryEmbedding,
      limit: 100,
      minScore: 0.0, // Show all results for debugging
    );

    // Deduplicate: keep only the best-matching chunk per source
    final deduped = <String, VectorSearchResult>{};
    for (final result in allResults) {
      final sourceId = result.recordingId;
      if (!deduped.containsKey(sourceId) ||
          result.score > deduped[sourceId]!.score) {
        deduped[sourceId] = result;
      }
    }

    // Sort by score and take top results
    final results = deduped.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final topResults = results.take(30).toList();

    if (mounted) {
      setState(() {
        _results = topResults;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
            tooltip: 'Refresh stats',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search mode toggle
          _buildModeToggle(isDark),

          // Embedding model status banner (only show in semantic mode)
          if (_searchMode == SearchMode.semantic) _buildEmbeddingBanner(isDark),

          // Indexing progress banner (only show in semantic mode)
          if (_searchMode == SearchMode.semantic) _buildIndexingBanner(isDark),

          // Stats card (only show in semantic mode)
          if (_searchMode == SearchMode.semantic) _buildStatsCard(isDark),

          // Search input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Search your vault...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _search('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: _search,
              onChanged: (value) {
                // Debounce search
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_searchController.text == value) {
                    _search(value);
                  }
                });
              },
            ),
          ),

          // Search status
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),

          if (_searchTimeMs != null && !_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_results?.length ?? 0} results in ${_searchTimeMs}ms',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),

          // Results list
          Expanded(
            child: _results == null || _results!.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    itemCount: _results!.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final result = _results![index];
                      if (_searchMode == SearchMode.keyword && result is SimpleSearchResult) {
                        return _buildSimpleResultCard(result, index, isDark);
                      } else if (result is VectorSearchResult) {
                        return _buildResultCard(result, index, isDark);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
      // Ask button - appears when there are search results
      floatingActionButton: _results != null && _results!.isNotEmpty && _searchController.text.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _askWithContext(_searchController.text, _results!),
              backgroundColor: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Ask AI'),
            )
          : null,
    );
  }

  /// Build the search mode toggle
  Widget _buildModeToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SegmentedButton<SearchMode>(
        segments: [
          ButtonSegment<SearchMode>(
            value: SearchMode.keyword,
            label: const Text('Keyword'),
            icon: const Icon(Icons.text_fields, size: 18),
          ),
          ButtonSegment<SearchMode>(
            value: SearchMode.semantic,
            label: const Text('Semantic'),
            icon: const Icon(Icons.auto_awesome, size: 18),
          ),
        ],
        selected: {_searchMode},
        onSelectionChanged: (Set<SearchMode> newSelection) {
          setState(() {
            _searchMode = newSelection.first;
            // Clear results when switching modes
            _results = null;
            _error = null;
            _searchTimeMs = null;
          });
          // Re-run search if there's a query
          if (_searchController.text.isNotEmpty) {
            _search(_searchController.text);
          }
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? BrandColors.nightForest : BrandColors.forest;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return isDark ? BrandColors.nightText : BrandColors.charcoal;
          }),
        ),
      ),
    );
  }

  /// Ask AI a question using search results as context
  void _askWithContext(String query, List<dynamic> results) {
    // Format search results as context for the AI
    final contextBuffer = StringBuffer();
    contextBuffer.writeln('The following are relevant excerpts from your vault:\n');

    // Take top 10 results for context
    final topResults = results.take(10).toList();
    for (var i = 0; i < topResults.length; i++) {
      final result = topResults[i];

      String sourceType;
      String sourceId;
      String content;

      if (result is SimpleSearchResult) {
        sourceType = result.type == 'journal' ? 'Journal' : 'Chat';
        sourceId = result.title;
        content = result.fullContent;
      } else if (result is VectorSearchResult) {
        sourceType = _contentTypeLabel(result.contentType.name);
        sourceId = _formatContentId(result.recordingId);
        content = result.chunkText;
      } else {
        continue;
      }

      contextBuffer.writeln('--- Source ${i + 1} ($sourceType: $sourceId) ---');
      contextBuffer.writeln(content);
      contextBuffer.writeln();
    }

    final searchContext = contextBuffer.toString();

    // Clear current chat and navigate with context
    ref.read(newChatProvider)();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          initialMessage: query,
          initialContext: searchContext,
        ),
      ),
    );
  }

  /// Build embedding model status banner
  Widget _buildEmbeddingBanner(bool isDark) {
    // Don't show if still checking or already ready
    if (_isCheckingEmbedding || _isEmbeddingReady) {
      return const SizedBox.shrink();
    }

    final isError = _embeddingError != null && !_isDownloadingEmbedding;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.withValues(alpha: 0.1)
            : (isDark ? BrandColors.nightForest : BrandColors.forest)
                .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? Colors.red.withValues(alpha: 0.3)
              : (isDark ? BrandColors.nightForest : BrandColors.forest)
                  .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.download,
                size: 20,
                color: isError
                    ? Colors.red
                    : (isDark ? BrandColors.nightForest : BrandColors.forest),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isError
                      ? 'Embedding model error'
                      : _isDownloadingEmbedding
                          ? 'Downloading embedding model...'
                          : 'Embedding model needed for search',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isDownloadingEmbedding) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _embeddingDownloadProgress > 0 ? _embeddingDownloadProgress : null,
                backgroundColor: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                    : BrandColors.driftwood.withValues(alpha: 0.2),
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _embeddingDownloadProgress > 0
                  ? 'Downloading... ${(_embeddingDownloadProgress * 100).toStringAsFixed(0)}%'
                  : 'Connecting to Ollama...',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ] else if (isError) ...[
            Text(
              _embeddingError!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red[700],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _downloadEmbeddingModel,
                child: const Text('Retry Download'),
              ),
            ),
          ] else ...[
            Text(
              'Download the AI model to enable semantic search across your vault',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _downloadEmbeddingModel,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download Model (~200 MB)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build indexing progress banner
  Widget _buildIndexingBanner(bool isDark) {
    // Try to get the search index service status
    final configuredIndexAsync = ref.watch(configuredSearchIndexProvider);

    return configuredIndexAsync.when(
      data: (searchIndex) {
        final status = searchIndex.status;
        final progress = searchIndex.progress;
        final total = searchIndex.totalToIndex;
        final count = searchIndex.indexedCount;

        // Only show when actively indexing
        if (status != IndexingStatus.indexing && status != IndexingStatus.syncing) {
          return const SizedBox.shrink();
        }

        final statusText = status == IndexingStatus.syncing
            ? 'Checking for changes...'
            : 'Indexing $count of $total items...';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: status == IndexingStatus.indexing ? progress : null,
                      color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
              if (status == IndexingStatus.indexing && total > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: isDark
                        ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                        : BrandColors.driftwood.withValues(alpha: 0.2),
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This runs once, then only new content is indexed',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatsCard(bool isDark) {
    if (_isLoadingStats) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                : BrandColors.driftwood.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading search index...',
              style: TextStyle(
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      );
    }

    final totalChunks = _stats?['totalChunks'] ?? 0;
    final totalRecordings = _stats?['totalRecordings'] ?? 0;
    final chunksByType = _stats?['chunksByType'] as Map<String, dynamic>? ?? {};
    final hasIndex = totalChunks > 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.driftwood.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and build button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasIndex ? 'Semantic Search Index' : 'Build Search Index',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              if (!hasIndex || true) // Always show rebuild option
                TextButton.icon(
                  onPressed: _isEmbeddingReady ? _showBuildIndexDialog : null,
                  icon: Icon(
                    hasIndex ? Icons.refresh : Icons.build,
                    size: 16,
                  ),
                  label: Text(hasIndex ? 'Rebuild' : 'Build'),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                  ),
                ),
            ],
          ),

          if (!hasIndex) ...[
            const SizedBox(height: 8),
            Text(
              'Enable semantic search to find content by meaning, not just keywords.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
                const SizedBox(width: 4),
                Text(
                  'Uses ~200MB storage + battery during indexing',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ],

          if (hasIndex) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatChip('Chunks', totalChunks.toString(), isDark),
                const SizedBox(width: 8),
                _buildStatChip('Items', totalRecordings.toString(), isDark),
              ],
            ),
            if (chunksByType.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: chunksByType.entries.map((e) {
                  return _buildStatChip(
                    _contentTypeLabel(e.key),
                    e.value.toString(),
                    isDark,
                    color: _contentTypeColor(e.key),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Show dialog to confirm building the search index
  void _showBuildIndexDialog() async {
    final journalService = await ref.read(journalServiceFutureProvider.future);
    final journalDates = await journalService.listJournalDates();
    final journalCount = journalDates.length;

    // Get chat session count
    final localReader = ref.read(localSessionReaderProvider);
    final chatSessions = await localReader.getLocalSessions();
    final chatCount = chatSessions.length;

    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Build Search Index'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will index your content for semantic search:',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: 12),
            _buildIndexOption(
              'Journals',
              '$journalCount days',
              Icons.book,
              isDark,
            ),
            const SizedBox(height: 8),
            _buildIndexOption(
              'Chats',
              '$chatCount sessions',
              Icons.chat,
              isDark,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.battery_alert, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This may take several minutes and use significant battery. Consider plugging in.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _triggerSearchIndexSync();
            },
            child: const Text('Build Index'),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexOption(String title, String subtitle, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, bool isDark, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? (isDark ? BrandColors.nightForest : BrandColors.forest))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color ?? (isDark ? BrandColors.nightForest : BrandColors.forest),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: isDark
                ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                : BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty
                ? 'Enter a search query'
                : 'No results found',
            style: TextStyle(
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }

  /// Build result card for simple keyword search
  Widget _buildSimpleResultCard(SimpleSearchResult result, int index, bool isDark) {
    final typeColor = result.type == 'journal' ? BrandColors.forest : BrandColors.turquoise;
    final typeIcon = result.type == 'journal' ? Icons.book : Icons.chat_bubble;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? BrandColors.nightSurface : Colors.white,
      child: InkWell(
        onTap: () => _navigateToSimpleResult(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with rank, type, and match count
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                          : BrandColors.driftwood.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, size: 12, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          result.type == 'journal' ? 'Journal' : 'Chat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: typeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Match count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${result.matchCount} matches',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Title
              Text(
                result.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),

              const SizedBox(height: 8),

              // Snippet with query highlighting
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : BrandColors.softWhite,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildHighlightedText(
                  result.snippet,
                  _searchController.text,
                  isDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Navigate to a simple search result
  void _navigateToSimpleResult(SimpleSearchResult result) {
    if (result.type == 'chat') {
      _navigateToChat(result.id.replaceFirst('chat:', ''));
    } else if (result.type == 'journal') {
      // Parse date from id (journal:YYYY-MM-DD:entryId)
      final parts = result.id.split(':');
      if (parts.length >= 2) {
        final dateStr = parts[1];
        final dateParts = dateStr.split('-');
        if (dateParts.length == 3) {
          final year = int.tryParse(dateParts[0]);
          final month = int.tryParse(dateParts[1]);
          final day = int.tryParse(dateParts[2]);

          if (year != null && month != null && day != null) {
            final date = DateTime(year, month, day);
            ref.read(selectedJournalDateProvider.notifier).state = date;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Journal date set to $dateStr - switch to Journal tab'),
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
        }
      }
    }

    // Fallback: show content preview
    _showSimpleResultPreview(result);
  }

  /// Show preview of simple search result
  void _showSimpleResultPreview(SimpleSearchResult result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? BrandColors.nightSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                    : BrandColors.driftwood.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    result.type == 'journal' ? Icons.book : Icons.chat_bubble,
                    color: result.type == 'journal' ? BrandColors.forest : BrandColors.turquoise,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: _buildHighlightedText(
                  result.fullContent,
                  _searchController.text,
                  isDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(VectorSearchResult result, int index, bool isDark) {
    final scoreColor = _scoreColor(result.score);
    final relevanceLabel = _relevanceLabel(result.score);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? BrandColors.nightSurface : Colors.white,
      child: InkWell(
        onTap: () => _navigateToContent(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with rank, content type, and score
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                          : BrandColors.driftwood.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _contentTypeColor(result.contentType.name)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _contentTypeIcon(result.contentType.name),
                          size: 12,
                          color: _contentTypeColor(result.contentType.name),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _contentTypeLabel(result.contentType.name),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _contentTypeColor(result.contentType.name),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Relevance label + score
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          relevanceLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: scoreColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(result.score * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Chunk text with query highlighting
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : BrandColors.softWhite,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _buildHighlightedText(
                  result.chunkText,
                  _searchController.text,
                  isDark,
                ),
              ),

              const SizedBox(height: 8),

              // Source info
              Row(
                children: [
                  Icon(
                    Icons.source_outlined,
                    size: 12,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatContentId(result.recordingId),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    result.field,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build text with query terms highlighted
  Widget _buildHighlightedText(String text, String query, bool isDark) {
    if (query.trim().isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Extract query terms (simple word split)
    final queryTerms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .toSet();

    if (queryTerms.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Build spans with highlighting
    final spans = <TextSpan>[];
    final pattern = RegExp(
      queryTerms.map((t) => RegExp.escape(t)).join('|'),
      caseSensitive: false,
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      // Add text before match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
        ));
      }
      // Add highlighted match
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          backgroundColor: (isDark ? BrandColors.nightForest : BrandColors.forest)
              .withValues(alpha: 0.3),
          fontWeight: FontWeight.w600,
        ),
      ));
      lastEnd = match.end;
    }
    // Add remaining text
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
        ),
        children: spans,
      ),
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Navigate to the source content
  void _navigateToContent(VectorSearchResult result) {
    // Parse the content ID to determine navigation
    final id = result.recordingId;

    if (id.startsWith('chat:')) {
      _navigateToChat(id.substring(5)); // Remove "chat:" prefix
    } else if (id.startsWith('journal:')) {
      // Format: journal:YYYY-MM-DD:entryId
      _navigateToJournal(id, result);
    } else {
      // Assume it's a recording ID (old format)
      _showContentPreview(result);
    }
  }

  /// Navigate to a chat session
  void _navigateToChat(String sessionId) async {
    // Load the session
    await ref.read(switchSessionProvider)(sessionId);

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const ChatScreen(),
        ),
      );
    }
  }

  /// Navigate to a journal entry
  void _navigateToJournal(String id, VectorSearchResult result) {
    // Parse journal:YYYY-MM-DD:entryId
    final parts = id.split(':');
    if (parts.length >= 2) {
      final dateStr = parts[1];
      final dateParts = dateStr.split('-');
      if (dateParts.length == 3) {
        final year = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final day = int.tryParse(dateParts[2]);

        if (year != null && month != null && day != null) {
          final date = DateTime(year, month, day);

          // Set the selected journal date
          ref.read(selectedJournalDateProvider.notifier).state = date;

          // Show a snackbar with navigation hint
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Journal date set to $dateStr - switch to Journal tab'),
              action: SnackBarAction(
                label: 'View',
                onPressed: () {
                  // Show preview as fallback
                  _showContentPreview(result);
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          return;
        }
      }
    }

    // Fallback: show content preview
    _showContentPreview(result);
  }

  /// Show a preview of the content in a bottom sheet
  void _showContentPreview(VectorSearchResult result) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? BrandColors.nightSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                    : BrandColors.driftwood.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _contentTypeIcon(result.contentType.name),
                    color: _contentTypeColor(result.contentType.name),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _contentTypeLabel(result.contentType.name),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _scoreColor(result.score).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${(result.score * 100).toStringAsFixed(0)}% match',
                      style: TextStyle(
                        fontSize: 12,
                        color: _scoreColor(result.score),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: _buildHighlightedText(
                  result.chunkText,
                  _searchController.text,
                  isDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format content ID for display
  String _formatContentId(String id) {
    if (id.startsWith('chat:')) {
      return 'Chat session';
    } else if (id.startsWith('journal:')) {
      // Format: journal:YYYY-MM-DD:entryId
      final parts = id.split(':');
      if (parts.length >= 2) {
        return 'Journal ${parts[1]}';
      }
      return 'Journal entry';
    } else {
      return 'Recording';
    }
  }

  String _relevanceLabel(double score) {
    if (score >= 0.8) return 'Very high';
    if (score >= 0.6) return 'High';
    if (score >= 0.4) return 'Medium';
    if (score >= 0.2) return 'Low';
    return 'Weak';
  }

  IconData _contentTypeIcon(String type) {
    switch (type) {
      case 'recording':
        return Icons.mic;
      case 'journal':
        return Icons.book;
      case 'chat':
        return Icons.chat_bubble;
      default:
        return Icons.description;
    }
  }

  String _contentTypeLabel(String type) {
    switch (type) {
      case 'recording':
        return 'Recording';
      case 'journal':
        return 'Journal';
      case 'chat':
        return 'Chat';
      default:
        return type;
    }
  }

  Color _contentTypeColor(String type) {
    switch (type) {
      case 'recording':
        return Colors.purple;
      case 'journal':
        return BrandColors.forest;
      case 'chat':
        return BrandColors.turquoise;
      default:
        return Colors.grey;
    }
  }

  Color _scoreColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.lime;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }
}
