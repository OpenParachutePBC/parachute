import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/features/files/providers/file_browser_provider.dart';
import './settings_section_header.dart';

/// Storage settings section for Parachute Chat
///
/// Chat module folder structure:
/// - ~/Parachute/Chat/ (root)
///   - sessions/ - AI chat sessions
///   - assets/ - Media files
///   - contexts/ - Personal context files
///   - imports/ - Imported chat history
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  String _rootPath = '';
  String _assetsFolderName = 'assets';
  String _sessionsFolderName = 'sessions';
  final TextEditingController _assetsFolderNameController =
      TextEditingController();
  final TextEditingController _sessionsFolderNameController =
      TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _assetsFolderNameController.dispose();
    _sessionsFolderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    await fileSystemService.initialize();
    _rootPath = await fileSystemService.getRootPathDisplay();
    _assetsFolderName = fileSystemService.getAssetsFolderName();
    _sessionsFolderName = fileSystemService.getSessionsFolderName();
    _assetsFolderNameController.text = _assetsFolderName;
    _sessionsFolderNameController.text = _sessionsFolderName;

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openChatFolder() async {
    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final folderPath = await fileSystemService.getRootPath();

      final uri = Uri.file(folderPath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not open folder'),
              backgroundColor: BrandColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening folder: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _chooseChatFolder() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);

    // On Android, ensure we have storage permission first
    if (Platform.isAndroid) {
      final hasPermission = await fileSystemService.hasStoragePermission();
      if (!hasPermission) {
        // Show permission dialog
        final requestPermission = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Storage Permission Required'),
            content: const Text(
              'Parachute Chat needs access to all files to work with your vault folder.\n\n'
              'This permission allows Parachute to read and write files in any location, '
              'similar to how Obsidian works.\n\n'
              'You\'ll be taken to settings to grant this permission.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Grant Permission'),
              ),
            ],
          ),
        );

        if (requestPermission != true) return;

        final granted = await fileSystemService.requestStoragePermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Storage permission is required to access vault folders'),
                backgroundColor: BrandColors.error,
              ),
            );
          }
          return;
        }
      }
    }

    // Show dialog asking whether to migrate files
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Chat Folder'),
        content: const Text(
          'Do you want to copy your existing files to the new location?\n\n'
          '• Copy files - Brings all your sessions and assets to the new folder\n\n'
          '• Don\'t copy - Use the new location as-is (good for switching to an existing vault)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'change_only'),
            child: const Text('Don\'t Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'migrate'),
            child: const Text('Copy Files'),
          ),
        ],
      ),
    );

    if (choice == null) return;
    final shouldMigrate = choice == 'migrate';

    // Use standard file picker for all platforms
    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Your Chat Folder',
    );

    if (selectedDirectory != null) {
      // Show loading indicator only if migrating
      if (shouldMigrate && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(BrandColors.softWhite),
                  ),
                ),
                SizedBox(width: Spacing.lg),
                const Text('Copying files to new location...'),
              ],
            ),
            duration: const Duration(minutes: 5),
          ),
        );
      }

      final oldPath = await fileSystemService.getRootPathDisplay();
      final success = await fileSystemService.setRootPath(
        selectedDirectory,
        migrateFiles: shouldMigrate,
      );

      // Clear the loading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      if (success) {
        final displayPath = await fileSystemService.getRootPathDisplay();
        setState(() => _rootPath = displayPath);
        // Reset file browser to new root
        ref.read(currentBrowsePathProvider.notifier).state = '';
        ref.read(folderRefreshTriggerProvider.notifier).state++;

        if (mounted) {
          if (shouldMigrate) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Files copied successfully!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: Spacing.xs),
                    Text(
                      'Location: $displayPath',
                      style: TextStyle(fontSize: TypographyTokens.bodySmall),
                    ),
                    SizedBox(height: Spacing.xs),
                    Text(
                      'Old files remain at: $oldPath',
                      style: TextStyle(fontSize: TypographyTokens.bodySmall),
                    ),
                  ],
                ),
                backgroundColor: BrandColors.success,
                duration: const Duration(seconds: 10),
                action: SnackBarAction(
                  label: 'Got it',
                  textColor: BrandColors.softWhite,
                  onPressed: () {},
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Location changed to: $displayPath'),
                backgroundColor: BrandColors.success,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to set up Chat folder location'),
              backgroundColor: BrandColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveSubfolderNames() async {
    final newAssetsName = _assetsFolderNameController.text.trim();
    final newSessionsName = _sessionsFolderNameController.text.trim();

    // Validate folder names
    if (newAssetsName.isEmpty || newSessionsName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Folder names cannot be empty'),
          backgroundColor: BrandColors.error,
        ),
      );
      return;
    }

    if (newAssetsName.contains('/') || newSessionsName.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Folder names cannot contain slashes'),
          backgroundColor: BrandColors.error,
        ),
      );
      return;
    }

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final success = await fileSystemService.setSubfolderNames(
        assetsFolderName: newAssetsName,
        sessionsFolderName: newSessionsName,
      );

      if (success && mounted) {
        setState(() {
          _assetsFolderName = newAssetsName;
          _sessionsFolderName = newSessionsName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Folder names updated successfully!'),
            backgroundColor: BrandColors.success,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to update folder names'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Storage',
          icon: Icons.folder_open,
        ),
        SizedBox(height: Spacing.lg),

        // Chat Folder Section
        const SettingsSubsectionHeader(
          title: 'Chat Folder',
          subtitle:
              'Your chat sessions, generated images, and personal contexts are stored here. '
              'Choose a location you can sync with iCloud, Syncthing, Dropbox, etc.',
        ),
        SizedBox(height: Spacing.lg),

        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: BrandColors.turquoise.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: BrandColors.turquoise, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_open, color: BrandColors.turquoiseDeep),
                  SizedBox(width: Spacing.sm),
                  Text(
                    'Current folder',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.sm),
              Text(
                _rootPath,
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  fontFamily: 'monospace',
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),

              // Show helper notice if using app container
              if (_rootPath.contains('/Library/Containers/')) ...[
                SizedBox(height: Spacing.md),
                Container(
                  padding: EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: BrandColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(
                      color: BrandColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: BrandColors.warning,
                            size: 16,
                          ),
                          SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'Want to use ~/Parachute/Chat instead?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: BrandColors.warning,
                                fontSize: TypographyTokens.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: Spacing.sm),
                      Text(
                        'To sync with iCloud, Obsidian, or other apps, tap "Change Location" '
                        'below and navigate to ~/Parachute/Chat. Create the folder if needed.',
                        style: TextStyle(
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                          fontSize: TypographyTokens.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _chooseChatFolder,
                      icon: const Icon(Icons.folder, size: 18),
                      label: const Text('Change Location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.turquoise,
                      ),
                    ),
                  ),
                  SizedBox(width: Spacing.sm),
                  FilledButton.icon(
                    onPressed: _openChatFolder,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open'),
                    style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.turquoiseDeep,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        SizedBox(height: Spacing.xxl),

        // Subfolder Names Section
        const SettingsSubsectionHeader(
          title: 'Subfolder Names',
          subtitle:
              'Customize folder names within your Chat module',
        ),
        SizedBox(height: Spacing.lg),

        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurfaceElevated
                : BrandColors.stone.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.3)
                  : BrandColors.driftwood.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sessions folder name
              Row(
                children: [
                  Icon(
                    Icons.chat,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  SizedBox(width: Spacing.sm),
                  Text(
                    'Chat sessions folder',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.sm),
              TextField(
                controller: _sessionsFolderNameController,
                decoration: InputDecoration(
                  hintText: 'e.g., sessions, chats, conversations',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  prefixIcon: const Icon(Icons.chat, size: 18),
                ),
              ),

              SizedBox(height: Spacing.xl),

              // Assets folder name
              Row(
                children: [
                  Icon(
                    Icons.perm_media,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  SizedBox(width: Spacing.sm),
                  Text(
                    'Media assets folder',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.sm),
              TextField(
                controller: _assetsFolderNameController,
                decoration: InputDecoration(
                  hintText: 'e.g., assets, media, attachments',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  prefixIcon: const Icon(Icons.perm_media, size: 18),
                ),
              ),

              SizedBox(height: Spacing.lg),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _assetsFolderNameController.text = 'assets';
                        _sessionsFolderNameController.text = 'sessions';
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reset to Default'),
                    ),
                  ),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saveSubfolderNames,
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Save Names'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.success,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: Spacing.md),

              SettingsInfoBanner(
                message:
                    'Sessions store your AI chat history. Assets store generated images and audio.',
                color: BrandColors.turquoise,
              ),
            ],
          ),
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
