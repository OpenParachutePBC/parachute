import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/files/models/file_item.dart';
import 'package:app/features/files/providers/file_browser_provider.dart';
import 'package:app/features/files/screens/markdown_viewer_screen.dart';

/// Provider for showing hidden files toggle
final showHiddenFilesProvider = StateProvider<bool>((ref) => false);

/// Browse content widget - extracted from FilesScreen
///
/// Provides file system navigation with folder hierarchy,
/// hidden files toggle, and file operations via long-press menu.
class BrowseContent extends ConsumerStatefulWidget {
  const BrowseContent({super.key});

  @override
  ConsumerState<BrowseContent> createState() => _BrowseContentState();
}

class _BrowseContentState extends ConsumerState<BrowseContent> with WidgetsBindingObserver {
  String? _lastKnownRootPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize path to root on first load
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeOrRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh when app comes back to foreground
      _checkForVaultChange();
    }
  }

  Future<void> _initializeOrRefresh() async {
    final service = ref.read(fileBrowserServiceProvider);
    final rootPath = await service.getInitialPath();

    // Check if widget is still mounted after async operation
    if (!mounted) return;

    _lastKnownRootPath = rootPath;

    final currentPath = ref.read(currentBrowsePathProvider);
    if (currentPath.isEmpty || !currentPath.startsWith(rootPath)) {
      ref.read(currentBrowsePathProvider.notifier).state = rootPath;
    }
  }

  Future<void> _checkForVaultChange() async {
    final service = ref.read(fileBrowserServiceProvider);
    final currentRootPath = await service.getInitialPath();

    // Check if widget is still mounted after async operation
    if (!mounted) return;

    if (_lastKnownRootPath != null && _lastKnownRootPath != currentRootPath) {
      // Vault changed, reset to new root
      _lastKnownRootPath = currentRootPath;
      ref.read(currentBrowsePathProvider.notifier).state = currentRootPath;
      ref.read(folderRefreshTriggerProvider.notifier).state++;
    }
  }

  void _navigateToFolder(String path) {
    debugPrint('[BrowseContent] Navigating to folder: "$path"');
    ref.read(currentBrowsePathProvider.notifier).state = path;
  }

  void _navigateBack() {
    final service = ref.read(fileBrowserServiceProvider);
    final currentPath = ref.read(currentBrowsePathProvider);
    final parentPath = service.getParentPath(currentPath);
    ref.read(currentBrowsePathProvider.notifier).state = parentPath;
  }

  void _onItemTap(FileItem item) {
    if (item.isFolder) {
      _navigateToFolder(item.path);
    } else if (item.isMarkdown) {
      _openMarkdownFile(item);
    } else if (item.isAudio) {
      _playAudioFile(item);
    } else {
      _showFileInfo(item);
    }
  }

  void _onItemLongPress(FileItem item) {
    _showContextMenu(item);
  }

  void _openMarkdownFile(FileItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarkdownViewerScreen(file: item),
      ),
    );
  }

  void _playAudioFile(FileItem item) {
    // TODO: Play audio file
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Audio playback coming soon: ${item.name}')),
    );
  }

  void _showFileInfo(FileItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${item.type.name}'),
            if (item.sizeBytes != null)
              Text('Size: ${_formatFileSize(item.sizeBytes!)}'),
            if (item.modified != null)
              Text('Modified: ${_formatDate(item.modified!)}'),
            const SizedBox(height: 8),
            Text(
              item.path,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(FileItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? BrandColors.nightSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

            // File name header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildItemIcon(item, isDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.sizeBytes != null)
                          Text(
                            _formatFileSize(item.sizeBytes!),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? BrandColors.nightTextSecondary
                                  : BrandColors.driftwood,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Actions
            if (!item.isFolder)
              ListTile(
                leading: Icon(
                  Icons.open_in_new,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
                title: Text(
                  'Open',
                  style: TextStyle(
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _onItemTap(item);
                },
              ),

            ListTile(
              leading: Icon(
                Icons.copy,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              title: Text(
                'Copy Path',
                style: TextStyle(
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: item.path));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied to clipboard')),
                );
              },
            ),

            ListTile(
              leading: Icon(
                Icons.info_outline,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              title: Text(
                'Info',
                style: TextStyle(
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showFileInfo(item);
              },
            ),

            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(item);
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(FileItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.isFolder ? "folder" : "file"}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${item.name}"?',
              style: TextStyle(
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            if (item.isFolder) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will delete all contents inside the folder.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteItem(item);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(FileItem item) async {
    try {
      final service = ref.read(fileBrowserServiceProvider);
      await service.deleteItem(item.path);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${item.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _refresh() {
    // Check for vault changes when manually refreshing
    _checkForVaultChange();
    ref.read(folderRefreshTriggerProvider.notifier).state++;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showHidden = ref.watch(showHiddenFilesProvider);
    final folderContents = ref.watch(folderContentsWithHiddenProvider(showHidden));
    final isAtRoot = ref.watch(isAtRootProvider);
    final displayPath = ref.watch(displayPathProvider);
    final folderName = ref.watch(currentFolderNameProvider);

    return Column(
      children: [
        // Toolbar with path and actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                    : BrandColors.driftwood.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              // Back button
              isAtRoot.when(
                data: (atRoot) => atRoot
                    ? const SizedBox(width: 40)
                    : IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                        onPressed: _navigateBack,
                        tooltip: 'Go back',
                      ),
                loading: () => const SizedBox(width: 40),
                error: (_, __) => const SizedBox(width: 40),
              ),

              // Folder name and path
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folderName,
                      style: TextStyle(
                        fontSize: TypographyTokens.titleSmall,
                        fontWeight: FontWeight.bold,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    displayPath.when(
                      data: (path) => Text(
                        path,
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              // Hidden files toggle
              IconButton(
                icon: Icon(
                  showHidden ? Icons.visibility : Icons.visibility_off,
                  color: showHidden
                      ? (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                      : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
                ),
                onPressed: () {
                  ref.read(showHiddenFilesProvider.notifier).state = !showHidden;
                },
                tooltip: showHidden ? 'Hide hidden files' : 'Show hidden files',
              ),

              // Refresh button
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
                onPressed: _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // File list
        Expanded(
          child: folderContents.when(
            data: (items) => items.isEmpty
                ? _buildEmptyState(isDark)
                : RefreshIndicator(
                    onRefresh: () async => _refresh(),
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildFileItem(items[index], isDark),
                    ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                  SizedBox(height: Spacing.md),
                  Text(
                    'Error loading folder',
                    style: TextStyle(
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  SizedBox(height: Spacing.sm),
                  Text(
                    error.toString(),
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: Spacing.lg),
                  FilledButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: isDark
                ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                : BrandColors.driftwood.withValues(alpha: 0.5),
          ),
          SizedBox(height: Spacing.lg),
          Text(
            'This folder is empty',
            style: TextStyle(
              fontSize: TypographyTokens.titleMedium,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(FileItem item, bool isDark) {
    final isHidden = item.name.startsWith('.');

    return ListTile(
      leading: _buildItemIcon(item, isDark),
      title: Text(
        item.name,
        style: TextStyle(
          color: isHidden
              ? (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
              : (isDark ? BrandColors.nightText : BrandColors.charcoal),
          fontWeight: item.isFolder ? FontWeight.w500 : FontWeight.normal,
          fontStyle: isHidden ? FontStyle.italic : FontStyle.normal,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.isFolder
          ? null
          : Text(
              item.sizeBytes != null
                  ? _formatFileSize(item.sizeBytes!)
                  : item.type.name,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
      trailing: item.isFolder
          ? Icon(
              Icons.chevron_right,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            )
          : null,
      onTap: () => _onItemTap(item),
      onLongPress: () => _onItemLongPress(item),
    );
  }

  Widget _buildItemIcon(FileItem item, bool isDark) {
    IconData icon;
    Color color;

    switch (item.type) {
      case FileItemType.folder:
        icon = Icons.folder;
        color = isDark ? BrandColors.nightForest : BrandColors.forest;
        break;
      case FileItemType.markdown:
        icon = Icons.description;
        color = isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep;
        break;
      case FileItemType.audio:
        icon = Icons.audio_file;
        color = isDark
            ? BrandColors.nightForest.withValues(alpha: 0.8)
            : BrandColors.forestLight;
        break;
      case FileItemType.other:
        icon = Icons.insert_drive_file;
        color = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
