import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/github/github_api_service.dart';
import 'package:app/core/providers/github_auth_provider.dart';

/// Repository selector widget
///
/// Displays a list of user's GitHub repositories with search functionality.
/// When using GitHub Apps, shows ONLY the repositories the user authorized.
class RepositorySelector extends ConsumerStatefulWidget {
  final GitHubRepository? selectedRepository;
  final Function(GitHubRepository) onRepositorySelected;
  final VoidCallback onCreateNew;

  const RepositorySelector({
    super.key,
    this.selectedRepository,
    required this.onRepositorySelected,
    required this.onCreateNew,
  });

  @override
  ConsumerState<RepositorySelector> createState() => _RepositorySelectorState();
}

class _RepositorySelectorState extends ConsumerState<RepositorySelector> {
  final GitHubAPIService _apiService = GitHubAPIService.instance;
  final TextEditingController _searchController = TextEditingController();

  List<GitHubRepository> _repositories = [];
  List<GitHubRepository> _filteredRepositories = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRepositories();
    _searchController.addListener(_filterRepositories);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRepositories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get installation ID for repository-scoped access (GitHub Apps)
      final gitHubAuth = ref.read(gitHubAuthProvider);
      final installationId = gitHubAuth.installationId;

      if (installationId != null) {
        debugPrint(
          '[RepositorySelector] Loading authorized repositories (installation: $installationId)',
        );
      } else {
        debugPrint(
          '[RepositorySelector] Loading all user repositories (OAuth App mode)',
        );
      }

      final repos = await _apiService.listRepositories(
        installationId: installationId, // GitHub App: only authorized repos
        perPage: 100,
      );

      if (mounted) {
        setState(() {
          _repositories = repos;
          _filteredRepositories = repos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterRepositories() {
    final query = _searchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredRepositories = _repositories;
      } else {
        _filteredRepositories = _repositories.where((repo) {
          return repo.name.toLowerCase().contains(query) ||
              (repo.description?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search repositories...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),

        // Create new repository button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: widget.onCreateNew,
            icon: const Icon(Icons.add),
            label: const Text('Create New Repository'),
          ),
        ),
        const SizedBox(height: 16),

        // Repository list (fixed height)
        SizedBox(height: 400, child: _buildRepositoryList(theme)),
      ],
    );
  }

  Widget _buildRepositoryList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Failed to load repositories',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRepositories,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_filteredRepositories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No repositories found'
                  : 'No matching repositories',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isEmpty
                  ? 'Create a new repository to get started'
                  : 'Try a different search term',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredRepositories.length,
      itemBuilder: (context, index) {
        final repo = _filteredRepositories[index];
        final isSelected = widget.selectedRepository?.id == repo.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
          child: ListTile(
            leading: Icon(
              repo.private ? Icons.lock_outline : Icons.public,
              color: repo.private ? Colors.orange : Colors.green,
            ),
            title: Text(
              repo.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (repo.description != null)
                  Text(
                    repo.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  'Updated ${_formatDate(repo.updatedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.blue)
                : null,
            onTap: () => widget.onRepositorySelected(repo),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
