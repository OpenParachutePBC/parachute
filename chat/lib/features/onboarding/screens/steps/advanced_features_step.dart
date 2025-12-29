import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Advanced features step with brand styling
///
/// Shows optional features like AI Chat and Omi device support
class AdvancedFeaturesStep extends ConsumerWidget {
  final VoidCallback onComplete;
  final VoidCallback onBack;

  const AdvancedFeaturesStep({
    super.key,
    required this.onComplete,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color:
                          isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                    onPressed: onBack,
                  ),
                ],
              ),

              SizedBox(height: Spacing.sm),

              // Title
              Text(
                'Optional Features',
                style: TextStyle(
                  fontSize: TypographyTokens.headlineLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),

              SizedBox(height: Spacing.sm),

              Text(
                'These advanced features are disabled by default. '
                'You can enable them anytime in Settings.',
                style: TextStyle(
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                  height: 1.5,
                ),
              ),

              SizedBox(height: Spacing.xxl),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // AI Chat feature card
                      _buildFeatureCard(
                        context,
                        icon: Icons.chat_bubble_outline,
                        iconColor: BrandColors.turquoise,
                        title: 'AI Chat with Claude',
                        description:
                            'Have conversations with AI in dedicated spheres. '
                            'Requires running the Parachute backend server.',
                        isDark: isDark,
                      ),

                      SizedBox(height: Spacing.lg),

                      // Omi device feature card
                      _buildFeatureCard(
                        context,
                        icon: Icons.bluetooth,
                        iconColor: BrandColors.forest,
                        title: 'Omi Wearable Device',
                        description:
                            'Connect your Omi device to record with a button tap. '
                            'Includes firmware updates over-the-air.',
                        isDark: isDark,
                      ),

                      SizedBox(height: Spacing.xxl),

                      // What you get out of the box
                      Container(
                        padding: EdgeInsets.all(Spacing.lg),
                        decoration: BoxDecoration(
                          color: BrandColors.successLight,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(
                            color: BrandColors.success.withValues(alpha: 0.5),
                            width: 1,
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
                                  size: 22,
                                ),
                                SizedBox(width: Spacing.sm),
                                Text(
                                  'What you get right now:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: BrandColors.forestDeep,
                                    fontSize: TypographyTokens.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: Spacing.lg),
                            _buildCheckItem(
                              'Voice recording with transcription',
                              isDark,
                            ),
                            _buildCheckItem(
                              'AI-powered title generation',
                              isDark,
                            ),
                            _buildCheckItem(
                              'Local file storage in your Parachute folder',
                              isDark,
                            ),
                            _buildCheckItem(
                              'Complete privacy - everything stays on your device',
                              isDark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: Spacing.xl),

              // Finish button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onComplete,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isDark ? BrandColors.nightForest : BrandColors.forest,
                    foregroundColor: BrandColors.softWhite,
                    padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rocket_launch, size: 20),
                      SizedBox(width: Spacing.sm),
                      Text(
                        'Start Recording',
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyLarge,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: Spacing.md),

              // Settings reminder
              Center(
                child: Text(
                  'You can change any of these settings later',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isDark,
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
          width: 1,
        ),
        boxShadow: isDark ? null : Elevation.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          SizedBox(width: Spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color:
                            isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                    SizedBox(width: Spacing.sm),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? BrandColors.warning.withValues(alpha: 0.2)
                            : BrandColors.warningLight,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Text(
                        'OPTIONAL',
                        style: TextStyle(
                          fontSize: TypographyTokens.labelSmall - 1,
                          fontWeight: FontWeight.bold,
                          color: BrandColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: Spacing.sm),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check, color: BrandColors.success, size: 18),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.forestDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
