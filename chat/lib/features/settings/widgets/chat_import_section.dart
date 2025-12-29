import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/core/services/export_detection_service.dart';
import 'package:parachute_chat/core/services/conversation_import_service.dart';
import 'package:parachute_chat/features/chat/providers/chat_providers.dart';
import 'package:parachute_chat/features/context/providers/context_providers.dart';
import './settings_section_header.dart';

/// Chat import section for importing Claude exports
///
/// Supports:
/// - Picking zip files or folders
/// - Extracting to imports folder
/// - Using Claude memories for vault context setup
/// - Importing conversations to view locally
class ChatImportSection extends ConsumerStatefulWidget {
  const ChatImportSection({super.key});

  @override
  ConsumerState<ChatImportSection> createState() => _ChatImportSectionState();
}

class _ChatImportSectionState extends ConsumerState<ChatImportSection> {
  bool _isProcessing = false;
  String? _statusMessage;
  DetectedExport? _detectedExport;
  bool _vaultSetupDone = false;
  bool _conversationsImported = false;

  Future<void> _pickZipFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        _showError('Could not access file');
        return;
      }

      await _processZipFile(file.path!);
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _pickFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return;

      await _processFolder(path);
    } catch (e) {
      _showError('Error picking folder: $e');
    }
  }

  Future<void> _processZipFile(String zipPath) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Extracting...';
      _detectedExport = null;
    });

    try {
      final fileSystem = ref.read(fileSystemServiceProvider);
      final importsPath = await fileSystem.ensureImportsFolderExists();

      // Read and decode the zip
      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Create a folder for this export based on the zip name
      final zipName = p.basenameWithoutExtension(zipPath);
      final exportPath = p.join(importsPath, zipName);
      final exportDir = Directory(exportPath);

      // Remove existing if present
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
      await exportDir.create(recursive: true);

      // Extract files
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final filePath = p.join(exportPath, filename);
          final outFile = File(filePath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }

      setState(() => _statusMessage = 'Detecting export type...');

      // Scan for the new export
      await _scanForExport(exportPath);
    } catch (e) {
      _showError('Error extracting zip: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _processFolder(String folderPath) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Copying...';
      _detectedExport = null;
    });

    try {
      final fileSystem = ref.read(fileSystemServiceProvider);
      final importsPath = await fileSystem.ensureImportsFolderExists();

      // Copy folder to imports
      final folderName = p.basename(folderPath);
      final destPath = p.join(importsPath, folderName);
      final destDir = Directory(destPath);

      // Remove existing if present
      if (await destDir.exists()) {
        await destDir.delete(recursive: true);
      }

      // Copy recursively
      await _copyDirectory(Directory(folderPath), destDir);

      setState(() => _statusMessage = 'Detecting export type...');

      // Scan for the new export
      await _scanForExport(destPath);
    } catch (e) {
      _showError('Error copying folder: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  Future<void> _scanForExport(String exportPath) async {
    final exportService = ref.read(exportDetectionServiceProvider);
    final exports = await exportService.scanForExports();

    // Find the export we just added
    final detected = exports.where((e) => e.path == exportPath).firstOrNull;

    if (mounted) {
      setState(() {
        _detectedExport = detected;
        _statusMessage = null;
      });
    }
  }

  Future<void> _useMemoriesForVault() async {
    if (_detectedExport == null || !_detectedExport!.hasMemories) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Setting up vault...';
    });

    try {
      final exportService = ref.read(exportDetectionServiceProvider);

      // Create context files (general + per-project)
      final contextFiles = await exportService.createAllContextFilesFromClaudeExport(
        _detectedExport!.path,
      );

      // Also initialize vault with memories for AGENTS.md
      final memoriesContext = await exportService.formatClaudeMemoriesAsContext(
        _detectedExport!.path,
      );
      await ref.read(initializeVaultWithMemoriesProvider)(memoriesContext);

      if (mounted) {
        final message = contextFiles.isEmpty
            ? 'Vault initialized (context files already exist)'
            : 'Created ${contextFiles.length} context file${contextFiles.length > 1 ? 's' : ''}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: BrandColors.success,
          ),
        );
        // Don't clear _detectedExport - let user do other actions too
        setState(() {
          _statusMessage = null;
          _vaultSetupDone = true;
        });
      }
    } catch (e) {
      _showError('Error setting up vault: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _importConversations() async {
    if (_detectedExport == null || !_detectedExport!.hasConversations) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Importing conversations...';
    });

    try {
      final convImportService = ref.read(conversationImportServiceProvider);

      int importedCount = 0;
      int skippedCount = 0;

      // Use the new streaming import service
      Stream<ImportProgress> progressStream;
      if (_detectedExport!.type == ExportType.chatgpt) {
        progressStream = convImportService.importChatGPTConversations(_detectedExport!.path);
      } else {
        progressStream = convImportService.importClaudeConversations(_detectedExport!.path);
      }

      await for (final progress in progressStream) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Importing: ${progress.currentTitle}';
          });
        }

        if (progress.isComplete) {
          importedCount = progress.processed;
          // Calculate skipped based on total vs what we expected
          final expectedTotal = _detectedExport!.conversationCount ?? progress.total;
          skippedCount = expectedTotal - importedCount;
        }
      }

      // Refresh chat sessions list
      ref.invalidate(chatSessionsProvider);

      if (mounted) {
        String message;
        if (importedCount == 0 && skippedCount > 0) {
          message = 'All $skippedCount conversations already imported';
        } else if (skippedCount > 0) {
          message = 'Imported $importedCount new, skipped $skippedCount existing';
        } else {
          message = 'Imported $importedCount conversations';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: BrandColors.success,
          ),
        );
        // Don't clear _detectedExport - let user do other actions too
        setState(() {
          _statusMessage = null;
          _conversationsImported = true;
        });
      }
    } catch (e) {
      _showError('Error importing: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _statusMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.error,
      ),
    );
  }

  void _clearDetected() {
    setState(() {
      _detectedExport = null;
      _vaultSetupDone = false;
      _conversationsImported = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Import Claude Export',
          subtitle: 'Bring your conversations, memories, and project context',
          icon: Icons.download_outlined,
        ),
        SizedBox(height: Spacing.lg),

        // Show detected export or picker UI
        if (_detectedExport != null)
          _buildDetectedExportCard(isDark)
        else if (_isProcessing)
          _buildProcessingCard(isDark)
        else
          _buildPickerCards(isDark),

        SizedBox(height: Spacing.md),

        // Instructions
        _buildInstructions(isDark),

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildPickerCards(bool isDark) {
    return Column(
      children: [
        // Zip file picker
        _buildPickerCard(
          isDark: isDark,
          title: 'Import Zip File',
          subtitle: 'Select your downloaded export zip',
          icon: Icons.folder_zip_outlined,
          color: BrandColors.turquoise,
          onTap: _pickZipFile,
        ),
        SizedBox(height: Spacing.md),
        // Folder picker
        _buildPickerCard(
          isDark: isDark,
          title: 'Import Folder',
          subtitle: 'Select an already-extracted export folder',
          icon: Icons.folder_open_outlined,
          color: BrandColors.forest,
          onTap: _pickFolder,
        ),
      ],
    );
  }

  Widget _buildPickerCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.softWhite,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: TypographyTokens.bodyLarge,
                      color: isDark
                          ? BrandColors.nightText
                          : BrandColors.charcoal,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingCard(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: BrandColors.turquoise.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
          SizedBox(height: Spacing.md),
          Text(
            _statusMessage ?? 'Processing...',
            style: TextStyle(
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedExportCard(bool isDark) {
    final export = _detectedExport!;
    final isClaudeWithMemories = export.type == ExportType.claude && export.hasMemories;

    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: BrandColors.success.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: BrandColors.success,
                size: 24,
              ),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${export.displayName} Ready',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: TypographyTokens.bodyLarge,
                        color: isDark
                            ? BrandColors.nightText
                            : BrandColors.charcoal,
                      ),
                    ),
                    Text(
                      export.summary,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearDetected,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ],
          ),
          SizedBox(height: Spacing.lg),

          // Actions based on what's available
          if (isClaudeWithMemories) ...[
            _buildActionButton(
              isDark: isDark,
              title: _vaultSetupDone ? 'Context files created ✓' : 'Create context files',
              subtitle: _vaultSetupDone
                  ? 'Your Claude context is saved'
                  : 'Save memories & project context to vault',
              icon: _vaultSetupDone ? Icons.check_circle : Icons.auto_awesome,
              color: _vaultSetupDone ? BrandColors.success : BrandColors.forest,
              onTap: _isProcessing || _vaultSetupDone ? null : _useMemoriesForVault,
              isPrimary: !_vaultSetupDone,
            ),
            SizedBox(height: Spacing.sm),
          ],
          if (export.hasConversations)
            _buildActionButton(
              isDark: isDark,
              title: _conversationsImported ? 'Conversations imported ✓' : 'Import conversations',
              subtitle: _conversationsImported
                  ? 'Available in your chat history'
                  : export.conversationCount != null
                      ? 'Add ${export.conversationCount} chats to your library'
                      : 'Add chats to your library',
              icon: _conversationsImported ? Icons.check_circle : Icons.chat_bubble_outline,
              color: _conversationsImported ? BrandColors.success : BrandColors.turquoise,
              onTap: _isProcessing || _conversationsImported ? null : _importConversations,
              isPrimary: !isClaudeWithMemories && !_conversationsImported,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    required bool isPrimary,
  }) {
    if (isPrimary) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: EdgeInsets.all(Spacing.md),
          ),
          icon: Icon(icon, size: 20),
          label: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: EdgeInsets.all(Spacing.md),
        ),
        icon: Icon(icon, size: 20, color: color),
        label: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated.withValues(alpha: 0.5)
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              SizedBox(width: Spacing.sm),
              Text(
                'How to get your export',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightText
                      : BrandColors.charcoal,
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.sm),
          Text(
            'Claude: Settings > Account > Export Data',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
        ],
      ),
    );
  }
}
