import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/embedding_provider.dart';
import 'package:parachute_chat/core/providers/title_generation_provider.dart';
import 'package:parachute_chat/core/models/title_generation_models.dart';
import 'package:parachute_chat/features/recorder/providers/transcription_init_provider.dart';
import 'package:parachute_chat/features/recorder/providers/service_providers.dart';
import './settings_section_header.dart';

/// Unified Local AI Models section combining Parakeet and EmbeddingGemma
///
/// Shows status of both models and allows downloading them together or separately.
class LocalAiModelsSection extends ConsumerStatefulWidget {
  const LocalAiModelsSection({super.key});

  @override
  ConsumerState<LocalAiModelsSection> createState() =>
      _LocalAiModelsSectionState();
}

class _LocalAiModelsSectionState extends ConsumerState<LocalAiModelsSection> {
  bool _autoTranscribe = false;
  bool _isLoadingSettings = true;
  bool _isDownloadingBoth = false;

  // Gemma text model state (for AI enhance/cleanup)
  bool _gemmaTextReady = false;
  bool _gemmaTextDownloading = false;
  double _gemmaTextProgress = 0.0;

  // Ollama status (desktop only)
  bool _ollamaAvailable = false;
  bool _ollamaHasModel = false;
  String? _ollamaModel;

  // Size estimates
  static const int _parakeetSizeMB = 500;
  int get _embeddingSizeMB => getEmbeddingModelSizeMB(); // Platform-specific
  static const int _gemmaTextSizeMB = 555; // Gemma 1B
  int get _totalSizeMB => _parakeetSizeMB + _embeddingSizeMB + _gemmaTextSizeMB;

  // Check if we're on desktop (uses Ollama instead of local Gemma)
  bool get _isDesktop => Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storageService = ref.read(storageServiceProvider);
    _autoTranscribe = await storageService.getAutoTranscribe();

    // Check if Gemma text model is downloaded (mobile only)
    if (!_isDesktop) {
      final gemmaManager = ref.read(gemmaModelManagerProvider);
      _gemmaTextReady = await gemmaManager.isModelDownloaded(GemmaModelType.gemma1b);
    } else {
      // Check Ollama status (desktop only)
      await _checkOllamaStatus();
    }

    if (mounted) {
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _checkOllamaStatus() async {
    if (!_isDesktop) return;

    try {
      final ollamaService = ref.read(ollamaCleanupServiceProvider);
      final available = await ollamaService.isAvailable();

      if (available) {
        final models = await ollamaService.getAvailableModels();
        // Check if any suitable model is available
        final hasModel = models.any((m) =>
            m.contains('gemma') || m.contains('llama') || m.contains('mistral'));

        String? model;
        if (hasModel && models.isNotEmpty) {
          // Get the saved preference or default to first matching model
          final storageService = ref.read(storageServiceProvider);
          model = await storageService.getOllamaModel();
          model ??= models.firstWhere(
            (m) => m.contains('gemma'),
            orElse: () => models.first,
          );
        }

        if (mounted) {
          setState(() {
            _ollamaAvailable = available;
            _ollamaHasModel = hasModel;
            _ollamaModel = model;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _ollamaAvailable = false;
            _ollamaHasModel = false;
            _ollamaModel = null;
          });
        }
      }
    } catch (e) {
      debugPrint('[LocalAiModelsSection] Ollama check failed: $e');
      if (mounted) {
        setState(() {
          _ollamaAvailable = false;
          _ollamaHasModel = false;
          _ollamaModel = null;
        });
      }
    }
  }

  Future<void> _setAutoTranscribe(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoTranscribe(enabled);
    setState(() => _autoTranscribe = enabled);
  }

  /// Download Gemma text model (for AI enhance/cleanup)
  Future<void> _downloadGemmaTextModel() async {
    if (_isDesktop) return; // Desktop uses Ollama

    setState(() {
      _gemmaTextDownloading = true;
      _gemmaTextProgress = 0.0;
    });

    try {
      final gemmaManager = ref.read(gemmaModelManagerProvider);

      await for (final progress in gemmaManager.downloadModel(GemmaModelType.gemma1b)) {
        if (mounted) {
          setState(() => _gemmaTextProgress = progress);
        }
      }

      // Set as preferred model
      final storageService = ref.read(storageServiceProvider);
      await storageService.setPreferredGemmaModel(GemmaModelType.gemma1b.modelName);

      if (mounted) {
        setState(() {
          _gemmaTextReady = true;
          _gemmaTextDownloading = false;
        });
      }
    } catch (e) {
      debugPrint('[LocalAiModelsSection] Gemma text download failed: $e');
      if (mounted) {
        setState(() => _gemmaTextDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  /// Reinstall Gemma text model (force re-download)
  Future<void> _reinstallGemmaTextModel() async {
    if (_isDesktop) return; // Desktop uses Ollama

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reinstall AI Model?'),
        content: const Text(
          'This will re-download the Gemma 1B model (~555 MB). '
          'Use this if the model is corrupted or not working properly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reinstall'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _gemmaTextDownloading = true;
      _gemmaTextProgress = 0.0;
      _gemmaTextReady = false; // Mark as not ready during reinstall
    });

    try {
      final gemmaManager = ref.read(gemmaModelManagerProvider);

      await for (final progress in gemmaManager.reinstallModel(GemmaModelType.gemma1b)) {
        if (mounted) {
          setState(() => _gemmaTextProgress = progress);
        }
      }

      // Set as preferred model
      final storageService = ref.read(storageServiceProvider);
      await storageService.setPreferredGemmaModel(GemmaModelType.gemma1b.modelName);

      if (mounted) {
        setState(() {
          _gemmaTextReady = true;
          _gemmaTextDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Model reinstalled! Please restart the app.'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('[LocalAiModelsSection] Gemma text reinstall failed: $e');
      if (mounted) {
        setState(() => _gemmaTextDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reinstall failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadAllModels() async {
    setState(() => _isDownloadingBoth = true);

    try {
      // Download Parakeet
      final parakeetState = ref.read(transcriptionInitProvider);
      if (!parakeetState.isReady) {
        await ref.read(transcriptionInitProvider.notifier).downloadAndInitialize();
      }

      // Download EmbeddingGemma using the status notifier
      final embeddingStatus = ref.read(embeddingModelStatusProvider);
      if (!embeddingStatus.isReady) {
        await ref.read(embeddingModelStatusProvider.notifier).download();
      }

      // Download Gemma text model (mobile only)
      if (!_isDesktop && !_gemmaTextReady) {
        await _downloadGemmaTextModel();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Local AI models downloaded successfully!'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingBoth = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Watch model states
    final transcriptionState = ref.watch(transcriptionInitProvider);
    final embeddingStatus = ref.watch(embeddingModelStatusProvider);

    final parakeetReady = transcriptionState.isReady;
    final embeddingReady = embeddingStatus.isReady;
    // On desktop, Gemma text is handled by Ollama; on mobile, by local Gemma
    final gemmaTextReady = _isDesktop ? (_ollamaAvailable && _ollamaHasModel) : _gemmaTextReady;
    final allReady = parakeetReady && embeddingReady && gemmaTextReady;
    final anyDownloading = transcriptionState.isInProgress ||
        embeddingStatus.isDownloading ||
        _gemmaTextDownloading ||
        _isDownloadingBoth;

    if (_isLoadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(
          title: 'Local AI Models',
          subtitle: allReady
              ? 'Voice, search, enhance, and Q&A ready'
              : 'Download for offline AI features',
          icon: Icons.auto_awesome,
        ),
        SizedBox(height: Spacing.xl),

        // Combined status card
        _buildStatusCard(
          isDark: isDark,
          parakeetReady: parakeetReady,
          embeddingReady: embeddingReady,
          gemmaTextReady: gemmaTextReady,
          transcriptionState: transcriptionState,
          embeddingStatus: embeddingStatus,
        ),
        SizedBox(height: Spacing.xl),

        // Download button (if any models missing)
        if (!allReady && !anyDownloading) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadAllModels,
              icon: const Icon(Icons.download),
              label: Text(
                allReady
                    ? 'All Models Ready'
                    : 'Download All (~$_totalSizeMB MB)',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.turquoise,
                padding: EdgeInsets.symmetric(vertical: Spacing.md),
              ),
            ),
          ),
          SizedBox(height: Spacing.md),
        ],

        // Downloading indicator
        if (anyDownloading) ...[
          _buildDownloadProgress(isDark, transcriptionState, embeddingStatus),
          SizedBox(height: Spacing.xl),
        ],

        // Auto-transcribe toggle (only show if Parakeet ready)
        if (parakeetReady) ...[
          const Divider(),
          SizedBox(height: Spacing.lg),
          _buildAutoTranscribeToggle(isDark),
        ],

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildStatusCard({
    required bool isDark,
    required bool parakeetReady,
    required bool embeddingReady,
    required bool gemmaTextReady,
    required TranscriptionInitState transcriptionState,
    required EmbeddingStatusState embeddingStatus,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.stone,
        ),
      ),
      child: Column(
        children: [
          // Parakeet status row
          _buildModelStatusRow(
            isDark: isDark,
            title: 'Voice Transcription',
            subtitle: 'Parakeet v3 (~$_parakeetSizeMB MB)',
            icon: Icons.record_voice_over,
            isReady: parakeetReady,
            isDownloading: transcriptionState.isInProgress,
            progress: transcriptionState.progress,
            onDownload: parakeetReady
                ? null
                : () => ref.read(transcriptionInitProvider.notifier).downloadAndInitialize(),
          ),
          Divider(height: Spacing.xl),
          // EmbeddingGemma status row
          _buildModelStatusRow(
            isDark: isDark,
            title: 'Semantic Search',
            subtitle: 'EmbeddingGemma (~$_embeddingSizeMB MB)',
            icon: Icons.search,
            isReady: embeddingReady,
            isDownloading: embeddingStatus.isDownloading,
            progress: embeddingStatus.progress,
            onDownload: embeddingReady
                ? null
                : () => ref.read(embeddingModelStatusProvider.notifier).download(),
          ),
          // Gemma text model row (mobile only - desktop uses Ollama)
          if (!_isDesktop) ...[
            Divider(height: Spacing.xl),
            _buildModelStatusRow(
              isDark: isDark,
              title: 'AI Enhance & Ask',
              subtitle: 'Gemma 1B (~$_gemmaTextSizeMB MB)',
              icon: Icons.auto_awesome,
              isReady: _gemmaTextReady,
              isDownloading: _gemmaTextDownloading,
              progress: _gemmaTextProgress,
              onDownload: _gemmaTextReady ? null : _downloadGemmaTextModel,
              onReinstall: _gemmaTextReady ? _reinstallGemmaTextModel : null,
            ),
          ],
          // Ollama status row (desktop only)
          if (_isDesktop) ...[
            Divider(height: Spacing.xl),
            _buildOllamaStatusRow(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildModelStatusRow({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isReady,
    required bool isDownloading,
    required double progress,
    VoidCallback? onDownload,
    VoidCallback? onReinstall,
  }) {
    final color = isReady
        ? BrandColors.success
        : isDownloading
            ? BrandColors.turquoise
            : BrandColors.warning;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              SizedBox(height: Spacing.xs),
              if (isDownloading && progress > 0)
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: BrandColors.stone,
                  valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
                )
              else
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
        SizedBox(width: Spacing.md),
        if (isReady) ...[
          Icon(Icons.check_circle, color: BrandColors.success, size: 24),
          if (onReinstall != null) ...[
            SizedBox(width: Spacing.xs),
            IconButton(
              onPressed: onReinstall,
              icon: Icon(Icons.refresh, color: BrandColors.driftwood, size: 20),
              tooltip: 'Reinstall model',
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ] else if (isDownloading)
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
            ),
          )
        else if (onDownload != null)
          IconButton(
            onPressed: onDownload,
            icon: Icon(Icons.download, color: BrandColors.turquoise),
            tooltip: 'Download',
          ),
      ],
    );
  }

  Widget _buildOllamaStatusRow(bool isDark) {
    final isReady = _ollamaAvailable && _ollamaHasModel;
    final color = isReady
        ? BrandColors.success
        : _ollamaAvailable
            ? BrandColors.warning
            : BrandColors.error;

    String subtitle;
    if (isReady) {
      subtitle = 'Ollama ready (${_ollamaModel ?? 'gemma3:4b'})';
    } else if (_ollamaAvailable) {
      subtitle = 'Ollama running, but no model installed';
    } else {
      subtitle = 'Ollama not running';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Icon(Icons.auto_awesome, color: color, size: 20),
            ),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Enhance & Ask',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  SizedBox(height: Spacing.xs),
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
            SizedBox(width: Spacing.md),
            if (isReady)
              Icon(Icons.check_circle, color: BrandColors.success, size: 24)
            else
              IconButton(
                onPressed: _checkOllamaStatus,
                icon: Icon(Icons.refresh, color: color),
                tooltip: 'Refresh status',
              ),
          ],
        ),
        // Help text if not ready
        if (!isReady) ...[
          SizedBox(height: Spacing.md),
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ollamaAvailable
                      ? 'Install a model:'
                      : 'Install and start Ollama:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: Spacing.sm),
                if (!_ollamaAvailable) ...[
                  _buildCommandLine('brew install ollama', isDark),
                  SizedBox(height: Spacing.xs),
                  _buildCommandLine('ollama serve', isDark),
                  SizedBox(height: Spacing.xs),
                ],
                _buildCommandLine('ollama pull gemma3:4b', isDark),
                SizedBox(height: Spacing.sm),
                Text(
                  'Then tap refresh to check status.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: BrandColors.driftwood,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCommandLine(String command, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 14, color: BrandColors.driftwood),
          SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: TypographyTokens.labelSmall,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(
    bool isDark,
    TranscriptionInitState transcriptionState,
    EmbeddingStatusState embeddingStatus,
  ) {
    String status = 'Downloading...';
    if (transcriptionState.isInProgress) {
      status = transcriptionState.statusMessage.isNotEmpty
          ? transcriptionState.statusMessage
          : 'Downloading voice transcription...';
    } else if (embeddingStatus.isDownloading) {
      status = 'Downloading semantic search...';
    } else if (_gemmaTextDownloading) {
      status = 'Downloading AI enhance model (${(_gemmaTextProgress * 100).toStringAsFixed(0)}%)...';
    }

    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.turquoise.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: BrandColors.turquoise.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
            ),
          ),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                color: BrandColors.turquoise,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoTranscribeToggle(bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: _autoTranscribe
            ? BrandColors.forest.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: SwitchListTile(
        title: Text(
          'Auto-transcribe recordings',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        subtitle: Text(
          'Automatically transcribe after recording stops',
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark
                ? BrandColors.nightTextSecondary
                : BrandColors.driftwood,
          ),
        ),
        value: _autoTranscribe,
        onChanged: _setAutoTranscribe,
        activeTrackColor: BrandColors.forest,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
