import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/widgets/error_boundary.dart';
import 'package:parachute_chat/core/services/logger_service.dart';
import 'package:parachute_chat/features/context/providers/context_providers.dart';
import 'package:parachute_chat/features/context/widgets/prompt_chip.dart';
import 'package:parachute_chat/features/context/widgets/reflection_banner.dart';
import '../models/chat_session.dart';
import '../models/context_file.dart';
import '../providers/chat_providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/session_selector.dart';
import '../widgets/connection_status_banner.dart';
import '../widgets/resume_marker.dart';
import '../widgets/session_resume_banner.dart';

/// Main chat screen for AI conversations
///
/// Supports:
/// - Streaming responses with real-time text and tool call display
/// - Session switching via bottom sheet
/// - Agent selection
/// - Initial context (e.g., from recording transcript)
/// - Auto-run mode for standalone agents
class ChatScreen extends ConsumerStatefulWidget {
  /// Optional initial message to pre-fill
  final String? initialMessage;

  /// Optional context to include with first message (e.g., recording transcript)
  final String? initialContext;

  /// If true, automatically sends [autoRunMessage] on screen load
  final bool autoRun;

  /// Message to auto-send when [autoRun] is true
  final String? autoRunMessage;

  const ChatScreen({
    super.key,
    this.initialMessage,
    this.initialContext,
    this.autoRun = false,
    this.autoRunMessage,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _pendingInitialContext;
  bool _hasAutoRun = false;
  bool _showReflectionBanner = false;
  bool _reflectionBannerDismissed = false;
  bool _resumeBannerDismissed = false;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _pendingInitialContext = widget.initialContext;

    // Schedule auto-run after first frame
    if (widget.autoRun && widget.autoRunMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoRun();
      });
    }
  }

  void _performAutoRun() {
    if (_hasAutoRun) return;
    _hasAutoRun = true;
    _handleSend(widget.autoRunMessage!);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Motion.standard,
          curve: Motion.settling,
        );
      });
    }
  }

  void _handleSend(String message) {
    final selectedAgent = ref.read(selectedAgentProvider);
    final selectedContexts = ref.read(selectedContextsProvider);

    // Convert selected context files to paths for the API
    final contextPaths = selectedContexts.map((c) => c.path).toList();

    ref.read(chatMessagesProvider.notifier).sendMessage(
          message: message,
          agentPath: selectedAgent?.path,
          initialContext: _pendingInitialContext,
          contexts: contextPaths.isNotEmpty ? contextPaths : null,
        );

    // Clear pending context after first message
    _pendingInitialContext = null;

    _scrollToBottom();
  }

  void _handleReflect() {
    // Hide the banner
    setState(() {
      _showReflectionBanner = false;
      _reflectionBannerDismissed = true;
    });

    // Send the reflection prompt
    const reflectPrompt = '''Based on the conversation we just had, do you have any suggestions for how we might update my AGENTS.md?

Consider:
- Did I reveal anything about who I am or how I think?
- Did new topics or interests come up?
- Should any links be added to point to relevant context?

If you have suggestions, show me the specific edits you'd recommend.''';

    _handleSend(reflectPrompt);
  }

  void _showSessionRecoveryDialog(SessionUnavailableInfo info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Session Recovery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.message),
              if (info.hasMarkdownHistory) ...[
                const SizedBox(height: 12),
                Text(
                  '${info.messageCount} messages available from history.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(chatMessagesProvider.notifier).dismissSessionUnavailable();
              },
              child: const Text('Cancel'),
            ),
            if (info.hasMarkdownHistory)
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  ref.read(chatMessagesProvider.notifier).recoverSession('inject_context');
                },
                child: const Text('Continue with History'),
              ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                ref.read(chatMessagesProvider.notifier).recoverSession('fresh_start');
              },
              child: const Text('Start Fresh'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatState = ref.watch(chatMessagesProvider);
    final currentSessionId = ref.watch(currentSessionIdProvider);

    // Auto-scroll when new messages arrive and show reflection banner
    ref.listen(chatMessagesProvider, (previous, next) {
      if (next.messages.length != (previous?.messages.length ?? 0)) {
        _scrollToBottom();
      }

      // Reset resume banner when session changes
      if (previous?.sessionId != next.sessionId) {
        _resumeBannerDismissed = false;
      }

      // Show reflection banner when streaming ends and we have enough exchanges
      final wasStreaming = previous?.isStreaming ?? false;
      final isNowStreaming = next.isStreaming;
      if (wasStreaming && !isNowStreaming && !_reflectionBannerDismissed) {
        // Check if we have at least 2 message pairs (4 messages)
        if (next.messages.length >= 4 && next.messages.length > _lastMessageCount) {
          setState(() {
            _showReflectionBanner = true;
            _lastMessageCount = next.messages.length;
          });
        }
      }

      // Show session recovery dialog when session is unavailable
      if (next.sessionUnavailable != null && previous?.sessionUnavailable == null) {
        _showSessionRecoveryDialog(next.sessionUnavailable!);
      }
    });

    // Wrap in error boundary to catch rendering errors
    return ScreenErrorBoundary(
      onError: (error, stack) {
        logger.createLogger('ChatScreen').error(
          'Chat screen error',
          error: error,
          stackTrace: stack,
        );
      },
      child: Scaffold(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
        appBar: AppBar(
          backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
          surfaceTintColor: Colors.transparent,
          title: _buildTitle(context, isDark, currentSessionId),
          actions: [
            // New chat button
            IconButton(
              onPressed: () => ref.read(newChatProvider)(),
              icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner (shows when server unreachable)
          ConnectionStatusBanner(
            onSettings: () {
              // Navigate to settings
              Navigator.of(context).pushNamed('/settings');
            },
          ),

          // Session resume banner (shows when context was rebuilt)
          if (chatState.sessionResumeInfo != null && !_resumeBannerDismissed)
            SessionResumeBanner(
              resumeInfo: chatState.sessionResumeInfo!,
              onDismiss: () {
                setState(() {
                  _resumeBannerDismissed = true;
                });
              },
            ),

          // Context banner (if initial context provided)
          if (_pendingInitialContext != null)
            _buildContextBanner(context, isDark),

          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyStateOrContinuation(context, isDark, chatState)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: chatState.messages.length + (chatState.isContinuation ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show resume marker at the top if this is a continuation
                      if (chatState.isContinuation && index == 0) {
                        return ResumeMarker(
                          key: const ValueKey('resume_marker'),
                          originalSession: chatState.continuedFromSession!,
                          priorMessages: chatState.priorMessages,
                        );
                      }
                      final msgIndex = chatState.isContinuation ? index - 1 : index;
                      return MessageBubble(
                        message: chatState.messages[msgIndex],
                      );
                    },
                  ),
          ),

          // Error banner
          if (chatState.error != null)
            _buildErrorBanner(context, isDark, chatState.error!),

          // Continue button for imported sessions
          if (chatState.isViewingImported)
            _buildContinueButton(context, isDark, chatState),

          // Reflection suggestion banner
          if (_showReflectionBanner && !chatState.isStreaming)
            ReflectionBanner(
              onReflect: () => _handleReflect(),
              onDismiss: () {
                setState(() {
                  _showReflectionBanner = false;
                  _reflectionBannerDismissed = true;
                });
              },
            ),

          // Input field - disabled when viewing imported sessions (use Continue button)
          ChatInput(
            onSend: _handleSend,
            enabled: !chatState.isStreaming && !chatState.isViewingImported,
            initialText: widget.initialMessage,
            hintText: _pendingInitialContext != null
                ? 'Ask about this recording...'
                : chatState.isViewingImported
                    ? 'Click Continue to resume this conversation'
                    : 'Message your vault...',
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark, String? sessionId) {
    final chatState = ref.watch(chatMessagesProvider);
    final sessionTitle = chatState.sessionTitle;

    // Determine title text
    String titleText;
    if (sessionId == null) {
      titleText = 'New Chat';
    } else if (sessionTitle != null && sessionTitle.isNotEmpty) {
      titleText = sessionTitle;
    } else {
      titleText = 'Chat';
    }

    return GestureDetector(
      onTap: () => SessionSelector.show(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 20,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateOrContinuation(
    BuildContext context,
    bool isDark,
    ChatMessagesState chatState,
  ) {
    // If this is a continuation, show the resume marker with a prompt to continue
    if (chatState.isContinuation) {
      return ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          ResumeMarker(
            originalSession: chatState.continuedFromSession!,
            priorMessages: chatState.priorMessages,
          ),
          const SizedBox(height: Spacing.xl),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 32,
                  color: isDark ? BrandColors.nightForest : BrandColors.forest,
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Continue the conversation',
                  style: TextStyle(
                    fontSize: TypographyTokens.titleMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  'Send a message to pick up where you left off',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyMedium,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _buildEmptyState(context, isDark);
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    final promptsAsync = ref.watch(promptsProvider);
    final availableContexts = ref.watch(availableContextsProvider);
    final selectedContexts = ref.watch(selectedContextsProvider);

    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.forestMist.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_outlined,
                size: 48,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: TypographyTokens.headlineSmall,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Ask questions about your vault, get help with ideas,\nor explore your thoughts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            // Context selector
            availableContexts.when(
              data: (contexts) => contexts.isEmpty
                  ? const SizedBox.shrink()
                  : _buildContextSelector(context, isDark, contexts, selectedContexts),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: Spacing.xl),
            // Quick action prompts from prompts.yaml
            promptsAsync.when(
              data: (prompts) => Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: prompts.take(4).map((prompt) => PromptChip(
                  prompt: prompt,
                  onTap: () => _handleSend(prompt.prompt),
                )).toList(),
              ),
              loading: () => Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionChip(
                    label: 'Loading prompts...',
                    onTap: () {},
                  ),
                ],
              ),
              error: (e, st) => Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  _SuggestionChip(
                    label: 'Summarize my recent notes',
                    onTap: () => _handleSend('Summarize my recent notes'),
                  ),
                  _SuggestionChip(
                    label: 'What did I capture today?',
                    onTap: () => _handleSend('What did I capture today?'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildContextBanner(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
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
            Icons.description_outlined,
            size: 20,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Recording context attached',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color:
                    isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pendingInitialContext = null;
              });
            },
            icon: Icon(
              Icons.close,
              size: 18,
              color:
                  isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
            ),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildContextSelector(
    BuildContext context,
    bool isDark,
    List<ContextFile> availableContexts,
    List<ContextFile> selectedContexts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 14,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              'Contexts',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.sm),
        Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          alignment: WrapAlignment.center,
          children: [
            // Show selected contexts as chips
            ...selectedContexts.map((ctx) => _ContextChip(
              context: ctx,
              isSelected: true,
              onToggle: () => ref.read(toggleContextProvider)(ctx),
            )),
            // Show add button if there are more contexts to add
            if (availableContexts.length > selectedContexts.length)
              _AddContextButton(
                onTap: () => _showContextPicker(context, isDark, availableContexts, selectedContexts),
              ),
          ],
        ),
      ],
    );
  }

  void _showContextPicker(
    BuildContext context,
    bool isDark,
    List<ContextFile> available,
    List<ContextFile> selected,
  ) {
    final unselected = available.where(
      (c) => !selected.any((s) => s.path == c.path),
    ).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Context',
                style: TextStyle(
                  fontSize: TypographyTokens.titleMedium,
                  fontWeight: FontWeight.w600,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Select context files to include in this conversation',
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                ),
              ),
              const SizedBox(height: Spacing.lg),
              if (unselected.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
                  child: Center(
                    child: Text(
                      'All contexts are selected',
                      style: TextStyle(
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: unselected.map((ctx) => ListTile(
                      leading: Icon(
                        Icons.description_outlined,
                        color: isDark ? BrandColors.nightForest : BrandColors.forest,
                      ),
                      title: Text(
                        ctx.title,
                        style: TextStyle(
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: ctx.description.isNotEmpty
                          ? Text(
                              ctx.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: TypographyTokens.labelSmall,
                                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                              ),
                            )
                          : null,
                      onTap: () {
                        ref.read(toggleContextProvider)(ctx);
                        Navigator.of(sheetContext).pop();
                      },
                    )).toList(),
                  ),
                ),
              const SizedBox(height: Spacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton(
    BuildContext context,
    bool isDark,
    ChatMessagesState chatState,
  ) {
    final session = chatState.viewingSession!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightForest.withValues(alpha: 0.1)
            : BrandColors.forestMist,
        border: Border(
          top: BorderSide(
            color: isDark
                ? BrandColors.nightForest.withValues(alpha: 0.2)
                : BrandColors.forest.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 16,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Imported from ${session.source.displayName}',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => _showContinueConfirmation(context, session, isDark),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Continue'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  isDark ? BrandColors.nightForest : BrandColors.forest,
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, bool isDark, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: BrandColors.errorLight,
        borderRadius: Radii.badge,
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: BrandColors.error,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContinueConfirmation(
    BuildContext context,
    ChatSession session,
    bool isDark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        title: Text(
          'Continue conversation?',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will start a new conversation with the prior messages as context.',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.stone.withValues(alpha: 0.3),
                borderRadius: Radii.badge,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Attachments, images, and some context may not carry over perfectly.',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(continueSessionProvider)(session);
    }
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        fontSize: TypographyTokens.labelMedium,
        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
        ),
      ),
    );
  }
}

/// Chip for displaying a selected context file
class _ContextChip extends StatelessWidget {
  final ContextFile context;
  final bool isSelected;
  final VoidCallback onToggle;

  const _ContextChip({
    required this.context,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext buildContext) {
    final theme = Theme.of(buildContext);
    final isDark = theme.brightness == Brightness.dark;

    return InputChip(
      label: Text(context.title),
      onDeleted: isSelected ? onToggle : null,
      deleteIcon: const Icon(Icons.close, size: 14),
      deleteIconColor: isDark ? BrandColors.nightForest : BrandColors.forest,
      backgroundColor: isDark
          ? BrandColors.nightForest.withValues(alpha: 0.15)
          : BrandColors.forestMist.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        fontSize: TypographyTokens.labelSmall,
        color: isDark ? BrandColors.nightForest : BrandColors.forest,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.3)
              : BrandColors.forest.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Button to add more context files
class _AddContextButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddContextButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      avatar: Icon(
        Icons.add,
        size: 14,
        color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
      ),
      label: Text(
        'Add',
        style: TextStyle(
          fontSize: TypographyTokens.labelSmall,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
      ),
      onPressed: onTap,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      visualDensity: VisualDensity.compact,
    );
  }
}
