import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/recorder/providers/transcription_init_provider.dart';

/// Platform-adaptive transcription setup step with brand styling
///
/// Uses transcriptionInitProvider for consistent state across the app.
class TranscriptionSetupStep extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const TranscriptionSetupStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  bool get _isApplePlatform => Platform.isIOS || Platform.isMacOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initState = ref.watch(transcriptionInitProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
          onPressed: onBack,
        ),
        title: Text(
          'Transcription Setup',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
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
                        'Voice Transcription',
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
                        'Parachute uses Parakeet v3 for fast, offline transcription. '
                        'Your voice stays on your device.',
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyLarge,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                          height: 1.5,
                        ),
                      ),
                      SizedBox(height: Spacing.xxl),

                      _buildParakeetInfo(context, ref, isDark, initState),
                    ],
                  ),
                ),
              ),
              SizedBox(height: Spacing.lg),
              _buildBottomButtons(context, isDark, initState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParakeetInfo(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    TranscriptionInitState initState,
  ) {
    return Container(
      padding: EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.stone,
          width: 1,
        ),
        boxShadow: isDark ? null : Elevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightTurquoise.withValues(alpha: 0.2)
                      : BrandColors.turquoiseMist,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: isDark
                      ? BrandColors.nightTurquoise
                      : BrandColors.turquoiseDeep,
                  size: 28,
                ),
              ),
              SizedBox(width: Spacing.lg),
              Text(
                initState.engineName ?? 'Parakeet v3',
                style: TextStyle(
                  fontSize: TypographyTokens.headlineSmall,
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.xl),
          _buildFeatureItem(
            icon: Icons.speed,
            title: _isApplePlatform ? '~190x Real-time' : '~5x Real-time',
            subtitle: _isApplePlatform
                ? 'Uses Apple Neural Engine'
                : 'ONNX Runtime optimized',
            isDark: isDark,
          ),
          SizedBox(height: Spacing.md),
          _buildFeatureItem(
            icon: Icons.language,
            title: '25 Languages',
            subtitle: 'Auto-detects language',
            isDark: isDark,
          ),
          SizedBox(height: Spacing.md),
          _buildFeatureItem(
            icon: Icons.cloud_off,
            title: '100% Offline',
            subtitle: 'No internet required',
            isDark: isDark,
          ),
          SizedBox(height: Spacing.md),
          _buildFeatureItem(
            icon: Icons.download,
            title: _isApplePlatform ? '~500 MB download' : '~640 MB download',
            subtitle: 'Downloads automatically on first use',
            isDark: isDark,
          ),

          // Show ready state
          if (initState.isReady) ...[
            SizedBox(height: Spacing.xl),
            Container(
              padding: EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: BrandColors.successLight,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: BrandColors.success, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: BrandColors.success),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      'Ready to use!',
                      style: TextStyle(
                        color: BrandColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Show error state
          if (initState.hasFailed && initState.errorMessage != null) ...[
            SizedBox(height: Spacing.xl),
            Container(
              padding: EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: BrandColors.errorLight,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: BrandColors.error, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: BrandColors.error),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      initState.errorMessage!,
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

          // Show progress when downloading/initializing
          if (initState.isInProgress) ...[
            SizedBox(height: Spacing.xl),
            _buildProgressIndicator(isDark, initState),
          ],

          // Show download button when not ready and not in progress
          if (!initState.isReady && !initState.isInProgress) ...[
            SizedBox(height: Spacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(transcriptionInitProvider.notifier).downloadAndInitialize();
                },
                icon: Icon(initState.hasFailed ? Icons.refresh : Icons.download),
                label: Text(
                  initState.hasFailed ? 'Retry Download' : 'Download Now',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? BrandColors.nightTurquoise
                      : BrandColors.turquoise,
                  side: BorderSide(
                    color: isDark
                        ? BrandColors.nightTurquoise
                        : BrandColors.turquoise,
                  ),
                  padding: EdgeInsets.symmetric(vertical: Spacing.md),
                ),
              ),
            ),
            SizedBox(height: Spacing.md),
            Center(
              child: Text(
                'Or skip and download later',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(bool isDark, TranscriptionInitState initState) {
    final isIndeterminate = initState.progress < 0;

    return Column(
      children: [
        if (isIndeterminate)
          LinearProgressIndicator(
            backgroundColor: BrandColors.stone,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          )
        else
          LinearProgressIndicator(
            value: initState.progress,
            backgroundColor: BrandColors.stone,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
        SizedBox(height: Spacing.sm),
        Text(
          initState.statusMessage.isNotEmpty
              ? initState.statusMessage
              : initState.userFriendlyStatus,
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!isIndeterminate) ...[
          SizedBox(height: Spacing.xs),
          Text(
            '${(initState.progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.7)
              : BrandColors.forest.withValues(alpha: 0.7),
          size: 20,
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
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
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
      ],
    );
  }

  Widget _buildBottomButtons(
    BuildContext context,
    bool isDark,
    TranscriptionInitState initState,
  ) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onSkip,
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
            child: const Text('Skip'),
          ),
        ),
        SizedBox(width: Spacing.md),
        Expanded(
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor:
                  isDark ? BrandColors.nightForest : BrandColors.forest,
              foregroundColor: BrandColors.softWhite,
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
            ),
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }
}
