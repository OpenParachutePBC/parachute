import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/embedding_provider.dart';
import 'package:app/features/recorder/providers/transcription_init_provider.dart';

/// Final onboarding step - shows what's ready and lets user get started
class ReadyStep extends ConsumerWidget {
  final VoidCallback onComplete;
  final VoidCallback onBack;

  const ReadyStep({
    super.key,
    required this.onComplete,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check status of AI models
    final transcriptionState = ref.watch(transcriptionInitProvider);
    final embeddingStatus = ref.watch(embeddingModelStatusProvider);

    final parakeetReady = transcriptionState.isReady;
    final embeddingReady = embeddingStatus.isReady;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Success icon
                        Container(
                          padding: EdgeInsets.all(Spacing.xxl),
                          decoration: BoxDecoration(
                            color: BrandColors.forest.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle_outline,
                            size: 80,
                            color: isDark
                                ? BrandColors.nightForest
                                : BrandColors.forest,
                          ),
                        ),
                        SizedBox(height: Spacing.xxl),

                        Text(
                          "You're All Set!",
                          style: TextStyle(
                            fontSize: TypographyTokens.displaySmall,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: Spacing.lg),

                        Text(
                          'Parachute is ready to help you think.',
                          style: TextStyle(
                            fontSize: TypographyTokens.bodyLarge,
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: Spacing.xxl),

                        // Feature checklist
                        _buildFeatureList(
                          isDark: isDark,
                          parakeetReady: parakeetReady,
                          embeddingReady: embeddingReady,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Get Started button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? BrandColors.nightForest : BrandColors.forest,
                    padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                  ),
                  child: Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyLarge,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureList({
    required bool isDark,
    required bool parakeetReady,
    required bool embeddingReady,
  }) {
    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.stone,
        ),
      ),
      child: Column(
        children: [
          _buildFeatureItem(
            isDark: isDark,
            icon: Icons.folder_open,
            title: 'Your Vault',
            subtitle: 'Notes and recordings stored locally',
            isReady: true,
          ),
          Divider(height: Spacing.xl),
          _buildFeatureItem(
            isDark: isDark,
            icon: Icons.edit_note,
            title: 'Journal',
            subtitle: 'Quick notes and voice recordings',
            isReady: true,
          ),
          Divider(height: Spacing.xl),
          _buildFeatureItem(
            isDark: isDark,
            icon: Icons.record_voice_over,
            title: 'Voice Transcription',
            subtitle: parakeetReady
                ? 'Ready to transcribe'
                : 'Download in Settings when ready',
            isReady: parakeetReady,
            isOptional: true,
          ),
          Divider(height: Spacing.xl),
          _buildFeatureItem(
            isDark: isDark,
            icon: Icons.search,
            title: 'Semantic Search',
            subtitle: embeddingReady
                ? 'Search by meaning'
                : 'Download in Settings when ready',
            isReady: embeddingReady,
            isOptional: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isReady,
    bool isOptional = false,
  }) {
    final color = isReady
        ? BrandColors.success
        : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood);

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
              Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                  if (isOptional && !isReady) ...[
                    SizedBox(width: Spacing.xs),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.xs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? BrandColors.nightSurface
                            : BrandColors.stone.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Optional',
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall - 2,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                        ),
                      ),
                    ),
                  ],
                ],
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
        Icon(
          isReady ? Icons.check_circle : Icons.circle_outlined,
          color: color,
          size: 24,
        ),
      ],
    );
  }
}
