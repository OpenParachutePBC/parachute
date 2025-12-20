import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import '../providers/context_providers.dart';

/// Dialog shown when AGENTS.md or prompts.yaml don't exist
///
/// Offers to create default files to help the AI understand the user better.
class VaultSetupDialog extends ConsumerStatefulWidget {
  const VaultSetupDialog({super.key});

  /// Show the dialog and return true if files were created
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const VaultSetupDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<VaultSetupDialog> createState() => _VaultSetupDialogState();
}

class _VaultSetupDialogState extends ConsumerState<VaultSetupDialog> {
  bool _isCreating = false;

  Future<void> _createFiles() async {
    setState(() => _isCreating = true);

    try {
      await ref.read(initializeVaultContextProvider)();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create files: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      title: Text(
        'Set up your vault',
        style: TextStyle(
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create your vault profile to help the AI understand you better.',
            style: TextStyle(
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              height: TypographyTokens.lineHeightRelaxed,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          _SetupItem(
            icon: Icons.description_outlined,
            title: 'AGENTS.md',
            subtitle: 'Your profile and vault context',
            isDark: isDark,
          ),
          const SizedBox(height: Spacing.sm),
          _SetupItem(
            icon: Icons.bolt_outlined,
            title: 'prompts.yaml',
            subtitle: 'Quick actions for common tasks',
            isDark: isDark,
          ),
          const SizedBox(height: Spacing.lg),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightForest.withValues(alpha: 0.1)
                  : BrandColors.forestMist.withValues(alpha: 0.5),
              borderRadius: Radii.card,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  size: 20,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    'After setup, use "Get to know me" to personalize your profile.',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightForest : BrandColors.forestDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Skip for now',
            style: TextStyle(
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createFiles,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          child: _isCreating
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Create files'),
        ),
      ],
    );
  }
}

class _SetupItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  const _SetupItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurface
                : BrandColors.stone.withValues(alpha: 0.5),
            borderRadius: Radii.badge,
          ),
          child: Icon(
            icon,
            size: 20,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
          ),
        ),
        const SizedBox(width: Spacing.md),
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
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
