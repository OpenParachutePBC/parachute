import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Expandable settings section with header and collapsible content
///
/// Provides progressive disclosure - users see category overview first,
/// then tap to expand and see details.
class ExpandableSettingsSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;
  final Color? accentColor;
  final Widget? trailing;

  const ExpandableSettingsSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
    this.accentColor,
    this.trailing,
  });

  @override
  State<ExpandableSettingsSection> createState() =>
      _ExpandableSettingsSectionState();
}

class _ExpandableSettingsSectionState extends State<ExpandableSettingsSection>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconRotation;
  late Animation<double> _expandAnimation;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: Motion.standard,
      vsync: this,
    );
    _iconRotation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Motion.settling),
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Motion.settling,
    );

    if (_isExpanded) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = widget.accentColor ??
        (isDark ? BrandColors.nightForest : BrandColors.forest);

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated
            : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: _isExpanded
              ? accentColor.withValues(alpha: 0.3)
              : (isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                    : BrandColors.stone),
          width: _isExpanded ? 2 : 1,
        ),
        boxShadow: isDark ? null : Elevation.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (always visible)
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  // Icon
                  Container(
                    padding: EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(
                      widget.icon,
                      color: accentColor,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: Spacing.lg),

                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: TypographyTokens.titleMedium,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          SizedBox(height: Spacing.xs),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              fontSize: TypographyTokens.bodySmall,
                              color: isDark
                                  ? BrandColors.nightTextSecondary
                                  : BrandColors.driftwood,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Trailing widget or expand icon
                  if (widget.trailing != null) ...[
                    widget.trailing!,
                    SizedBox(width: Spacing.sm),
                  ],
                  RotationTransition(
                    turns: _iconRotation,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                  height: 1,
                  color: isDark
                      ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                      : BrandColors.stone,
                ),
                Padding(
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple settings row for use inside expandable sections
class SettingsRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: Spacing.md,
          horizontal: Spacing.sm,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              SizedBox(width: Spacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      color: isDark
                          ? BrandColors.nightText
                          : BrandColors.charcoal,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: Spacing.xs),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null)
              Icon(
                Icons.chevron_right,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings toggle row with switch
class SettingsToggleRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const SettingsToggleRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: Spacing.sm,
          horizontal: Spacing.sm,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 20,
                color: value
                    ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                    : (isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood),
              ),
              SizedBox(width: Spacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      color: isDark
                          ? BrandColors.nightText
                          : BrandColors.charcoal,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: Spacing.xs),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeTrackColor:
                  isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
          ],
        ),
      ),
    );
  }
}
