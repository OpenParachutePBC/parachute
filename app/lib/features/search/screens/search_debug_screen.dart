import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/search_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';

/// Debug screen for testing RAG search functionality
///
/// This is a temporary screen for development testing.
/// Remove or replace with proper UI in issue #28.
class SearchDebugScreen extends ConsumerStatefulWidget {
  const SearchDebugScreen({super.key});

  @override
  ConsumerState<SearchDebugScreen> createState() => _SearchDebugScreenState();
}

class _SearchDebugScreenState extends ConsumerState<SearchDebugScreen> {
  final _searchController = TextEditingController();
  List<SearchResult> _results = [];
  bool _isSearching = false;
  bool _isIndexing = false;
  String? _error;
  String _statusMessage = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
      _results = [];
    });

    try {
      final hybridSearch = ref.read(hybridSearchServiceProvider);
      final results = await hybridSearch.search(query, limit: 20);

      setState(() {
        _results = results;
        _statusMessage = 'Found ${results.length} results';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _rebuildIndex() async {
    setState(() {
      _isIndexing = true;
      _error = null;
      _statusMessage = 'Rebuilding index...';
    });

    try {
      final searchIndex = ref.read(searchIndexServiceProvider);
      await searchIndex.forceFullReindex();

      setState(() {
        _statusMessage = 'Index rebuilt successfully!';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isIndexing = false;
      });
    }
  }

  Future<void> _syncIndex() async {
    setState(() {
      _isIndexing = true;
      _error = null;
      _statusMessage = 'Syncing index...';
    });

    try {
      final searchIndex = ref.read(searchIndexServiceProvider);
      await searchIndex.syncIndexes();

      setState(() {
        _statusMessage = 'Index synced!';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isIndexing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isIndexing ? null : _syncIndex,
            tooltip: 'Sync Index',
          ),
          IconButton(
            icon: const Icon(Icons.build),
            onPressed: _isIndexing ? null : _rebuildIndex,
            tooltip: 'Rebuild Index',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search input
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search your recordings...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSearching ? null : _runSearch,
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
          ),

          // Status message
          if (_statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Error display
          if (_error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // Indexing indicator
          if (_isIndexing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Indexing...'),
                ],
              ),
            ),

          // Results list
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _isSearching
                          ? 'Searching...'
                          : 'Enter a query to search',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final result = _results[index];
                      return _SearchResultCard(result: result);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final SearchResult result;

  const _SearchResultCard({required this.result});

  void _openRecording(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RecordingDetailScreen(recording: result.recording),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _openRecording(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and score
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.recording.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getRelevanceColor(result.relevanceLabel),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      result.relevanceLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Match info
              Row(
                children: [
                  if (result.hasVectorMatch)
                    const Chip(
                      label: Text('Semantic'),
                      backgroundColor: Colors.blue,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 10),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (result.hasVectorMatch && result.hasKeywordMatch)
                    const SizedBox(width: 4),
                  if (result.hasKeywordMatch)
                    const Chip(
                      label: Text('Keyword'),
                      backgroundColor: Colors.green,
                      labelStyle: TextStyle(color: Colors.white, fontSize: 10),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Matched chunk preview
              if (result.matchedChunk != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    result.getSnippet(maxLength: 200),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              const SizedBox(height: 8),

              // Debug scores
              Text(
                'RRF: ${result.rrfScore.toStringAsFixed(4)} | '
                'Vector: ${result.vectorScore?.toStringAsFixed(3) ?? "N/A"} (rank ${result.vectorRank ?? "N/A"}) | '
                'BM25: ${result.keywordScore?.toStringAsFixed(3) ?? "N/A"} (rank ${result.keywordRank ?? "N/A"})',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRelevanceColor(String relevance) {
    switch (relevance) {
      case 'High':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
