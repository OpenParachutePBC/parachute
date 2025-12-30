import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import 'package:parachute_daily/core/providers/file_system_provider.dart';

/// Storage settings section for Parachute Daily
///
/// Configures:
/// - Daily folder location (root path)
/// - Journals subfolder name (empty = store in root)
/// - Assets subfolder name
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  String _currentPath = '';
  final TextEditingController _journalsFolderController = TextEditingController();
  final TextEditingController _assetsFolderController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _journalsFolderController.dispose();
    _assetsFolderController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      await fileSystemService.initialize();

      final path = await fileSystemService.getRootPathDisplay();
      final journalsName = fileSystemService.getJournalFolderName();
      final assetsName = fileSystemService.getAssetsFolderName();

      setState(() {
        _currentPath = path;
        _journalsFolderController.text = journalsName;
        _assetsFolderController.text = assetsName;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _currentPath = 'Error loading path';
        _isLoading = false;
      });
    }
  }

  Future<void> _chooseDailyFolder() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);

    // On Android, check permission first
    if (Platform.isAndroid) {
      final hasPermission = await fileSystemService.hasStoragePermission();
      if (!hasPermission) {
        final granted = await fileSystemService.requestStoragePermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Storage permission required to choose folder'),
              ),
            );
          }
          return;
        }
      }
    }

    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Parachute Daily Folder',
    );

    if (result != null && mounted) {
      final success = await fileSystemService.setRootPath(result, migrateFiles: false);
      if (success) {
        await _loadCurrentSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Daily folder set to: $result')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to set folder')),
          );
        }
      }
    }
  }

  Future<void> _openDailyFolder() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final path = await fileSystemService.getRootPath();
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _updateSubfolderNames() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final success = await fileSystemService.setSubfolderNames(
      journalsFolderName: _journalsFolderController.text,
      assetsFolderName: _assetsFolderController.text,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Subfolder names updated' : 'Failed to update'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Storage',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // Daily folder path
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Path display
              ListTile(
                title: const Text('Daily Folder'),
                subtitle: Text(
                  _currentPath,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Open folder button
                    if (Platform.isMacOS || Platform.isLinux)
                      IconButton(
                        icon: Icon(
                          Icons.folder_open,
                          color: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                        ),
                        onPressed: _openDailyFolder,
                        tooltip: 'Open in file manager',
                      ),
                    // Change folder button
                    IconButton(
                      icon: Icon(
                        Icons.edit,
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                      onPressed: _chooseDailyFolder,
                      tooltip: 'Change folder',
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Journals subfolder
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Journals subfolder',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _journalsFolderController,
                        decoration: InputDecoration(
                          hintText: '(root)',
                          hintStyle: TextStyle(
                            color: isDark
                                ? BrandColors.nightTextSecondary.withValues(alpha: 0.5)
                                : BrandColors.driftwood.withValues(alpha: 0.5),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                        onSubmitted: (_) => _updateSubfolderNames(),
                      ),
                    ),
                  ],
                ),
              ),

              // Assets subfolder
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Assets subfolder',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _assetsFolderController,
                        decoration: InputDecoration(
                          hintText: 'assets',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                        onSubmitted: (_) => _updateSubfolderNames(),
                      ),
                    ),
                  ],
                ),
              ),

              // Helper text
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Leave journals blank to store directly in Daily folder. Assets stores audio and images.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                        : BrandColors.driftwood.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }
}
