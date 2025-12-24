import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/features/recorder/providers/transcription_init_provider.dart';

/// Local AI setup step - offers download of Parakeet + EmbeddingGemma
///
/// Shows combined status and offers options:
/// - Download Now
/// - Download on WiFi (queues for later)
/// - Skip (download in settings later)
class LocalAiStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const LocalAiStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<LocalAiStep> createState() => _LocalAiStepState();
}

class _LocalAiStepState extends ConsumerState<LocalAiStep> {
  bool _isChecking = true;
  bool _isDownloading = false;
  bool _parakeetReady = false;
  bool _embeddingReady = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  String? _error;

  // Size estimates
  static const int _parakeetSizeMB = 500; // ~500MB for Parakeet
  static const int _embeddingSizeMB = 300; // ~300MB for EmbeddingGemma

  @override
  void initState() {
    super.initState();
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    setState(() => _isChecking = true);

    try {
      // Check Parakeet status
      final transcriptionState = ref.read(transcriptionInitProvider);
      _parakeetReady = transcriptionState.isReady;

      // If not ready, trigger a status check
      if (!_parakeetReady) {
        await ref.read(transcriptionInitProvider.notifier).checkStatus();
        final newState = ref.read(transcriptionInitProvider);
        _parakeetReady = newState.isReady;
      }

      // Check EmbeddingGemma status
      final embeddingManager = ref.read(embeddingModelManagerProvider);
      _embeddingReady = await embeddingManager.isReady();
    } catch (e) {
      debugPrint('[LocalAiStep] Error checking status: $e');
    }

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  bool get _allReady => _parakeetReady && _embeddingReady;

  int get _downloadSizeRequired {
    int size = 0;
    if (!_parakeetReady) size += _parakeetSizeMB;
    if (!_embeddingReady) size += _embeddingSizeMB;
    return size;
  }

  Future<void> _downloadModels() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Starting downloads...';
      _error = null;
    });

    try {
      // Download Parakeet first (larger, more important)
      if (!_parakeetReady) {
        setState(() => _downloadStatus = 'Downloading voice transcription...');

        final success = await ref
            .read(transcriptionInitProvider.notifier)
            .downloadAndInitialize();

        if (success) {
          setState(() {
            _parakeetReady = true;
            _downloadProgress = 0.6; // 60% done
          });
        } else {
          final state = ref.read(transcriptionInitProvider);
          throw Exception(state.errorMessage ?? 'Parakeet download failed');
        }
      }

      // Download EmbeddingGemma
      if (!_embeddingReady) {
        setState(() => _downloadStatus = 'Downloading semantic search...');

        final embeddingManager = ref.read(embeddingModelManagerProvider);
        await for (final progress in embeddingManager.downloadModel()) {
          if (mounted) {
            setState(() {
              _downloadProgress = 0.6 + (progress * 0.4); // 60-100%
            });
          }
        }

        setState(() {
          _embeddingReady = true;
          _downloadProgress = 1.0;
        });
      }

      setState(() {
        _isDownloading = false;
        _downloadStatus = 'Ready!';
      });
    } catch (e) {
      debugPrint('[LocalAiStep] Download error: $e');
      setState(() {
        _isDownloading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Watch transcription state for live updates during download
    final transcriptionState = ref.watch(transcriptionInitProvider);
    if (transcriptionState.isInProgress && _isDownloading) {
      // Update progress from Parakeet download
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && transcriptionState.progress >= 0) {
          setState(() {
            _downloadProgress = transcriptionState.progress * 0.6;
            _downloadStatus = transcriptionState.statusMessage;
          });
        }
      });
    }

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
          onPressed: widget.onBack,
        ),
        title: Text(
          'Local AI',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: widget.onSkip,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isChecking
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _allReady
                                  ? 'AI Features Ready!'
                                  : 'Enable AI Features',
                              style: TextStyle(
                                fontSize: TypographyTokens.headlineLarge,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? BrandColors.nightText
                                    : BrandColors.charcoal,
                              ),
                            ),
                            SizedBox(height: Spacing.lg),
                            Text(
                              _allReady
                                  ? 'Voice transcription and semantic search are ready to use.'
                                  : 'Download local AI models for offline voice transcription and semantic search. '
                                      'Your data stays on your device.',
                              style: TextStyle(
                                fontSize: TypographyTokens.bodyLarge,
                                color: isDark
                                    ? BrandColors.nightTextSecondary
                                    : BrandColors.driftwood,
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: Spacing.xxl),

                            // Model cards
                            _buildModelCard(
                              isDark: isDark,
                              title: 'Voice Transcription',
                              subtitle: 'Parakeet v3 - Speech to text',
                              icon: Icons.record_voice_over,
                              isReady: _parakeetReady,
                              sizeMB: _parakeetSizeMB,
                            ),
                            SizedBox(height: Spacing.md),
                            _buildModelCard(
                              isDark: isDark,
                              title: 'Semantic Search',
                              subtitle: 'EmbeddingGemma - Find by meaning',
                              icon: Icons.search,
                              isReady: _embeddingReady,
                              sizeMB: _embeddingSizeMB,
                            ),

                            // Download progress
                            if (_isDownloading) ...[
                              SizedBox(height: Spacing.xxl),
                              _buildDownloadProgress(isDark),
                            ],

                            // Error message
                            if (_error != null) ...[
                              SizedBox(height: Spacing.xl),
                              _buildErrorMessage(isDark),
                            ],

                            // Info about what happens if skipped
                            if (!_allReady && !_isDownloading) ...[
                              SizedBox(height: Spacing.xxl),
                              _buildInfoMessage(isDark),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: Spacing.lg),
                    _buildBottomButtons(isDark),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildModelCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isReady,
    required int sizeMB,
  }) {
    final color = isReady ? BrandColors.success : BrandColors.turquoise;

    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: TypographyTokens.bodyLarge,
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
          if (isReady)
            Icon(Icons.check_circle, color: BrandColors.success, size: 28)
          else
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                '~$sizeMB MB',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadProgress(bool isDark) {
    final isIndeterminate = _downloadProgress <= 0;

    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.turquoise.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: BrandColors.turquoise, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
                ),
              ),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  _downloadStatus,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: BrandColors.turquoise,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.md),
          if (isIndeterminate)
            const LinearProgressIndicator(
              backgroundColor: BrandColors.stone,
              valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
            )
          else
            LinearProgressIndicator(
              value: _downloadProgress,
              backgroundColor: BrandColors.stone,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
            ),
          if (!isIndeterminate) ...[
            SizedBox(height: Spacing.sm),
            Text(
              '${(_downloadProgress * 100).toStringAsFixed(0)}% complete',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: BrandColors.turquoise,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorMessage(bool isDark) {
    return Container(
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
    );
  }

  Widget _buildInfoMessage(bool isDark) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            size: 20,
          ),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'You can skip this and download later from Settings. '
              'Recording and note-taking work without AI features.',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(bool isDark) {
    if (_allReady) {
      // All models ready - just continue
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: widget.onNext,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
            padding: EdgeInsets.symmetric(vertical: Spacing.md),
          ),
          child: const Text('Continue'),
        ),
      );
    }

    if (_isDownloading) {
      // Downloading - show cancel option
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () {
            // TODO: Implement cancel - for now just allow skip
            widget.onSkip();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: BrandColors.driftwood,
            padding: EdgeInsets.symmetric(vertical: Spacing.md),
          ),
          child: const Text('Continue in Background'),
        ),
      );
    }

    // Not downloaded - show download options
    return Column(
      children: [
        // Download button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _downloadModels,
            icon: const Icon(Icons.download),
            label: Text(
              _error != null
                  ? 'Retry Download'
                  : 'Download Now (~$_downloadSizeRequired MB)',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.turquoise,
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
          ),
        ),
        SizedBox(height: Spacing.md),
        // Skip button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.onSkip,
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
              side: BorderSide(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.3)
                    : BrandColors.driftwood.withValues(alpha: 0.3),
              ),
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
            child: const Text('Skip for Now'),
          ),
        ),
      ],
    );
  }
}
