import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/chat_message.dart';

/// Inline section showing the agent's thinking process and tool calls
///
/// Thinking text is shown expanded by default.
/// Tool calls are shown as compact chips, expandable for full input details.
class CollapsibleThinkingSection extends StatefulWidget {
  /// Content items in order (thinking text and tool calls interleaved)
  final List<MessageContent> items;
  final bool isDark;

  const CollapsibleThinkingSection({
    super.key,
    required this.items,
    required this.isDark,
  });

  @override
  State<CollapsibleThinkingSection> createState() => _CollapsibleThinkingSectionState();
}

class _CollapsibleThinkingSectionState extends State<CollapsibleThinkingSection> {
  final Set<int> _expandedTools = {};

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        bottom: Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          if (item.type == ContentType.thinking) {
            return _buildThinkingBlock(item.text ?? '');
          } else if (item.type == ContentType.toolUse && item.toolCall != null) {
            return _buildToolCall(index, item.toolCall!);
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    );
  }

  /// Thinking block - shown expanded as muted text
  Widget _buildThinkingBlock(String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: widget.isDark
            ? BrandColors.nightSurface.withValues(alpha: 0.3)
            : BrandColors.cream.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: widget.isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
              : BrandColors.driftwood.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: Spacing.xs),
            child: Icon(
              Icons.psychology_outlined,
              size: 14,
              color: widget.isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.6)
                  : BrandColors.driftwood.withValues(alpha: 0.6),
            ),
          ),
          Expanded(
            child: MarkdownBody(
              data: text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: widget.isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.charcoal.withValues(alpha: 0.7),
                  fontSize: TypographyTokens.bodySmall,
                  height: TypographyTokens.lineHeightNormal,
                ),
                code: TextStyle(
                  color: widget.isDark
                      ? BrandColors.nightTurquoise
                      : BrandColors.turquoiseDeep,
                  fontSize: TypographyTokens.bodySmall - 1,
                  fontFamily: 'monospace',
                  backgroundColor: widget.isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.softWhite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tool call - compact chip, expandable for full input and result
  Widget _buildToolCall(int index, ToolCall toolCall) {
    final isExpanded = _expandedTools.contains(index);
    final hasInput = toolCall.input.isNotEmpty;
    final hasResult = toolCall.result != null;
    final hasDetails = hasInput || hasResult;

    // Chip color - error results get error styling
    final chipColor = toolCall.isError
        ? (widget.isDark ? BrandColors.error : BrandColors.error)
        : (widget.isDark ? BrandColors.nightTurquoise : BrandColors.turquoise);

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact chip header
          GestureDetector(
            onTap: hasDetails ? () => _toggleTool(index) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: chipColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    toolCall.isError ? Icons.error_outline : _getToolIcon(toolCall.name),
                    size: 12,
                    color: chipColor,
                  ),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    _formatToolName(toolCall.name),
                    style: TextStyle(
                      color: toolCall.isError
                          ? chipColor
                          : (widget.isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep),
                      fontSize: TypographyTokens.labelSmall,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (toolCall.summary.isNotEmpty && !isExpanded) ...[
                    const SizedBox(width: Spacing.xs),
                    Flexible(
                      child: Text(
                        toolCall.summary,
                        style: TextStyle(
                          color: widget.isDark
                              ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                              : BrandColors.driftwood.withValues(alpha: 0.7),
                          fontSize: TypographyTokens.labelSmall,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  // Show checkmark if result received (success)
                  if (hasResult && !toolCall.isError && !isExpanded) ...[
                    const SizedBox(width: Spacing.xs),
                    Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: widget.isDark
                          ? BrandColors.nightForest
                          : BrandColors.forest,
                    ),
                  ],
                  if (hasDetails) ...[
                    const SizedBox(width: Spacing.xs),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: chipColor.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded details (input and result)
          if (isExpanded && hasDetails)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: Spacing.xs, left: Spacing.sm),
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.softWhite,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: widget.isDark
                      ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                      : BrandColors.driftwood.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Input section
                  if (hasInput) ...[
                    Text(
                      'Input',
                      style: TextStyle(
                        color: widget.isDark
                            ? BrandColors.nightTextSecondary.withValues(alpha: 0.6)
                            : BrandColors.driftwood.withValues(alpha: 0.6),
                        fontSize: TypographyTokens.labelSmall - 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    SelectableText(
                      _formatInput(toolCall.input),
                      style: TextStyle(
                        color: widget.isDark
                            ? BrandColors.nightText
                            : BrandColors.charcoal,
                        fontSize: TypographyTokens.labelSmall,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ],
                  // Result section
                  if (hasResult) ...[
                    if (hasInput) const SizedBox(height: Spacing.sm),
                    Row(
                      children: [
                        Text(
                          toolCall.isError ? 'Error' : 'Result',
                          style: TextStyle(
                            color: toolCall.isError
                                ? BrandColors.error
                                : (widget.isDark
                                    ? BrandColors.nightForest
                                    : BrandColors.forest),
                            fontSize: TypographyTokens.labelSmall - 1,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Icon(
                          toolCall.isError ? Icons.error_outline : Icons.check_circle_outline,
                          size: 12,
                          color: toolCall.isError
                              ? BrandColors.error
                              : (widget.isDark
                                  ? BrandColors.nightForest
                                  : BrandColors.forest),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _formatResult(toolCall.result!),
                          style: TextStyle(
                            color: toolCall.isError
                                ? BrandColors.error.withValues(alpha: 0.9)
                                : (widget.isDark
                                    ? BrandColors.nightText
                                    : BrandColors.charcoal),
                            fontSize: TypographyTokens.labelSmall,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _toggleTool(int index) {
    setState(() {
      if (_expandedTools.contains(index)) {
        _expandedTools.remove(index);
      } else {
        _expandedTools.add(index);
      }
    });
  }

  String _formatToolName(String name) {
    if (name.startsWith('mcp__')) {
      final parts = name.split('__');
      if (parts.length >= 3) {
        return '${parts[1]}/${parts[2]}';
      }
    }
    return name;
  }

  String _formatInput(Map<String, dynamic> input) {
    final buffer = StringBuffer();
    for (final entry in input.entries) {
      final value = entry.value;
      String displayValue;

      if (value is String) {
        // Show more of the value when expanded
        if (value.length > 500) {
          displayValue = '${value.substring(0, 497)}...';
        } else {
          displayValue = value;
        }
      } else if (value is Map || value is List) {
        // Format JSON-like structures
        displayValue = value.toString();
        if (displayValue.length > 200) {
          displayValue = '${displayValue.substring(0, 197)}...';
        }
      } else {
        displayValue = value.toString();
      }

      buffer.writeln('${entry.key}: $displayValue');
    }
    return buffer.toString().trimRight();
  }

  String _formatResult(String result) {
    // Truncate very long results
    if (result.length > 2000) {
      return '${result.substring(0, 1997)}...';
    }
    return result;
  }

  IconData _getToolIcon(String toolName) {
    final name = toolName.toLowerCase();
    if (name.contains('read')) return Icons.description_outlined;
    if (name.contains('bash')) return Icons.terminal;
    if (name.contains('glob') || name.contains('grep')) return Icons.search;
    if (name.contains('write') || name.contains('edit')) return Icons.edit_outlined;
    if (name.contains('task')) return Icons.task_alt;
    if (name.contains('search')) return Icons.search;
    if (name.contains('image') || name.contains('generate')) return Icons.image_outlined;
    if (name.contains('browser') || name.contains('navigate')) return Icons.public;
    if (name.contains('click')) return Icons.mouse;
    if (name.contains('snapshot')) return Icons.camera_alt_outlined;
    return Icons.build_outlined;
  }
}
