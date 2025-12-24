import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/features/recorder/providers/transcription_init_provider.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
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

  // Size estimates
  static const int _parakeetSizeMB = 500;
  int get _embeddingSizeMB => getEmbeddingModelSizeMB(); // Platform-specific
  int get _totalSizeMB => _parakeetSizeMB + _embeddingSizeMB;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storageService = ref.read(storageServiceProvider);
    _autoTranscribe = await storageService.getAutoTranscribe();

    if (mounted) {
      setState(() => _isLoadingSettings = false);
    }
  }

  Future<void> _setAutoTranscribe(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoTranscribe(enabled);
    setState(() => _autoTranscribe = enabled);
  }

  Future<void> _downloadBothModels() async {
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
    final allReady = parakeetReady && embeddingReady;
    final anyDownloading = transcriptionState.isInProgress ||
        embeddingStatus.isDownloading ||
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
              ? 'Voice transcription and semantic search ready'
              : 'Download for offline AI features',
          icon: Icons.auto_awesome,
        ),
        SizedBox(height: Spacing.xl),

        // Combined status card
        _buildStatusCard(
          isDark: isDark,
          parakeetReady: parakeetReady,
          embeddingReady: embeddingReady,
          transcriptionState: transcriptionState,
          embeddingStatus: embeddingStatus,
        ),
        SizedBox(height: Spacing.xl),

        // Download button (if any models missing)
        if (!allReady && !anyDownloading) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _downloadBothModels,
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
        if (isReady)
          Icon(Icons.check_circle, color: BrandColors.success, size: 24)
        else if (isDownloading)
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
