import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/models/space.dart';
import 'package:app/features/spaces/providers/space_provider.dart';
import 'package:app/features/spaces/providers/space_knowledge_provider.dart';
import 'package:app/features/spaces/providers/space_storage_provider.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';

/// Screen for linking or moving a capture to spheres
///
/// Supports two actions:
/// - Link: Creates a reference to the capture (stays in inbox)
/// - Move: Physically moves files into the sphere's captures folder
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
  String? _selectedSpaceId;
  final _contextController = TextEditingController();
  final _tagInputController = TextEditingController();
  final List<String> _tags = [];

  bool _isLoading = false;
  bool _showCreateSphere = false;
  final _newSphereNameController = TextEditingController();
  String _newSphereIcon = '📁';

  @override
  void dispose() {
    _contextController.dispose();
    _tagInputController.dispose();
    _newSphereNameController.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    if (tag.trim().isEmpty) return;
    setState(() {
      _tags.add(tag.trim());
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _createNewSphere() async {
    final name = _newSphereNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a sphere name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storageService = ref.read(spaceStorageServiceProvider);
      final newSpace = await storageService.createSpace(
        name: name,
        icon: _newSphereIcon,
      );

      // Refresh the spaces list
      ref.invalidate(spaceListProvider);

      setState(() {
        _selectedSpaceId = newSpace.id;
        _showCreateSphere = false;
        _newSphereNameController.clear();
        _newSphereIcon = '📁';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created sphere: ${newSpace.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create sphere: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _linkToSpace() async {
    if (_selectedSpaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a sphere')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final knowledgeService = ref.read(spaceKnowledgeServiceProvider);
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final spacesPath = await fileSystemService.getSpacesPath();

      final spacesAsync = await ref.read(spaceListProvider.future);
      final space = spacesAsync.where((s) => s.id == _selectedSpaceId).firstOrNull;
      if (space == null) throw Exception('Sphere not found');

      final spacePath = '$spacesPath/${space.path}';
      final contextText = _contextController.text;

      await knowledgeService.linkCaptureToSpace(
        spaceId: _selectedSpaceId!,
        spacePath: spacePath,
        captureId: widget.captureId,
        notePath: widget.notePath,
        context: contextText.isNotEmpty ? contextText : null,
        tags: _tags.isNotEmpty ? _tags : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('Linked to ${space.name}')),
        );
        Navigator.of(this.context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to link: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _moveToSpace() async {
    if (_selectedSpaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a sphere')),
      );
      return;
    }

    // Confirm move action
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Sphere?'),
        content: const Text(
          'This will move the recording files into the sphere folder. '
          'The recording will no longer appear in the main captures list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final knowledgeService = ref.read(spaceKnowledgeServiceProvider);
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final spacesPath = await fileSystemService.getSpacesPath();

      final spacesAsync = await ref.read(spaceListProvider.future);
      final space = spacesAsync.where((s) => s.id == _selectedSpaceId).firstOrNull;
      if (space == null) throw Exception('Sphere not found');

      final spacePath = '$spacesPath/${space.path}';
      final contextText = _contextController.text;

      await knowledgeService.moveCaptureToSpace(
        spacePath: spacePath,
        captureId: widget.captureId,
        sourcePath: widget.notePath,
        context: contextText.isNotEmpty ? contextText : null,
        tags: _tags.isNotEmpty ? _tags : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('Moved to ${space.name}')),
        );
        Navigator.of(this.context).pop('moved');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to move: $e')),
        );
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add to Sphere'),
      ),
      body: spacesAsync.when(
        data: (spaces) => _buildBody(spaces, theme),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Error loading spheres: $error')),
      ),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  Widget _buildBody(List<Space> spaces, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.mic, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.filename,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Select sphere section
          Text(
            'Select Sphere',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Sphere list
          if (spaces.isEmpty && !_showCreateSphere)
            _buildEmptyState(theme)
          else
            ...spaces.map((space) => _buildSpaceOption(space, theme)),

          // Create new sphere option
          if (!_showCreateSphere)
            _buildCreateSphereButton(theme)
          else
            _buildCreateSphereForm(theme),

          const SizedBox(height: 24),

          // Context and tags (only show when sphere selected)
          if (_selectedSpaceId != null) ...[
            Text(
              'Context (optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contextController,
              decoration: const InputDecoration(
                hintText: 'Why is this relevant to this sphere?',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 16),

            Text(
              'Tags (optional)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagInputController,
                    decoration: const InputDecoration(
                      hintText: 'Add tag',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: _addTag,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _addTag(_tagInputController.text),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        onDeleted: () => _removeTag(tag),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],

          const SizedBox(height: 100), // Space for bottom bar
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.bubble_chart_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No spheres yet',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first sphere to organize your captures',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSpaceOption(Space space, ThemeData theme) {
    final isSelected = _selectedSpaceId == space.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedSpaceId = isSelected ? null : space.id;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    space.icon ?? '📁',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  space.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : null,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateSphereButton(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _showCreateSphere = true;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Create new sphere',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateSphereForm(ThemeData theme) {
    final icons = ['📁', '💼', '🏠', '💡', '📚', '🎯', '🌟', '🔬', '🎨', '🌱', '🎵', '✈️'];

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'New Sphere',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showCreateSphere = false;
                    });
                  },
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newSphereNameController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Sphere name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _createNewSphere(),
            ),
            const SizedBox(height: 12),
            Text(
              'Icon',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: icons.map((icon) {
                final isSelected = _newSphereIcon == icon;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _newSphereIcon = icon;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: theme.colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _createNewSphere,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Sphere'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoading || _selectedSpaceId == null
                    ? null
                    : _linkToSpace,
                icon: const Icon(Icons.link),
                label: const Text('Link'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isLoading || _selectedSpaceId == null
                    ? null
                    : _moveToSpace,
                icon: const Icon(Icons.drive_file_move),
                label: const Text('Move'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
