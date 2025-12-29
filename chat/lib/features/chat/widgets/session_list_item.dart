import 'package:flutter/material.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/chat_session.dart';

/// List item for displaying a chat session
///
/// Shows session title, agent name, timestamp, and swipe-to-delete with confirmation.
class SessionListItem extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

  const SessionListItem({
    super.key,
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          'This will permanently delete "${session.displayTitle}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        // Show confirmation dialog first
        final confirmed = await _confirmDelete(context);
        if (!confirmed) return false;

        // Perform the deletion
        await onDelete();
        return true;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Spacing.lg),
        decoration: BoxDecoration(
          color: BrandColors.error,
          borderRadius: Radii.card,
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.card,
          child: Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated
                  : BrandColors.softWhite,
              borderRadius: Radii.card,
              border: Border.all(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                // Type icon
                _buildTypeIcon(isDark),

                const SizedBox(width: Spacing.md),

                // Title and metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.displayTitle,
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyMedium,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? BrandColors.nightText
                              : BrandColors.charcoal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Spacing.xxs),
                      Row(
                        children: [
                          // Show source for imported sessions
                          if (session.isImported) ...[
                            Text(
                              session.source.displayName,
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: isDark
                                    ? BrandColors.nightForest
                                    : BrandColors.forest,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: isDark
                                    ? BrandColors.nightTextSecondary
                                    : BrandColors.driftwood,
                              ),
                            ),
                          ] else if (session.agentName != null) ...[
                            Text(
                              session.agentName!,
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: isDark
                                    ? BrandColors.nightTurquoise
                                    : BrandColors.turquoise,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: isDark
                                    ? BrandColors.nightTextSecondary
                                    : BrandColors.driftwood,
                              ),
                            ),
                          ],
                          Text(
                            _formatTimestamp(session.updatedAt ?? session.createdAt),
                            style: TextStyle(
                              fontSize: TypographyTokens.labelSmall,
                              color: isDark
                                  ? BrandColors.nightTextSecondary
                                  : BrandColors.driftwood,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(bool isDark) {
    // Show different icons based on source
    IconData icon;
    Color color;

    switch (session.source) {
      case ChatSource.chatgpt:
        icon = Icons.auto_awesome;
        color = BrandColors.turquoise;
        break;
      case ChatSource.claude:
        icon = Icons.psychology_outlined;
        color = BrandColors.forest;
        break;
      case ChatSource.other:
        icon = Icons.download_outlined;
        color = BrandColors.driftwood;
        break;
      case ChatSource.parachute:
        icon = Icons.chat_bubble_outline;
        color = isDark ? BrandColors.nightTurquoise : BrandColors.turquoise;
        break;
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 18,
        color: color,
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${timestamp.month}/${timestamp.day}';
    }
  }
}
