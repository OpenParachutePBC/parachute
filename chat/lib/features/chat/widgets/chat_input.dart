import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';

/// Text input field for chat messages
class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool enabled;
  final String? initialText;
  final String hintText;

  const ChatInput({
    super.key,
    required this.onSend,
    this.enabled = true,
    this.initialText,
    this.hintText = 'Message your vault...',
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;

    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.cream,
                  borderRadius: Radii.button,
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                        : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
                    width: _focusNode.hasFocus ? 1.5 : 1,
                  ),
                ),
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    // Send on Enter (without Shift)
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _handleSend();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    style: TextStyle(
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      fontSize: TypographyTokens.bodyMedium,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                        fontSize: TypographyTokens.bodyMedium,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.sm,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: Spacing.sm),

            // Send button
            AnimatedContainer(
              duration: Motion.quick,
              curve: Motion.settling,
              child: IconButton(
                onPressed: (_hasText && widget.enabled) ? _handleSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: (_hasText && widget.enabled)
                      ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                      : (isDark
                          ? BrandColors.nightSurfaceElevated
                          : BrandColors.stone),
                  foregroundColor: (_hasText && widget.enabled)
                      ? Colors.white
                      : (isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood),
                  shape: RoundedRectangleBorder(
                    borderRadius: Radii.button,
                  ),
                ),
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
