import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:app/core/theme/design_tokens.dart';
import '../models/chat_message.dart';

/// A chat message bubble with support for text and tool calls
class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
        bottom: Spacing.sm,
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                : (isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(Radii.lg),
              topRight: const Radius.circular(Radii.lg),
              bottomLeft: Radius.circular(isUser ? Radii.lg : Radii.sm),
              bottomRight: Radius.circular(isUser ? Radii.sm : Radii.lg),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildContent(context, isUser, isDark),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, bool isUser, bool isDark) {
    final widgets = <Widget>[];

    for (final content in message.content) {
      if (content.type == ContentType.text && content.text != null) {
        widgets.add(_buildTextContent(context, content.text!, isUser, isDark));
      } else if (content.type == ContentType.toolUse && content.toolCall != null) {
        widgets.add(_buildToolCallContent(context, content.toolCall!, isDark));
      }
    }

    // Show streaming indicator if message is streaming and has no content yet
    if (message.isStreaming && widgets.isEmpty) {
      widgets.add(_buildStreamingIndicator(context, isDark));
    }

    return widgets;
  }

  Widget _buildTextContent(
      BuildContext context, String text, bool isUser, bool isDark) {
    final textColor = isUser
        ? Colors.white
        : (isDark ? BrandColors.nightText : BrandColors.charcoal);

    return Padding(
      padding: Spacing.cardPadding,
      child: isUser
          ? Text(
              text,
              style: TextStyle(
                color: textColor,
                fontSize: TypographyTokens.bodyMedium,
                height: TypographyTokens.lineHeightNormal,
              ),
            )
          : MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: textColor,
                  fontSize: TypographyTokens.bodyMedium,
                  height: TypographyTokens.lineHeightNormal,
                ),
                code: TextStyle(
                  color: textColor,
                  backgroundColor: isDark
                      ? BrandColors.nightSurface
                      : BrandColors.cream,
                  fontFamily: 'monospace',
                  fontSize: TypographyTokens.bodySmall,
                ),
                codeblockDecoration: BoxDecoration(
                  color:
                      isDark ? BrandColors.nightSurface : BrandColors.cream,
                  borderRadius: Radii.badge,
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isDark
                          ? BrandColors.nightForest
                          : BrandColors.forest,
                      width: 3,
                    ),
                  ),
                ),
                h1: TextStyle(
                  color: textColor,
                  fontSize: TypographyTokens.headlineLarge,
                  fontWeight: FontWeight.bold,
                ),
                h2: TextStyle(
                  color: textColor,
                  fontSize: TypographyTokens.headlineMedium,
                  fontWeight: FontWeight.bold,
                ),
                h3: TextStyle(
                  color: textColor,
                  fontSize: TypographyTokens.headlineSmall,
                  fontWeight: FontWeight.bold,
                ),
                listBullet: TextStyle(color: textColor),
              ),
            ),
    );
  }

  Widget _buildToolCallContent(
      BuildContext context, ToolCall toolCall, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.cream,
        borderRadius: Radii.badge,
        border: Border.all(
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getToolIcon(toolCall.name),
            size: 14,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
          ),
          const SizedBox(width: Spacing.xs),
          Flexible(
            child: Text(
              '${toolCall.name}${toolCall.summary.isNotEmpty ? ': ${toolCall.summary}' : ''}',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                fontSize: TypographyTokens.labelSmall,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingIndicator(BuildContext context, bool isDark) {
    return Padding(
      padding: Spacing.cardPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise),
          const SizedBox(width: 4),
          _PulsingDot(
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            delay: const Duration(milliseconds: 150),
          ),
          const SizedBox(width: 4),
          _PulsingDot(
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            delay: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String toolName) {
    final name = toolName.toLowerCase();
    if (name.contains('read')) return Icons.description_outlined;
    if (name.contains('bash')) return Icons.terminal;
    if (name.contains('glob') || name.contains('grep')) return Icons.search;
    if (name.contains('write') || name.contains('edit')) return Icons.edit_outlined;
    if (name.contains('task')) return Icons.task_alt;
    return Icons.build_outlined;
  }
}

/// Animated pulsing dot for streaming indicator
class _PulsingDot extends StatefulWidget {
  final Color color;
  final Duration delay;

  const _PulsingDot({
    required this.color,
    this.delay = Duration.zero,
  });

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
