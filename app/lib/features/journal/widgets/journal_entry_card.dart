import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme/design_tokens.dart';
import '../models/journal_entry.dart';

/// Card widget displaying a single journal entry
///
/// Shows the entry title, content preview, and type indicator.
/// The para ID is hidden from the user.
///
/// Special handling for "preamble" and "plain_*" entries which are
/// markdown content imported from Obsidian without para:IDs.
class JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final String? audioPath;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const JournalEntryCard({
    super.key,
    required this.entry,
    this.audioPath,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  /// Check if this is imported markdown content (no para:ID)
  bool get _isImportedMarkdown =>
      entry.id == 'preamble' || entry.id.startsWith('plain_');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use different layout for imported markdown vs para:ID entries
    if (_isImportedMarkdown) {
      return _buildMarkdownCard(context, theme, isDark);
    }

    return Card(
      elevation: 0,
      color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? BrandColors.charcoal : BrandColors.stone,
          width: 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: title + type icon + menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type indicator
                  _buildTypeIcon(isDark),
                  const SizedBox(width: 12),

                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title.isNotEmpty ? entry.title : 'Untitled',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isDark ? BrandColors.softWhite : BrandColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entry.durationSeconds != null && entry.durationSeconds! > 0)
                          Text(
                            _formatDuration(entry.durationSeconds!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: BrandColors.driftwood,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Menu button
                  _buildMenuButton(),
                ],
              ),

              // Content preview
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _truncateContent(entry.content),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? BrandColors.stone : BrandColors.charcoal,
                    height: 1.5,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Linked file indicator
              if (entry.isLinked && entry.linkedFilePath != null) ...[
                const SizedBox(height: 12),
                _buildLinkedFileChip(context, isDark),
              ],

              // Audio indicator
              if (entry.hasAudio && audioPath != null) ...[
                const SizedBox(height: 12),
                _buildAudioChip(context, isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build card for imported markdown content (preamble/plain entries)
  Widget _buildMarkdownCard(BuildContext context, ThemeData theme, bool isDark) {
    // For preamble (content before any H1), show as markdown block
    // For plain_* entries (H1 without para:ID), show title + markdown content
    final hasTitle = entry.title.isNotEmpty && entry.id != 'preamble';

    return Card(
      elevation: 0,
      color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? BrandColors.charcoal.withValues(alpha: 0.5)
              : BrandColors.stone.withValues(alpha: 0.5),
          width: 0.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with markdown icon and optional title
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Markdown icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: BrandColors.driftwood.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.article_outlined,
                      size: 18,
                      color: BrandColors.driftwood,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasTitle ? entry.title : 'Note',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isDark ? BrandColors.softWhite : BrandColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Pre-Parachute',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: BrandColors.driftwood,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildMenuButton(),
                ],
              ),

              // Rendered markdown content
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: MarkdownBody(
                      data: entry.content,
                      shrinkWrap: true,
                      softLineBreak: true,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? BrandColors.stone : BrandColors.charcoal,
                          height: 1.5,
                        ),
                        h1: theme.textTheme.titleMedium?.copyWith(
                          color: isDark ? BrandColors.softWhite : BrandColors.ink,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: theme.textTheme.titleSmall?.copyWith(
                          color: isDark ? BrandColors.softWhite : BrandColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                        listBullet: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? BrandColors.stone : BrandColors.charcoal,
                        ),
                        code: TextStyle(
                          fontFamily: 'monospace',
                          backgroundColor: isDark
                              ? BrandColors.charcoal.withValues(alpha: 0.3)
                              : BrandColors.stone.withValues(alpha: 0.3),
                          color: isDark ? BrandColors.turquoise : BrandColors.turquoiseDeep,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: BrandColors.driftwood,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        color: BrandColors.driftwood,
        size: 20,
      ),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 8),
              Text('Edit'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: BrandColors.error),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: BrandColors.error)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeIcon(bool isDark) {
    IconData icon;
    Color color;

    switch (entry.type) {
      case JournalEntryType.voice:
        icon = Icons.mic;
        color = BrandColors.turquoise;
      case JournalEntryType.linked:
        icon = Icons.link;
        color = BrandColors.forest;
      case JournalEntryType.text:
        icon = Icons.edit_note;
        color = BrandColors.driftwood;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 18,
        color: color,
      ),
    );
  }

  Widget _buildLinkedFileChip(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.forestMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 14,
            color: BrandColors.forest,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              entry.linkedFilePath!.split('/').last,
              style: TextStyle(
                fontSize: 12,
                color: BrandColors.forest,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioChip(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.turquoiseMist.withValues(alpha: isDark ? 0.2 : 1.0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 14,
            color: BrandColors.turquoise,
          ),
          const SizedBox(width: 6),
          Text(
            'Play audio',
            style: TextStyle(
              fontSize: 12,
              color: BrandColors.turquoise,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateContent(String content) {
    // Remove excessive whitespace
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes > 0) {
      return '$minutes min ${secs > 0 ? '$secs sec' : ''}';
    }
    return '$secs sec';
  }
}
