import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/quick_prompt.dart';

/// A chip button for a quick prompt
class PromptChip extends StatelessWidget {
  final QuickPrompt prompt;
  final VoidCallback onTap;

  const PromptChip({
    super.key,
    required this.prompt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      avatar: Icon(
        _iconFromName(prompt.icon),
        size: 16,
        color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
      ),
      label: Text(prompt.name),
      onPressed: onTap,
      backgroundColor: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        fontSize: TypographyTokens.labelMedium,
        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
        ),
      ),
    );
  }

  /// Convert icon name string to IconData
  static IconData _iconFromName(String name) {
    switch (name) {
      case 'rocket_launch':
        return Icons.rocket_launch_outlined;
      case 'refresh':
        return Icons.refresh;
      case 'wb_sunny':
        return Icons.wb_sunny_outlined;
      case 'hub':
        return Icons.hub_outlined;
      case 'person':
        return Icons.person_outline;
      case 'folder_open':
        return Icons.folder_open_outlined;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'auto_fix_high':
        return Icons.auto_fix_high_outlined;
      case 'chat':
        return Icons.chat_bubble_outline;
      case 'search':
        return Icons.search;
      case 'edit':
        return Icons.edit_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }
}

/// Convert icon name string to IconData (exported for use elsewhere)
IconData iconFromName(String name) {
  return PromptChip._iconFromName(name);
}
