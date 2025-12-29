import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Banner suggesting to reflect on the chat to update AGENTS.md
///
/// Shown after a conversation has some exchanges, prompting the user
/// to consider updating their profile based on what was discussed.
class ReflectionBanner extends StatefulWidget {
  final VoidCallback onReflect;
  final VoidCallback onDismiss;

  const ReflectionBanner({
    super.key,
    required this.onReflect,
    required this.onDismiss,
  });

  @override
  State<ReflectionBanner> createState() => _ReflectionBannerState();
}

class _ReflectionBannerState extends State<ReflectionBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Motion.standard,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Motion.settling),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Motion.settling));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
                : BrandColors.turquoiseMist,
            borderRadius: Radii.card,
            border: Border.all(
              color: isDark
                  ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
                  : BrandColors.turquoiseLight,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_fix_high_outlined,
                size: 20,
                color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onReflect,
                  child: Text(
                    'Reflect on this chat',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark
                          ? BrandColors.nightTurquoise
                          : BrandColors.turquoiseDeep,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onDismiss,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: isDark
                      ? BrandColors.nightTurquoise
                      : BrandColors.turquoiseDeep,
                ),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
