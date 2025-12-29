import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/core/services/conversation_import_service.dart';
import 'package:parachute_chat/features/context/providers/context_providers.dart';

/// Import step for onboarding - guides users through importing Claude history
///
/// Provides step-by-step instructions for exporting from Claude
/// and handles the import with streaming progress.
class ImportStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const ImportStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<ImportStep> createState() => _ImportStepState();
}

enum _ImportSource { none, claude, chatgpt }

enum _ImportPhase { selectSource, instructions, importing, complete }

class _ImportStepState extends ConsumerState<ImportStep> {
  _ImportSource _selectedSource = _ImportSource.none;
  _ImportPhase _phase = _ImportPhase.selectSource;

  // Scan results
  ImportScanResult? _scanResult;

  // Import progress
  String _progressTitle = '';
  double _progressValue = 0;
  int _processedCount = 0;
  int _totalCount = 0;

  // Results
  int _importedConversations = 0;
  int _importedContexts = 0;
  String? _error;

  // Existing imports detection
  bool _isCheckingExisting = true;
  int _existingClaudeImports = 0;
  int _existingChatGPTImports = 0;

  @override
  void initState() {
    super.initState();
    _checkExistingImports();
  }

  /// Check for existing imported conversations in the vault
  Future<void> _checkExistingImports() async {
    try {
      final fileSystem = ref.read(fileSystemServiceProvider);
      final sessionsPath = await fileSystem.getSessionsPath();
      final importedPath = p.join(sessionsPath, 'imported');

      final importedDir = Directory(importedPath);
      if (await importedDir.exists()) {
        final files = await importedDir.list().toList();

        int claudeCount = 0;
        int chatgptCount = 0;

        for (final file in files) {
          if (file is File && file.path.endsWith('.md')) {
            final basename = p.basename(file.path);
            if (basename.startsWith('claude-')) {
              claudeCount++;
            } else if (basename.startsWith('chatgpt-')) {
              chatgptCount++;
            }
          }
        }

        if (mounted) {
          setState(() {
            _existingClaudeImports = claudeCount;
            _existingChatGPTImports = chatgptCount;
            _isCheckingExisting = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isCheckingExisting = false);
        }
      }
    } catch (e) {
      debugPrint('[ImportStep] Error checking existing imports: $e');
      if (mounted) {
        setState(() => _isCheckingExisting = false);
      }
    }
  }

  bool get _hasExistingImports =>
      _existingClaudeImports > 0 || _existingChatGPTImports > 0;

  int get _totalExistingImports =>
      _existingClaudeImports + _existingChatGPTImports;

  /// Ensure AGENTS.md exists before moving to next step
  Future<void> _ensureAgentsMdAndContinue() async {
    try {
      final needsSetup = await ref.read(vaultNeedsSetupProvider.future);
      if (needsSetup) {
        // Create default AGENTS.md and prompts.yaml
        await ref.read(initializeVaultContextProvider)();
      }
    } catch (e) {
      // Don't block progression if this fails
      debugPrint('[ImportStep] Error creating AGENTS.md: $e');
    }
    widget.onNext();
  }

  /// Skip import but still ensure AGENTS.md exists
  Future<void> _skipAndContinue() async {
    try {
      final needsSetup = await ref.read(vaultNeedsSetupProvider.future);
      if (needsSetup) {
        await ref.read(initializeVaultContextProvider)();
      }
    } catch (e) {
      debugPrint('[ImportStep] Error creating AGENTS.md on skip: $e');
    }
    widget.onSkip();
  }

  void _selectSource(_ImportSource source) {
    setState(() {
      _selectedSource = source;
      _phase = _ImportPhase.instructions;
    });
  }

  void _backToSourceSelect() {
    setState(() {
      _selectedSource = _ImportSource.none;
      _phase = _ImportPhase.selectSource;
      _scanResult = null;
      _error = null;
    });
  }

  Future<void> _openExportSettings() async {
    final url = _selectedSource == _ImportSource.claude
        ? 'https://claude.ai/settings'
        : 'https://chat.openai.com/settings';

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickExportFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        dialogTitle: 'Select your ${_selectedSource == _ImportSource.claude ? 'Claude' : 'ChatGPT'} export',
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        setState(() => _error = 'Could not access file');
        return;
      }

      await _processExport(file.path!);
    } catch (e) {
      setState(() => _error = 'Error selecting file: $e');
    }
  }

  Future<void> _pickExportFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your ${_selectedSource == _ImportSource.claude ? 'Claude' : 'ChatGPT'} export folder',
      );

      if (path == null) return;

      await _processExportFolder(path);
    } catch (e) {
      setState(() => _error = 'Error selecting folder: $e');
    }
  }

  Future<void> _processExport(String zipPath) async {
    setState(() {
      _phase = _ImportPhase.importing;
      _progressTitle = 'Extracting export...';
      _progressValue = 0;
      _error = null;
    });

    String? tempExportPath;

    try {
      // Extract to a temp directory - NOT the imports folder
      final tempDir = await Directory.systemTemp.createTemp('parachute_import_');
      tempExportPath = tempDir.path;

      // Read and decode the zip
      final zipFile = File(zipPath);
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Extract only what we need (skip images for ChatGPT)
      int extracted = 0;
      final filesToExtract = archive.files.where((f) {
        if (!f.isFile) return false;
        // Skip image files for ChatGPT exports
        if (_selectedSource == _ImportSource.chatgpt) {
          final ext = p.extension(f.name).toLowerCase();
          if (['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'].contains(ext)) {
            return false;
          }
          // Skip image directories
          if (f.name.contains('dalle-generations/')) return false;
        }
        return true;
      }).toList();

      final totalFiles = filesToExtract.length;

      for (final file in filesToExtract) {
        final filename = file.name;
        final filePath = p.join(tempExportPath, filename);
        final outFile = File(filePath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);

        extracted++;
        setState(() {
          _progressTitle = 'Extracting: ${p.basename(filename)}';
          _progressValue = extracted / totalFiles * 0.3; // 30% for extraction
        });
      }

      await _scanAndImport(tempExportPath, cleanupPath: tempExportPath);
    } catch (e) {
      // Clean up temp on error
      if (tempExportPath != null) {
        try {
          await Directory(tempExportPath).delete(recursive: true);
        } catch (_) {}
      }
      setState(() {
        _error = 'Error processing export: $e';
        _phase = _ImportPhase.instructions;
      });
    }
  }

  Future<void> _processExportFolder(String folderPath) async {
    setState(() {
      _phase = _ImportPhase.importing;
      _progressTitle = 'Scanning export...';
      _progressValue = 0;
      _error = null;
    });

    try {
      // Process directly from source - no copying needed!
      // The import service reads the JSON and creates markdown files in agent-sessions/
      await _scanAndImport(folderPath);
    } catch (e) {
      setState(() {
        _error = 'Error processing folder: $e';
        _phase = _ImportPhase.instructions;
      });
    }
  }

  Future<void> _scanAndImport(String exportPath, {String? cleanupPath}) async {
    final importService = ref.read(conversationImportServiceProvider);

    // Scan
    setState(() {
      _progressTitle = 'Analyzing export...';
      _progressValue = 0.35;
    });

    ImportScanResult scanResult;
    if (_selectedSource == _ImportSource.claude) {
      scanResult = await importService.scanClaudeExport(exportPath);
    } else {
      scanResult = await importService.scanChatGPTExport(exportPath);
    }

    setState(() => _scanResult = scanResult);

    if (scanResult.nonEmptyCount == 0) {
      setState(() {
        _error = 'No conversations found in export';
        _phase = _ImportPhase.instructions;
      });
      return;
    }

    // Import conversations
    setState(() {
      _progressTitle = 'Importing conversations...';
      _progressValue = 0.4;
    });

    Stream<ImportProgress> progressStream;
    if (_selectedSource == _ImportSource.claude) {
      progressStream = importService.importClaudeConversations(exportPath);
    } else {
      progressStream = importService.importChatGPTConversations(exportPath);
    }

    await for (final progress in progressStream) {
      setState(() {
        _progressTitle = progress.currentTitle;
        _processedCount = progress.processed;
        _totalCount = progress.total;
        _progressValue = 0.4 + (progress.progress * 0.5); // 40-90%
      });

      if (progress.hasError) {
        setState(() {
          _error = progress.error;
          _phase = _ImportPhase.instructions;
        });
        return;
      }

      if (progress.isComplete) {
        _importedConversations = progress.processed;
      }
    }

    // Create context files for Claude
    if (_selectedSource == _ImportSource.claude && scanResult.hasMemories) {
      setState(() {
        _progressTitle = 'Creating context files...';
        _progressValue = 0.95;
      });

      final exportService = ref.read(exportDetectionServiceProvider);
      final contextFiles = await exportService.createAllContextFilesFromClaudeExport(exportPath);
      _importedContexts = contextFiles.length;
    }

    // Extract ChatGPT memory to context
    if (_selectedSource == _ImportSource.chatgpt && scanResult.hasMemories) {
      setState(() {
        _progressTitle = 'Saving your context...';
        _progressValue = 0.95;
      });

      final memory = await importService.extractChatGPTMemory(exportPath);
      if (memory != null) {
        final fileSystem = ref.read(fileSystemServiceProvider);
        final contextsPath = await fileSystem.getContextsPath();
        await fileSystem.ensureContextsFolderExists();

        final contextFile = File(p.join(contextsPath, 'chatgpt-context.md'));
        if (!await contextFile.exists()) {
          await contextFile.writeAsString('''# ChatGPT Context

> Imported from your ChatGPT export

$memory

---
*Imported from ChatGPT memory*
''');
          _importedContexts = 1;
        }
      }
    }

    // Clean up temp directory if one was created
    if (cleanupPath != null) {
      try {
        await Directory(cleanupPath).delete(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }
    }

    setState(() {
      _progressValue = 1.0;
      _phase = _ImportPhase.complete;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: _buildContent(isDark),
            ),
          ),
          _buildBottomButtons(isDark),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    switch (_phase) {
      case _ImportPhase.selectSource:
        return _buildSourceSelection(isDark);
      case _ImportPhase.instructions:
        return _buildInstructions(isDark);
      case _ImportPhase.importing:
        return _buildImporting(isDark);
      case _ImportPhase.complete:
        return _buildComplete(isDark);
    }
  }

  Widget _buildSourceSelection(bool isDark) {
    // Show loading state while checking existing imports
    if (_isCheckingExisting) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: Spacing.xxl * 2),
          const CircularProgressIndicator(),
          SizedBox(height: Spacing.lg),
          Text(
            'Checking for existing imports...',
            style: TextStyle(
              fontSize: TypographyTokens.bodyMedium,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: Spacing.xxl),

        Text(
          'Import from Claude',
          style: TextStyle(
            fontSize: TypographyTokens.headlineLarge,
            fontWeight: FontWeight.bold,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        SizedBox(height: Spacing.md),

        // Show different message if imports already exist
        if (_hasExistingImports) ...[
          // Already imported banner
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: BrandColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: BrandColors.success, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: BrandColors.success, size: 24),
                SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Imports already synced!',
                        style: TextStyle(
                          color: BrandColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: TypographyTokens.bodyMedium,
                        ),
                      ),
                      SizedBox(height: Spacing.xs),
                      Text(
                        '$_totalExistingImports conversation${_totalExistingImports == 1 ? '' : 's'} from your vault',
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
              ],
            ),
          ),
          SizedBox(height: Spacing.lg),
          Text(
            'Your conversation history is already available. '
            'You can import more conversations if you have a new export.',
            style: TextStyle(
              fontSize: TypographyTokens.bodyLarge,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              height: 1.5,
            ),
          ),
        ] else ...[
          Text(
            'Bring your Claude conversations, memories, and project context into Parachute. '
            'Your history becomes searchable and available in all your chats.',
            style: TextStyle(
              fontSize: TypographyTokens.bodyLarge,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              height: 1.5,
            ),
          ),
        ],
        SizedBox(height: Spacing.xxl),

        // Claude card - now the only option
        _buildSourceCard(
          isDark: isDark,
          source: _ImportSource.claude,
          title: _hasExistingImports ? 'Import More Conversations' : 'Import Claude Export',
          subtitle: 'Conversations, memories, and project context',
          icon: Icons.psychology_outlined,
          color: BrandColors.forest,
        ),

        SizedBox(height: Spacing.xxl),

        // What gets imported explanation (only show if no existing imports)
        if (!_hasExistingImports) ...[
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated.withValues(alpha: 0.5)
                  : BrandColors.forestMist.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What gets imported:',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.sm),
                _buildImportItem(isDark, 'Conversations', 'Searchable chat history'),
                _buildImportItem(isDark, 'Memories', 'Context Claude learned about you'),
                _buildImportItem(isDark, 'Projects', 'Project instructions and context'),
              ],
            ),
          ),
          SizedBox(height: Spacing.lg),
        ],

        // Skip note
        Text(
          _hasExistingImports
              ? 'You can continue with your existing imports, or add more from a new export.'
              : 'You can always import later from Settings, or skip to start fresh.',
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildImportItem(bool isDark, String title, String description) {
    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: BrandColors.forest,
          ),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard({
    required bool isDark,
    required _ImportSource source,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return InkWell(
      onTap: () => _selectSource(source),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: TypographyTokens.titleMedium,
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  SizedBox(height: Spacing.xs),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions(bool isDark) {
    final isClaude = _selectedSource == _ImportSource.claude;
    final color = isClaude ? BrandColors.forest : BrandColors.turquoise;
    final title = isClaude ? 'Claude' : 'ChatGPT';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: Spacing.xl),

        // Back button
        TextButton.icon(
          onPressed: _backToSourceSelect,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
          style: TextButton.styleFrom(
            foregroundColor: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        SizedBox(height: Spacing.md),

        Text(
          'Export from $title',
          style: TextStyle(
            fontSize: TypographyTokens.headlineLarge,
            fontWeight: FontWeight.bold,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        SizedBox(height: Spacing.lg),

        // Steps
        _buildStep(isDark, 1, isClaude
            ? 'Go to claude.ai/settings'
            : 'Go to chat.openai.com/settings'),
        _buildStep(isDark, 2, isClaude
            ? 'Click "Export Data" under Account'
            : 'Go to Data Controls'),
        _buildStep(isDark, 3, isClaude
            ? 'Wait for email (usually 2-5 minutes)'
            : 'Click "Export Data" and wait for email'),
        _buildStep(isDark, 4, 'Download and unzip the file'),

        SizedBox(height: Spacing.xl),

        // Open settings button
        OutlinedButton.icon(
          onPressed: _openExportSettings,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text('Open $title Settings'),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
          ),
        ),

        SizedBox(height: Spacing.xxl),

        // File picker section
        Text(
          'When you have the export:',
          style: TextStyle(
            fontSize: TypographyTokens.titleMedium,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        SizedBox(height: Spacing.md),

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickExportFile,
                icon: const Icon(Icons.folder_zip_outlined),
                label: const Text('Select Zip File'),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ),
            SizedBox(width: Spacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickExportFolder,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Select Folder'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ),
          ],
        ),

        if (_error != null) ...[
          SizedBox(height: Spacing.lg),
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: BrandColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: BrandColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: BrandColors.error, size: 20),
                SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: BrandColors.error,
                      fontSize: TypographyTokens.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep(bool isDark, int number, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated
                  : BrandColors.stone.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
            ),
          ),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: Spacing.xs),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyLarge,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImporting(bool isDark) {
    final color = _selectedSource == _ImportSource.claude
        ? BrandColors.forest
        : BrandColors.turquoise;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: Spacing.xxl * 2),

        // Animated progress indicator
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: _progressValue,
                  strokeWidth: 8,
                  backgroundColor: color.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '${(_progressValue * 100).toInt()}%',
                style: TextStyle(
                  fontSize: TypographyTokens.titleLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: Spacing.xl),

        Text(
          _progressTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: TypographyTokens.bodyLarge,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),

        if (_totalCount > 0) ...[
          SizedBox(height: Spacing.sm),
          Text(
            '$_processedCount of $_totalCount',
            style: TextStyle(
              fontSize: TypographyTokens.bodyMedium,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComplete(bool isDark) {
    final color = _selectedSource == _ImportSource.claude
        ? BrandColors.forest
        : BrandColors.turquoise;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: Spacing.xxl * 2),

        // Success icon
        Container(
          padding: EdgeInsets.all(Spacing.xl),
          decoration: BoxDecoration(
            color: BrandColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_outline,
            size: 64,
            color: BrandColors.success,
          ),
        ),

        SizedBox(height: Spacing.xl),

        Text(
          'Import Complete!',
          style: TextStyle(
            fontSize: TypographyTokens.headlineMedium,
            fontWeight: FontWeight.bold,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),

        SizedBox(height: Spacing.lg),

        // Stats
        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Column(
            children: [
              if (_importedConversations > 0)
                _buildStatRow(
                  isDark,
                  Icons.chat_bubble_outline,
                  '$_importedConversations conversations imported',
                  color,
                ),
              if (_importedContexts > 0) ...[
                SizedBox(height: Spacing.md),
                _buildStatRow(
                  isDark,
                  Icons.auto_awesome,
                  '$_importedContexts context file${_importedContexts > 1 ? 's' : ''} created',
                  BrandColors.forest,
                ),
              ],
              if (_scanResult?.hasMemories == true) ...[
                SizedBox(height: Spacing.md),
                _buildStatRow(
                  isDark,
                  Icons.psychology_outlined,
                  'Your AI memory preserved',
                  BrandColors.turquoise,
                ),
              ],
            ],
          ),
        ),

        SizedBox(height: Spacing.xl),

        Text(
          'Your history is now searchable and\navailable to Parachute.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: TypographyTokens.bodyMedium,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(bool isDark, IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: TypographyTokens.bodyMedium,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons(bool isDark) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Row(
        children: [
          if (_phase != _ImportPhase.importing && _phase != _ImportPhase.selectSource)
            TextButton(
              onPressed: _backToSourceSelect,
              child: const Text('Back'),
            ),
          const Spacer(),
          // Show Skip or Continue based on context
          if (_phase == _ImportPhase.selectSource || _phase == _ImportPhase.instructions) ...[
            if (_hasExistingImports && _phase == _ImportPhase.selectSource) ...[
              // When imports exist, show Continue as primary action
              FilledButton(
                onPressed: _skipAndContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                child: const Text('Continue'),
              ),
            ] else ...[
              TextButton(
                onPressed: _skipAndContinue,
                child: const Text('Skip'),
              ),
            ],
          ],
          if (_phase == _ImportPhase.instructions)
            SizedBox(width: Spacing.md),
          if (_phase == _ImportPhase.complete)
            FilledButton(
              onPressed: _ensureAgentsMdAndContinue,
              child: const Text('Continue'),
            ),
        ],
      ),
    );
  }
}
