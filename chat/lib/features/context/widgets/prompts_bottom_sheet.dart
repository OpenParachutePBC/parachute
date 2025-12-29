import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/quick_prompt.dart';
import '../providers/context_providers.dart';
import 'prompt_chip.dart';

/// Bottom sheet showing available quick prompts
class PromptsBottomSheet extends ConsumerWidget {
  final void Function(String prompt) onPromptSelected;

  const PromptsBottomSheet({
    super.key,
    required this.onPromptSelected,
  });

  /// Show the prompts bottom sheet
  static Future<void> show(
    BuildContext context, {
    required void Function(String prompt) onPromptSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PromptsBottomSheet(onPromptSelected: onPromptSelected),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final promptsAsync = ref.watch(promptsProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.3)
                    : BrandColors.stone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_outlined,
                    size: 20,
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: TypographyTokens.titleMedium,
                      fontWeight: FontWeight.w600,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                  ),
                ],
              ),
            ),

            // Prompts list
            promptsAsync.when(
              data: (prompts) => _buildPromptsList(context, prompts, isDark),
              loading: () => Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  'Failed to load prompts',
                  style: TextStyle(color: BrandColors.error),
                ),
              ),
            ),

            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptsList(BuildContext context, List<QuickPrompt> prompts, bool isDark) {
    if (prompts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Text(
          'No prompts configured',
          style: TextStyle(
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      itemCount: prompts.length,
      separatorBuilder: (context, index) => const SizedBox(height: Spacing.xs),
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        return _PromptListItem(
          prompt: prompt,
          isDark: isDark,
          onTap: () {
            Navigator.of(context).pop();
            onPromptSelected(prompt.prompt);
          },
        );
      },
    );
  }
}

class _PromptListItem extends StatelessWidget {
  final QuickPrompt prompt;
  final bool isDark;
  final VoidCallback onTap;

  const _PromptListItem({
    required this.prompt,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.card,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurface
                : BrandColors.stone.withValues(alpha: 0.3),
            borderRadius: Radii.card,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightTurquoise.withValues(alpha: 0.2)
                      : BrandColors.turquoiseMist,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconFromName(prompt.icon),
                  size: 18,
                  color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                    if (prompt.description.isNotEmpty) ...[
                      const SizedBox(height: Spacing.xxs),
                      Text(
                        prompt.description,
                        style: TextStyle(
                          fontSize: TypographyTokens.bodySmall,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
