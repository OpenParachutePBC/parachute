import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Parachute brand-aware UI components
///
/// "Think naturally" - Reusable components that embody the brand.
/// Use these throughout the app for consistent brand expression.

/// Brand-styled status card for showing state with color coding
class BrandStatusCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final BrandStatusType status;
  final Widget? trailing;
  final VoidCallback? onTap;

  const BrandStatusCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.status,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getStatusColors(status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.foreground, size: 28),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: TypographyTokens.bodyLarge,
                      color: colors.foreground,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: Spacing.xs),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: BrandColors.driftwood,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }

  _StatusColors _getStatusColors(BrandStatusType status) {
    switch (status) {
      case BrandStatusType.success:
        return _StatusColors(
          background: BrandColors.successLight,
          border: BrandColors.success,
          foreground: BrandColors.success,
        );
      case BrandStatusType.warning:
        return _StatusColors(
          background: BrandColors.warningLight,
          border: BrandColors.warning,
          foreground: BrandColors.warning,
        );
      case BrandStatusType.error:
        return _StatusColors(
          background: BrandColors.errorLight,
          border: BrandColors.error,
          foreground: BrandColors.error,
        );
      case BrandStatusType.info:
        return _StatusColors(
          background: BrandColors.infoLight,
          border: BrandColors.info,
          foreground: BrandColors.info,
        );
      case BrandStatusType.neutral:
        return _StatusColors(
          background: BrandColors.stone,
          border: BrandColors.driftwood,
          foreground: BrandColors.charcoal,
        );
      case BrandStatusType.primary:
        return _StatusColors(
          background: BrandColors.forestMist,
          border: BrandColors.forest,
          foreground: BrandColors.forest,
        );
      case BrandStatusType.secondary:
        return _StatusColors(
          background: BrandColors.turquoiseMist,
          border: BrandColors.turquoise,
          foreground: BrandColors.turquoise,
        );
    }
  }
}

class _StatusColors {
  final Color background;
  final Color border;
  final Color foreground;

  _StatusColors({
    required this.background,
    required this.border,
    required this.foreground,
  });
}

enum BrandStatusType {
  success,
  warning,
  error,
  info,
  neutral,
  primary,
  secondary,
}

/// Brand-styled info banner
class BrandInfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final BrandStatusType type;

  const BrandInfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.type = BrandStatusType.info,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(type);

    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.foreground, size: 16),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: colors.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _InfoColors _getColors(BrandStatusType type) {
    switch (type) {
      case BrandStatusType.success:
        return _InfoColors(
          background: BrandColors.successLight,
          border: BrandColors.success,
          foreground: BrandColors.success,
          textColor: BrandColors.forestDeep,
        );
      case BrandStatusType.warning:
        return _InfoColors(
          background: BrandColors.warningLight,
          border: BrandColors.warning,
          foreground: BrandColors.warning,
          textColor: const Color(0xFF7A5A20),
        );
      case BrandStatusType.error:
        return _InfoColors(
          background: BrandColors.errorLight,
          border: BrandColors.error,
          foreground: BrandColors.error,
          textColor: const Color(0xFF8A3A2A),
        );
      case BrandStatusType.info:
      case BrandStatusType.secondary:
        return _InfoColors(
          background: BrandColors.turquoiseMist,
          border: BrandColors.turquoise,
          foreground: BrandColors.turquoiseDeep,
          textColor: BrandColors.turquoiseDeep,
        );
      case BrandStatusType.primary:
        return _InfoColors(
          background: BrandColors.forestMist,
          border: BrandColors.forest,
          foreground: BrandColors.forest,
          textColor: BrandColors.forestDeep,
        );
      case BrandStatusType.neutral:
        return _InfoColors(
          background: BrandColors.stone,
          border: BrandColors.driftwood,
          foreground: BrandColors.driftwood,
          textColor: BrandColors.charcoal,
        );
    }
  }
}

class _InfoColors {
  final Color background;
  final Color border;
  final Color foreground;
  final Color textColor;

  _InfoColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.textColor,
  });
}

/// Brand-styled section header
class BrandSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  const BrandSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 24, color: BrandColors.forest),
              SizedBox(width: Spacing.sm),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: TypographyTokens.headlineLarge,
                fontWeight: FontWeight.bold,
                color: BrandColors.charcoal,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          SizedBox(height: Spacing.sm),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: TypographyTokens.bodyMedium,
              color: BrandColors.driftwood,
            ),
          ),
        ],
      ],
    );
  }
}

/// Brand-styled badge
class BrandBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final BrandStatusType type;
  final bool compact;

  const BrandBadge({
    super.key,
    required this.label,
    this.icon,
    this.type = BrandStatusType.primary,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(type);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Spacing.sm : Spacing.md,
        vertical: compact ? Spacing.xs : Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: colors.foreground),
            SizedBox(width: Spacing.xs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact
                  ? TypographyTokens.labelSmall
                  : TypographyTokens.labelMedium,
              fontWeight: FontWeight.w600,
              color: colors.foreground,
            ),
          ),
        ],
      ),
    );
  }

  _BadgeColors _getColors(BrandStatusType type) {
    switch (type) {
      case BrandStatusType.success:
        return _BadgeColors(
          background: BrandColors.successLight,
          border: BrandColors.success,
          foreground: BrandColors.success,
        );
      case BrandStatusType.warning:
        return _BadgeColors(
          background: BrandColors.warningLight,
          border: BrandColors.warning,
          foreground: BrandColors.warning,
        );
      case BrandStatusType.error:
        return _BadgeColors(
          background: BrandColors.errorLight,
          border: BrandColors.error,
          foreground: BrandColors.error,
        );
      case BrandStatusType.info:
        return _BadgeColors(
          background: BrandColors.infoLight,
          border: BrandColors.info,
          foreground: BrandColors.info,
        );
      case BrandStatusType.primary:
        return _BadgeColors(
          background: BrandColors.forestMist,
          border: BrandColors.forestLight,
          foreground: BrandColors.forest,
        );
      case BrandStatusType.secondary:
        return _BadgeColors(
          background: BrandColors.turquoiseMist,
          border: BrandColors.turquoiseLight,
          foreground: BrandColors.turquoiseDeep,
        );
      case BrandStatusType.neutral:
        return _BadgeColors(
          background: BrandColors.stone,
          border: BrandColors.driftwood,
          foreground: BrandColors.charcoal,
        );
    }
  }
}

class _BadgeColors {
  final Color background;
  final Color border;
  final Color foreground;

  _BadgeColors({
    required this.background,
    required this.border,
    required this.foreground,
  });
}

/// Brand-styled empty state
class BrandEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const BrandEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.forestDeep.withValues(alpha: 0.3)
                    : BrandColors.forestMist.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.7)
                    : BrandColors.forest.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: Spacing.xxl),
            Text(
              title,
              style: TextStyle(
                fontSize: TypographyTokens.headlineSmall,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? BrandColors.nightText.withValues(alpha: 0.8)
                    : BrandColors.charcoal.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: Spacing.sm),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: TypographyTokens.bodyMedium,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: Spacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Brand-styled progress indicator (processing state)
class BrandProcessingIndicator extends StatelessWidget {
  final String? label;
  final double? progress;

  const BrandProcessingIndicator({
    super.key,
    this.label,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: BrandColors.warningLight,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: progress != null
                ? CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(BrandColors.warning),
                  )
                : CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(BrandColors.warning),
                  ),
          ),
          if (label != null) ...[
            SizedBox(width: Spacing.sm),
            Text(
              label!,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                fontWeight: FontWeight.w500,
                color: BrandColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Snackbar helpers with brand styling
class BrandSnackbar {
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.success,
      ),
    );
  }

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.error,
      ),
    );
  }

  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.warning,
      ),
    );
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.info,
      ),
    );
  }
}
