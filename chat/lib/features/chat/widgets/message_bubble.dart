import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/core/services/performance_service.dart';
import '../models/chat_message.dart';
import 'inline_audio_player.dart';
import 'collapsible_thinking_section.dart';

/// Intent for copying message text
class CopyMessageIntent extends Intent {
  const CopyMessageIntent();
}

/// A chat message bubble with support for text, tool calls, and inline assets
class MessageBubble extends ConsumerWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trace = perf.trace('MessageBubble.build', metadata: {
      'role': message.role.name,
      'contentLength': message.textContent.length,
      'isStreaming': message.isStreaming,
    });

    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get vault path for resolving relative asset paths
    final vaultPath = ref.watch(vaultPathProvider).valueOrNull;

    // Build the widget (synchronous part)
    final widget = _buildWidget(context, isUser, isDark, vaultPath);
    trace.end();
    return widget;
  }

  Widget _buildWidget(BuildContext context, bool isUser, bool isDark, String? vaultPath) {
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
          child: _MessageContentWithCopy(
            message: message,
            isUser: isUser,
            isDark: isDark,
            vaultPath: vaultPath,
            contentBuilder: () => _buildContent(context, isUser, isDark, vaultPath),
            getFullText: _getFullText,
            buildActionRow: () => _buildActionRow(context, isDark, isUser),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, bool isUser, bool isDark, String? vaultPath) {
    final widgets = <Widget>[];

    // Collect thinking items (thinking text + tool calls) in order
    final thinkingItems = <MessageContent>[];
    final textParts = <String>[];

    for (final content in message.content) {
      if (content.type == ContentType.text && content.text != null) {
        textParts.add(content.text!);
      } else if (content.type == ContentType.thinking || content.type == ContentType.toolUse) {
        // Collect thinking and tool calls together in order
        thinkingItems.add(content);
      }
    }

    // Add combined thinking section (collapsed by default)
    if (thinkingItems.isNotEmpty) {
      widgets.add(CollapsibleThinkingSection(
        items: thinkingItems,
        isDark: isDark,
      ));
    }

    // Add final text content last (the actual response)
    if (textParts.isNotEmpty) {
      final combinedText = textParts.join('\n');
      widgets.add(_buildTextContent(context, combinedText, isUser, isDark, vaultPath));
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
          ? SelectableText(
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

  /// Get all text content from the message for copying
  String _getFullText() {
    final textParts = <String>[];
    for (final content in message.content) {
      if (content.type == ContentType.text && content.text != null) {
        textParts.add(content.text!);
      }
    }
    return textParts.join('\n');
  }

  /// Build action row with copy button
  Widget _buildActionRow(BuildContext context, bool isDark, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.sm,
        right: Spacing.sm,
        bottom: Spacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CopyButton(
            text: _getFullText(),
            isDark: isDark,
            isUser: isUser,
          ),
        ],
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

    // Try to find the file, including with alternate extensions
    // (nano-banana may save .jpeg when .png was requested)
    return FutureBuilder<File?>(
      future: _findImageFile(path),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return _buildImagePlaceholder(alt ?? uri.toString(), isDark);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
          child: GestureDetector(
            onSecondaryTapUp: (details) => _showImageContextMenu(
              context, details.globalPosition, file, isDark,
            ),
            onLongPressStart: (details) => _showImageContextMenu(
              context, details.globalPosition, file, isDark,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    _buildImagePlaceholder('Failed to load image', isDark),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show context menu for image with copy/save options
  void _showImageContextMenu(
    BuildContext context,
    Offset position,
    File file,
    bool isDark,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: isDark ? BrandColors.nightText : BrandColors.charcoal),
              const SizedBox(width: Spacing.sm),
              const Text('Copy image'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save_alt, size: 18, color: isDark ? BrandColors.nightText : BrandColors.charcoal),
              const SizedBox(width: Spacing.sm),
              const Text('Save image as...'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'reveal',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: isDark ? BrandColors.nightText : BrandColors.charcoal),
              const SizedBox(width: Spacing.sm),
              const Text('Show in folder'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          _copyImageToClipboard(context, file);
          break;
        case 'save':
          _saveImageAs(context, file);
          break;
        case 'reveal':
          _revealInFinder(file);
          break;
      }
    });
  }

  /// Copy image path to clipboard
  Future<void> _copyImageToClipboard(BuildContext context, File file) async {
    try {
      // Copy file path to clipboard
      // Note: Full image clipboard support requires platform-specific implementation
      await Clipboard.setData(ClipboardData(text: file.path));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image path copied to clipboard'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to copy: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Save image to a new location
  Future<void> _saveImageAs(BuildContext context, File file) async {
    try {
      final fileName = file.path.split('/').last;
      final extension = fileName.split('.').last;

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save image as',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: [extension],
      );

      if (result != null) {
        await file.copy(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image saved to ${result.split('/').last}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Reveal file in Finder/Explorer
  Future<void> _revealInFinder(File file) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', file.path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', file.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [file.parent.path]);
      }
    } catch (e) {
      debugPrint('Failed to reveal file: $e');
    }
  }

  /// Find an image file, trying alternate extensions if needed
  Future<File?> _findImageFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return file;
    }

    // Try alternate extensions (handles .png -> .jpeg mismatch)
    final alternateExtensions = ['.jpeg', '.jpg', '.png', '.webp'];
    final basePath = path.replaceAll(RegExp(r'\.[^.]+$'), '');

    for (final ext in alternateExtensions) {
      final altFile = File('$basePath$ext');
      if (await altFile.exists()) {
        return altFile;
      }
    }

    return null;
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

/// Message content wrapper with keyboard shortcuts and context menu for copying
class _MessageContentWithCopy extends StatefulWidget {
  final ChatMessage message;
  final bool isUser;
  final bool isDark;
  final String? vaultPath;
  final List<Widget> Function() contentBuilder;
  final String Function() getFullText;
  final Widget Function() buildActionRow;

  const _MessageContentWithCopy({
    required this.message,
    required this.isUser,
    required this.isDark,
    required this.vaultPath,
    required this.contentBuilder,
    required this.getFullText,
    required this.buildActionRow,
  });

  @override
  State<_MessageContentWithCopy> createState() => _MessageContentWithCopyState();
}

class _MessageContentWithCopyState extends State<_MessageContentWithCopy> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    final text = widget.getFullText();
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message copied to clipboard'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final text = widget.getFullText();
    if (text.isEmpty) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              Icon(
                Icons.copy,
                size: 18,
                color: widget.isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              const SizedBox(width: Spacing.sm),
              const Text('Copy message'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        _copyToClipboard();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.getFullText();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Cmd+C / Ctrl+C to copy
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyC): const CopyMessageIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyC): const CopyMessageIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          CopyMessageIntent: CallbackAction<CopyMessageIntent>(
            onInvoke: (_) {
              _copyToClipboard();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
          onLongPressStart: (details) => _showContextMenu(context, details.globalPosition),
          child: Focus(
            focusNode: _focusNode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message content with selection support
                SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.contentBuilder(),
                  ),
                ),
                // Copy button row
                if (text.isNotEmpty)
                  widget.buildActionRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy button with visual feedback
class _CopyButton extends StatefulWidget {
  final String text;
  final bool isDark;
  final bool isUser;

  const _CopyButton({
    required this.text,
    required this.isDark,
    required this.isUser,
  });

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isUser
        ? Colors.white.withValues(alpha: 0.7)
        : (widget.isDark
            ? BrandColors.nightTextSecondary
            : BrandColors.driftwood);

    return GestureDetector(
      onTap: _copyToClipboard,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xs,
          vertical: Spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied
                  ? (widget.isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                  : iconColor,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: _copied
                    ? (widget.isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                    : iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
