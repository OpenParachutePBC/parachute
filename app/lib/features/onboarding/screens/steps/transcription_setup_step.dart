import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/services/parakeet_service.dart';

/// Platform-adaptive transcription setup step with brand styling
class TranscriptionSetupStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const TranscriptionSetupStep({
    super.key,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  ConsumerState<TranscriptionSetupStep> createState() =>
      _TranscriptionSetupStepState();
}

class _TranscriptionSetupStepState
    extends ConsumerState<TranscriptionSetupStep> {
  bool _isInitializingParakeet = false;
  bool _parakeetInitialized = false;
  String? _parakeetError;

  final bool _isApplePlatform = Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _checkParakeetStatus();
  }

  Future<void> _checkParakeetStatus() async {
    if (_isApplePlatform) {
      final parakeetService = ParakeetService();
      // Check if models are downloaded (not just loaded in memory)
      final isDownloaded = await parakeetService.areModelsDownloaded();
      if (mounted) {
        setState(() {
          _parakeetInitialized = isDownloaded;
        });
      }
    } else {
      // Android uses Sherpa-ONNX
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );
      final isReady = await transcriptionService.isReady();
      if (mounted) {
        setState(() {
          _parakeetInitialized = isReady;
        });
      }
    }
  }

  Future<void> _initializeParakeet() async {
    setState(() {
      _isInitializingParakeet = true;
      _parakeetError = null;
    });

    try {
      if (_isApplePlatform) {
        final parakeetService = ParakeetService();
        await parakeetService.initialize(version: 'v3');
      } else {
        final transcriptionService = ref.read(
          transcriptionServiceAdapterProvider,
        );
        await transcriptionService.initialize();
      }

      if (mounted) {
        setState(() {
          _parakeetInitialized = true;
          _isInitializingParakeet = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _parakeetError = e.toString();
          _isInitializingParakeet = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

                      _buildParakeetInfo(isDark),
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

  Widget _buildParakeetInfo(bool isDark) {
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
                'Parakeet v3',
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
          if (_parakeetInitialized) ...[
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
          if (_parakeetError != null) ...[
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
                      _parakeetError!,
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
          if (!_parakeetInitialized && _parakeetError == null) ...[
            SizedBox(height: Spacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isInitializingParakeet
                    ? null
                    : _initializeParakeet,
                icon: _isInitializingParakeet
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark
                                ? BrandColors.nightTurquoise
                                : BrandColors.turquoise,
                          ),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  _isInitializingParakeet ? 'Downloading...' : 'Download Now',
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

  Widget _buildBottomButtons(bool isDark) {
    return Row(
      children: [
        Expanded(
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
            child: const Text('Skip'),
          ),
        ),
        SizedBox(width: Spacing.md),
        Expanded(
          child: FilledButton(
            onPressed: widget.onNext,
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
