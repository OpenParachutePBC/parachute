import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/file_system_provider.dart';
import '../models/chat_message.dart';
import 'inline_audio_player.dart';

/// A chat message bubble with support for text, tool calls, and inline assets
class MessageBubble extends ConsumerWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get vault path for resolving relative asset paths
    final vaultPath = ref.watch(vaultPathProvider).valueOrNull;

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
            children: _buildContent(context, isUser, isDark, vaultPath),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, bool isUser, bool isDark, String? vaultPath) {
    final widgets = <Widget>[];

    for (final content in message.content) {
      if (content.type == ContentType.text && content.text != null) {
        widgets.add(_buildTextContent(context, content.text!, isUser, isDark, vaultPath));
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
      BuildContext context, String text, bool isUser, bool isDark, String? vaultPath) {
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
              // ignore: deprecated_member_use
              imageBuilder: (uri, title, alt) =>
                  _buildImage(uri, title, alt, vaultPath, isDark),
              onTapLink: (linkText, href, title) =>
                  _handleLinkTap(context, linkText, href, title, vaultPath),
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

  /// Resolve a relative asset path to an absolute path
  String? _resolveAssetPath(String path, String? vaultPath) {
    if (vaultPath == null) return null;

    // Already absolute
    if (path.startsWith('/')) return path;

    // Remove leading ./ if present
    final cleanPath = path.startsWith('./') ? path.substring(2) : path;

    return '$vaultPath/$cleanPath';
  }

  /// Build an inline image widget
  Widget _buildImage(Uri uri, String? title, String? alt, String? vaultPath, bool isDark) {
    final path = _resolveAssetPath(uri.toString(), vaultPath);

    if (path == null) {
      return _buildImagePlaceholder(alt ?? 'Image', isDark);
    }

    final file = File(path);

    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return _buildImagePlaceholder(alt ?? uri.toString(), isDark);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: Image.file(
              file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) =>
                  _buildImagePlaceholder('Failed to load image', isDark),
            ),
          ),
        );
      },
    );
  }

  Widget _buildImagePlaceholder(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.cream,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 16,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          const SizedBox(width: Spacing.xs),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle link taps - special handling for audio files
  void _handleLinkTap(BuildContext context, String text, String? href, String? title, String? vaultPath) {
    if (href == null) return;

    // Check if it's an audio file
    final isAudio = href.endsWith('.opus') ||
        href.endsWith('.wav') ||
        href.endsWith('.mp3') ||
        href.endsWith('.m4a');

    if (isAudio) {
      final path = _resolveAssetPath(href, vaultPath);
      if (path != null) {
        _showAudioPlayer(context, path, text);
      }
    }
    // For other links, could open in browser or handle differently
  }

  /// Show a bottom sheet with the audio player
  void _showAudioPlayer(BuildContext context, String audioPath, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: Spacing.lg),
            InlineAudioPlayer(
              audioPath: audioPath,
              title: title,
            ),
            const SizedBox(height: Spacing.lg),
          ],
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
