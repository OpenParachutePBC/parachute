import 'package:flutter/material.dart';
import 'package:app/core/theme/design_tokens.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';

/// Marker showing that this conversation continues from a previous session
///
/// Displays a collapsible view of the prior conversation with a clear divider
/// indicating where the new conversation picks up.
class ResumeMarker extends StatefulWidget {
  /// The original session this continues from
  final ChatSession originalSession;

  /// Messages from the original session
  final List<ChatMessage> priorMessages;

  const ResumeMarker({
    super.key,
    required this.originalSession,
    required this.priorMessages,
  });

  @override
  State<ResumeMarker> createState() => _ResumeMarkerState();
}

class _ResumeMarkerState extends State<ResumeMarker> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Collapsible prior conversation
        if (_isExpanded) _buildPriorMessages(isDark),

        // Resume divider
        _buildResumeDivider(isDark),
      ],
    );
  }

  Widget _buildPriorMessages(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurfaceElevated.withValues(alpha: 0.5)
            : BrandColors.stone.withValues(alpha: 0.2),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(Radii.md),
          topRight: Radius.circular(Radii.md),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                _getSourceIcon(widget.originalSession.source),
                size: 16,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Prior conversation from ${widget.originalSession.source.displayName}',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),

          // Messages preview (limited)
          ...widget.priorMessages.take(10).map((msg) => _buildMessagePreview(msg, isDark)),

          if (widget.priorMessages.length > 10)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                '... and ${widget.priorMessages.length - 10} more messages',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessagePreview(ChatMessage message, bool isDark) {
    final isUser = message.role == MessageRole.user;
    final text = message.textContent;
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isUser ? Icons.person_outline : Icons.smart_toy_outlined,
            size: 14,
            color: isDark
                ? BrandColors.nightTextSecondary
                : BrandColors.driftwood,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text.length > 200 ? '${text.substring(0, 200)}...' : text,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.8)
                    : BrandColors.charcoal.withValues(alpha: 0.7),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeDivider(bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.md,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.2)
              : BrandColors.forestMist,
          borderRadius: Radii.badge,
          border: Border.all(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.3)
                : BrandColors.forest.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isExpanded ? Icons.unfold_less : Icons.unfold_more,
              size: 16,
              color: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              _isExpanded
                  ? 'Hide prior conversation'
                  : 'Continued from ${widget.originalSession.displayTitle}',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
            if (!_isExpanded) ...[
              const SizedBox(width: Spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xs + 2,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightForest.withValues(alpha: 0.3)
                      : BrandColors.forest.withValues(alpha: 0.2),
                  borderRadius: Radii.pill,
                ),
                child: Text(
                  '${widget.priorMessages.length} messages',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall - 2,
                    color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getSourceIcon(ChatSource source) {
    switch (source) {
      case ChatSource.chatgpt:
        return Icons.auto_awesome;
      case ChatSource.claude:
        return Icons.psychology_outlined;
      case ChatSource.other:
        return Icons.download_outlined;
      case ChatSource.parachute:
        return Icons.chat_bubble_outline;
    }
  }
}
