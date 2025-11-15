import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/services/github/github_api_service.dart';

/// Dialog for creating a new GitHub repository
class CreateRepositoryDialog extends ConsumerStatefulWidget {
  const CreateRepositoryDialog({super.key});

  @override
  ConsumerState<CreateRepositoryDialog> createState() =>
      _CreateRepositoryDialogState();
}

class _CreateRepositoryDialogState
    extends ConsumerState<CreateRepositoryDialog> {
  final GitHubAPIService _apiService = GitHubAPIService.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  bool _isPrivate = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-fill with suggested name
    _nameController.text = 'parachute-vault';
    _descriptionController.text =
        'Parachute vault - Personal knowledge base with voice recordings and AI spaces';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Create New Repository'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Repository name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Repository Name *',
                hintText: 'parachute-vault',
                prefixIcon: const Icon(Icons.folder_outlined),
                border: const OutlineInputBorder(),
                helperText: 'Only letters, numbers, hyphens, and underscores',
              ),
              enabled: !_isCreating,
            ),
            const SizedBox(height: 16),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'Brief description of your vault',
                prefixIcon: Icon(Icons.description_outlined),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              enabled: !_isCreating,
            ),
            const SizedBox(height: 16),

            // Privacy setting
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(
                    _isPrivate ? Icons.lock_outline : Icons.public,
                    color: _isPrivate ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isPrivate
                              ? 'Private Repository'
                              : 'Public Repository',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _isPrivate
                              ? 'Only you can see this repository'
                              : 'Anyone can see this repository',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isPrivate,
                    onChanged: _isCreating
                        ? null
                        : (value) {
                            setState(() {
                              _isPrivate = value;
                            });
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Recommendation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'We recommend private repositories for personal data',
                      style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                    ),
                  ),
                ],
              ),
            ),

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isCreating ? null : _createRepository,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_isCreating ? 'Creating...' : 'Create Repository'),
        ),
      ],
    );
  }

  Future<void> _createRepository() async {
    final name = _nameController.text.trim();

    // Validation
    if (name.isEmpty) {
      setState(() {
        _error = 'Repository name is required';
      });
      return;
    }

    // Validate repository name format
    final nameRegex = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!nameRegex.hasMatch(name)) {
      setState(() {
        _error =
            'Name can only contain letters, numbers, hyphens, and underscores';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final repo = await _apiService.createRepository(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        private: _isPrivate,
        autoInit: true, // Initialize with README
      );

      if (repo != null && mounted) {
        Navigator.of(context).pop(repo); // Return the created repository
      } else if (mounted) {
        setState(() {
          _error = 'Failed to create repository. It may already exist.';
          _isCreating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isCreating = false;
        });
      }
    }
  }
}
