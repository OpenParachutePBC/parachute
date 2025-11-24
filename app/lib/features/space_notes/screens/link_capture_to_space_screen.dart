import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/space.dart';
import 'package:app/features/spaces/providers/space_provider.dart';
import 'package:app/features/spaces/providers/space_knowledge_provider.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';

class LinkCaptureToSpaceScreen extends ConsumerStatefulWidget {
  final String captureId;
  final String filename;
  final String notePath;

  const LinkCaptureToSpaceScreen({
    super.key,
    required this.captureId,
    required this.filename,
    required this.notePath,
  });

  @override
  ConsumerState<LinkCaptureToSpaceScreen> createState() =>
      _LinkCaptureToSpaceScreenState();
}

class _LinkCaptureToSpaceScreenState
    extends ConsumerState<LinkCaptureToSpaceScreen> {
  final Map<String, bool> _selectedSpaces = {};
  final Map<String, TextEditingController> _contextControllers = {};
  final Map<String, List<String>> _spaceTags = {};
  final Map<String, TextEditingController> _tagInputControllers = {};

  bool _isLoading = false;

  @override
  void dispose() {
    for (final controller in _contextControllers.values) {
      controller.dispose();
    }
    for (final controller in _tagInputControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addTag(String spaceId, String tag) {
    if (tag.trim().isEmpty) return;

    setState(() {
      _spaceTags[spaceId] = [...(_spaceTags[spaceId] ?? []), tag.trim()];
      _tagInputControllers[spaceId]?.clear();
    });
  }

  void _removeTag(String spaceId, String tag) {
    setState(() {
      _spaceTags[spaceId] = _spaceTags[spaceId]!..remove(tag);
    });
  }

  Future<void> _linkToSpaces() async {
    final selectedSpaceIds = _selectedSpaces.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (selectedSpaceIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one space')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final knowledgeService = ref.read(spaceKnowledgeServiceProvider);
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final spacesPath = await fileSystemService.getSpacesPath();

      // Get all spaces to find paths
      final spacesAsync = await ref.read(spaceListProvider.future);

      for (final spaceId in selectedSpaceIds) {
        // Find space by ID
        final space = spacesAsync.where((s) => s.id == spaceId).firstOrNull;
        if (space == null) continue;

        final spacePath = '$spacesPath/${space.path}';
        final context = _contextControllers[spaceId]?.text ?? '';
        final tags = _spaceTags[spaceId] ?? [];

        await knowledgeService.linkCaptureToSpace(
          spaceId: spaceId,
          spacePath: spacePath,
          captureId: widget.captureId,
          notePath: widget.notePath,
          context: context.isNotEmpty ? context : null,
          tags: tags.isNotEmpty ? tags : null,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Linked to ${selectedSpaceIds.length} space${selectedSpaceIds.length > 1 ? 's' : ''}',
            ),
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to link: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacesAsync = ref.watch(spaceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link to Spaces'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(onPressed: _linkToSpaces, child: const Text('Link')),
        ],
      ),
      body: spacesAsync.when(
        data: (spaces) {
          if (spaces.isEmpty) {
            return const Center(
              child: Text('No spaces available. Create a space first.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Select spaces to link "${widget.filename}"',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'You can add different context and tags for each space',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              ...spaces.map((space) => _buildSpaceCard(space)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Error loading spaces: $error')),
      ),
    );
  }

  Widget _buildSpaceCard(Space space) {
    final isSelected = _selectedSpaces[space.id] ?? false;

    // Initialize controllers if not exist
    _contextControllers.putIfAbsent(space.id, () => TextEditingController());
    _tagInputControllers.putIfAbsent(space.id, () => TextEditingController());

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      _selectedSpaces[space.id] = value ?? false;
                    });
                  },
                ),
                if (space.icon?.isNotEmpty ?? false) ...[
                  Text(space.icon!, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    space.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _contextControllers[space.id],
                decoration: const InputDecoration(
                  labelText: 'Context for this space',
                  hintText: 'How does this note relate to this space?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagInputControllers[space.id],
                      decoration: const InputDecoration(
                        labelText: 'Add tags',
                        hintText: 'e.g., farming, research',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) => _addTag(space.id, value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        _addTag(space.id, _tagInputControllers[space.id]!.text),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if ((_spaceTags[space.id] ?? []).isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (_spaceTags[space.id] ?? [])
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                          onDeleted: () => _removeTag(space.id, tag),
                        ),
                      )
                      .toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
