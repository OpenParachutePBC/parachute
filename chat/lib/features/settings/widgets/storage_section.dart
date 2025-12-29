import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/features/files/providers/file_browser_provider.dart';
import './settings_section_header.dart';

/// Storage settings section (Parachute folder and subfolder names)
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  String _syncFolderPath = '';
  String _journalFolderName = 'Daily';
  String _assetsFolderName = 'assets';
  String _sessionsFolderName = 'agent-sessions';
  final TextEditingController _journalFolderNameController =
      TextEditingController();
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
    _journalFolderNameController.dispose();
    _assetsFolderNameController.dispose();
    _sessionsFolderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    await fileSystemService.initialize();
    _syncFolderPath = await fileSystemService.getRootPathDisplay();
    _journalFolderName = fileSystemService.getJournalFolderName();
    _assetsFolderName = fileSystemService.getAssetsFolderName();
    _sessionsFolderName = fileSystemService.getSessionsFolderName();
    _journalFolderNameController.text = _journalFolderName;
    _assetsFolderNameController.text = _assetsFolderName;
    _sessionsFolderNameController.text = _sessionsFolderName;

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openParachuteFolder() async {
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

  Future<void> _chooseSyncFolder() async {
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
              'Parachute needs access to all files to work with your vault folder.\n\n'
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
    // Returns: 'migrate' to copy files, 'change_only' to just change path, null to cancel
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Parachute Folder'),
        content: const Text(
          'Do you want to copy your existing files to the new location?\n\n'
          '• Copy files - Brings all your recordings and transcripts to the new folder\n\n'
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
      dialogTitle: 'Choose Your Vault Folder',
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
        setState(() => _syncFolderPath = displayPath);
        // Reset file browser to new vault root
        ref.read(currentBrowsePathProvider.notifier).state = '';
        ref.read(folderRefreshTriggerProvider.notifier).state++;
        // Chat doesn't have journal service, only session providers need refresh
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
              content: const Text('Failed to set up vault location'),
              backgroundColor: BrandColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveSubfolderNames() async {
    final newJournalName = _journalFolderNameController.text.trim();
    final newAssetsName = _assetsFolderNameController.text.trim();
    final newSessionsName = _sessionsFolderNameController.text.trim();

    // Validate folder names
    if (newJournalName.isEmpty || newAssetsName.isEmpty || newSessionsName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Folder names cannot be empty'),
          backgroundColor: BrandColors.error,
        ),
      );
      return;
    }

    if (newJournalName.contains('/') || newAssetsName.contains('/') || newSessionsName.contains('/')) {
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
        journalFolderName: newJournalName,
        assetsFolderName: newAssetsName,
        sessionsFolderName: newSessionsName,
      );

      if (success && mounted) {
        setState(() {
          _journalFolderName = newJournalName;
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

        // Parachute Folder Section
        const SettingsSubsectionHeader(
          title: 'Parachute Folder',
          subtitle:
              'All your recordings, transcripts, and spheres are stored here. '
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
                _syncFolderPath,
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  fontFamily: 'monospace',
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),

              // Show helper notice if using app container
              if (_syncFolderPath.contains('/Library/Containers/')) ...[
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
                              'Want to use ~/Parachute instead?',
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
                        'below and select your home folder. Create a "Parachute" folder there '
                        'and select it. This grants the app permission to access it.',
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
                      onPressed: _chooseSyncFolder,
                      icon: const Icon(Icons.folder, size: 18),
                      label: const Text('Change Location'),
                      style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.turquoise,
                      ),
                    ),
                  ),
                  SizedBox(width: Spacing.sm),
                  FilledButton.icon(
                    onPressed: _openParachuteFolder,
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
              'Customize folder names to work with Obsidian, Logseq, or any markdown-based vault',
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
              // Journal folder name
              Row(
                children: [
                  Icon(
                    Icons.book,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  SizedBox(width: Spacing.sm),
                  Text(
                    'Daily journal folder',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.sm),
              TextField(
                controller: _journalFolderNameController,
                decoration: InputDecoration(
                  hintText: 'e.g., Daily, Journal, daily-notes',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  prefixIcon: const Icon(Icons.book, size: 18),
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

              SizedBox(height: Spacing.xl),

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
                    'AI chat sessions folder',
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
                  hintText: 'e.g., Chat/sessions, chats, conversations',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  prefixIcon: const Icon(Icons.chat, size: 18),
                ),
              ),

              SizedBox(height: Spacing.lg),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _journalFolderNameController.text = 'Daily';
                        _assetsFolderNameController.text = 'assets';
                        _sessionsFolderNameController.text = 'Chat/sessions';
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
                    'These folders store your daily notes, audio/images, and AI chat history. '
                    'Customize them to match your existing Obsidian/Logseq setup.',
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
