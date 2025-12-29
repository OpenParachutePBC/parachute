import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';

/// Vault picker step - allows users to choose their vault location
///
/// Users can use the default ~/Parachute folder or choose an existing
/// Obsidian/Logseq vault folder.
class VaultPickerStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const VaultPickerStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<VaultPickerStep> createState() => _VaultPickerStepState();
}

class _VaultPickerStepState extends ConsumerState<VaultPickerStep> {
  String _currentPath = 'Loading...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final location = await fileSystemService.getRootPathDisplay();
    if (mounted) {
      setState(() => _currentPath = location);
    }
  }

  Future<void> _pickFolder() async {
    setState(() => _isLoading = true);

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);

      // On Android, ensure we have storage permission first
      if (Platform.isAndroid) {
        final hasPermission = await fileSystemService.hasStoragePermission();
        if (!hasPermission && mounted) {
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

          if (requestPermission != true) {
            setState(() => _isLoading = false);
            return;
          }

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
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose Your Vault Folder',
      );

      if (result != null && mounted) {
        await fileSystemService.setCustomRootPath(result);
        await _loadCurrentPath();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _useDefault() async {
    setState(() => _isLoading = true);

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      await fileSystemService.resetToDefaultPath();
      await _loadCurrentPath();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: Spacing.xl),

            // Folder icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDark
                        ? BrandColors.nightForest.withValues(alpha: 0.3)
                        : BrandColors.forestMist,
                    isDark
                        ? BrandColors.nightTurquoise.withValues(alpha: 0.2)
                        : BrandColors.turquoiseMist,
                  ],
                ),
                borderRadius: BorderRadius.circular(Radii.xl),
                boxShadow: isDark ? null : Elevation.cardShadow,
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 48,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),

            SizedBox(height: Spacing.xxl),

            // Heading
            Text(
              'Choose Your Vault',
              style: TextStyle(
                fontSize: TypographyTokens.displaySmall,
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.md),

            // Subtitle
            Text(
              'Use your existing Obsidian vault or create a new folder',
              style: TextStyle(
                fontSize: TypographyTokens.bodyLarge,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.xxl),

            // Current path display
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurface.withValues(alpha: 0.5)
                    : BrandColors.softWhite,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: isDark
                      ? BrandColors.nightForest.withValues(alpha: 0.3)
                      : BrandColors.stone.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Location',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                  SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.folder,
                        size: 20,
                        color: isDark
                            ? BrandColors.nightForest
                            : BrandColors.forest,
                      ),
                      SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          _currentPath,
                          style: TextStyle(
                            fontSize: TypographyTokens.bodyMedium,
                            fontFamily: 'monospace',
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: Spacing.xl),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _useDefault,
                    icon: const Icon(Icons.home_outlined, size: 20),
                    label: const Text('Use Default'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? BrandColors.nightForest
                          : BrandColors.forest,
                      side: BorderSide(
                        color: isDark
                            ? BrandColors.nightForest.withValues(alpha: 0.5)
                            : BrandColors.forest.withValues(alpha: 0.5),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: Spacing.md,
                        horizontal: Spacing.lg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: Spacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('Choose Folder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark
                          ? BrandColors.nightForest
                          : BrandColors.forest,
                      foregroundColor: BrandColors.softWhite,
                      padding: EdgeInsets.symmetric(
                        vertical: Spacing.md,
                        horizontal: Spacing.lg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: Spacing.xxl),

            // Compatibility badge
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
                    : BrandColors.turquoiseMist,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(
                  color: isDark
                      ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
                      : BrandColors.turquoise.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: isDark
                        ? BrandColors.nightTurquoise
                        : BrandColors.turquoiseDeep,
                  ),
                  SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Text(
                      'Works with Obsidian, Logseq, and other markdown vaults',
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTurquoise
                            : BrandColors.turquoiseDeep,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: Spacing.lg),

            // Info text
            Text(
              'Parachute stores journals, chats, and audio in your vault',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                    : BrandColors.driftwood.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: Spacing.xxxl),

            // Loading indicator
            if (_isLoading)
              Padding(
                padding: EdgeInsets.only(bottom: Spacing.lg),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                ),
              ),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : widget.onNext,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isDark ? BrandColors.nightForest : BrandColors.forest,
                  foregroundColor: BrandColors.softWhite,
                  padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                ),
                child: Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyLarge,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            SizedBox(height: Spacing.md),

            // Back and Skip row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  label: Text(
                    'Back',
                    style: TextStyle(
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  child: const Text('Skip setup'),
                ),
              ],
            ),

            SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}
