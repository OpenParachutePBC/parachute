import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/file_system_provider.dart';
import './settings_section_header.dart';

/// Storage settings section (Parachute folder and subfolder names)
class StorageSection extends ConsumerStatefulWidget {
  const StorageSection({super.key});

  @override
  ConsumerState<StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<StorageSection> {
  String _syncFolderPath = '';
  String _capturesFolderName = 'captures';
  final TextEditingController _capturesFolderNameController =
      TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _capturesFolderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    await fileSystemService.initialize();
    _syncFolderPath = await fileSystemService.getRootPathDisplay();
    _capturesFolderName = fileSystemService.getCapturesFolderName();
    _capturesFolderNameController.text = _capturesFolderName;

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
    // Show warning dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Parachute Folder'),
        content: const Text(
          'This will copy all your recordings and transcripts to the new location. '
          'This may take a while depending on how much data you have.\n\n'
          'Your original files will remain in the old location until you manually delete them.\n\n'
          'Make sure you have enough space in the new location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      // Show loading indicator
      if (mounted) {
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
                const Text('Migrating files to new location...'),
              ],
            ),
            duration: const Duration(minutes: 5),
          ),
        );
      }

      final fileSystemService = ref.read(fileSystemServiceProvider);
      final oldPath = await fileSystemService.getRootPathDisplay();
      final success = await fileSystemService.setRootPath(selectedDirectory);

      // Clear the loading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }

      if (success) {
        final displayPath = await fileSystemService.getRootPathDisplay();
        setState(() => _syncFolderPath = displayPath);
        if (mounted) {
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
                    'New location: $displayPath',
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
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to migrate files to new location'),
              backgroundColor: BrandColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveSubfolderNames() async {
    final newCapturesName = _capturesFolderNameController.text.trim();

    // Validate folder name
    if (newCapturesName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Folder name cannot be empty'),
          backgroundColor: BrandColors.error,
        ),
      );
      return;
    }

    if (newCapturesName.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Folder name cannot contain slashes'),
          backgroundColor: BrandColors.error,
        ),
      );
      return;
    }

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final success = await fileSystemService.setSubfolderNames(
        capturesFolderName: newCapturesName,
      );

      if (success && mounted) {
        setState(() {
          _capturesFolderName = newCapturesName;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Folder name updated successfully!'),
            backgroundColor: BrandColors.success,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to update folder name'),
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
              Row(
                children: [
                  Icon(
                    Icons.folder_special,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  SizedBox(width: Spacing.sm),
                  Text(
                    'Recordings folder name',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
              SizedBox(height: Spacing.sm),
              TextField(
                controller: _capturesFolderNameController,
                decoration: InputDecoration(
                  hintText: 'e.g., captures, notes, recordings',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  prefixIcon: const Icon(Icons.mic, size: 18),
                ),
              ),

              SizedBox(height: Spacing.lg),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _capturesFolderNameController.text = 'captures';
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
                      label: const Text('Save Name'),
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
                    'Use a custom name like "Parachute Captures" '
                    'to avoid conflicts with your existing note folders',
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
