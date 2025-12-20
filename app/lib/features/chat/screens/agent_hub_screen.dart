import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/context/providers/context_providers.dart';
import 'package:app/features/context/widgets/prompts_bottom_sheet.dart';
import 'package:app/features/context/widgets/prompt_chip.dart';
import '../models/chat_session.dart';
import '../providers/chat_providers.dart';
import '../widgets/session_list_item.dart';
import 'chat_screen.dart';

/// Chat Hub - Main entry point for AI conversations
///
/// Shows a list of recent chat sessions grouped by date,
/// with quick access to start new conversations.
class AgentHubScreen extends ConsumerWidget {
  const AgentHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sessionsAsync = ref.watch(chatSessionsProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Chat',
          style: TextStyle(
            fontSize: TypographyTokens.titleLarge,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        actions: [
          // Quick prompts button
          IconButton(
            onPressed: () => _showPromptsSheet(context, ref),
            icon: Icon(
              Icons.bolt_outlined,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
            tooltip: 'Quick Actions',
          ),
          // New chat button
          IconButton(
            onPressed: () => _startNewChat(context, ref),
            icon: Icon(
              Icons.add_comment_outlined,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            tooltip: 'New Chat',
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          // Sessions list
          Expanded(
            child: sessionsAsync.when(
              data: (sessions) => _buildSessionsList(context, ref, sessions, isDark),
              loading: () => _buildLoading(isDark),
              error: (e, _) => _buildError(isDark, e.toString()),
            ),
          ),

          // Quick chat input at bottom
          _buildQuickChatInput(context, ref, isDark),
        ],
      ),
    );
  }

  Widget _buildSessionsList(
    BuildContext context,
    WidgetRef ref,
    List<ChatSession> sessions,
    bool isDark,
  ) {
    // Filter out archived sessions
    final activeSessions = sessions.where((s) => !s.archived).toList();

    if (activeSessions.isEmpty) {
      return _buildEmptyState(context, ref, isDark);
    }

    // Group sessions by date
    final grouped = _groupSessionsByDate(activeSessions);

    return ListView.builder(
      padding: const EdgeInsets.all(Spacing.md),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return _buildDateGroup(context, ref, group, isDark);
      },
    );
  }

  Widget _buildDateGroup(
    BuildContext context,
    WidgetRef ref,
    _SessionGroup group,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: const EdgeInsets.only(
            left: Spacing.xs,
            top: Spacing.md,
            bottom: Spacing.sm,
          ),
          child: Text(
            group.label,
            style: TextStyle(
              fontSize: TypographyTokens.labelMedium,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        ),
        // Sessions in this group
        ...group.sessions.map((session) => Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: SessionListItem(
                session: session,
                onTap: () => _handleSessionTap(context, ref, session),
                onDelete: () => _handleSessionDelete(ref, session),
              ),
            )),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool isDark) {
    final promptsAsync = ref.watch(promptsProvider);

    return Center(
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
              'Your AI assistant has access to your vault.\nAsk questions, explore ideas, or just think out loud.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.xxl),

            // Quick prompts
            promptsAsync.when(
              data: (prompts) => Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                alignment: WrapAlignment.center,
                children: prompts.take(3).map((prompt) => PromptChip(
                      prompt: prompt,
                      onTap: () => _startNewChatWithPrompt(context, ref, prompt.prompt),
                    )).toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
      ),
    );
  }

  Widget _buildError(bool isDark, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Couldn\'t load conversations',
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Check that the agent server is running',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChatInput(BuildContext context, WidgetRef ref, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: () => _startNewChat(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurface
                  : BrandColors.stone.withValues(alpha: 0.5),
              borderRadius: Radii.pill,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 20,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Start a new conversation...',
                  style: TextStyle(
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
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

  // ============================================================
  // Actions
  // ============================================================

  void _showPromptsSheet(BuildContext context, WidgetRef ref) {
    PromptsBottomSheet.show(
      context,
      onPromptSelected: (prompt) => _startNewChatWithPrompt(context, ref, prompt),
    );
  }

  void _startNewChat(BuildContext context, WidgetRef ref) {
    ref.read(newChatProvider)();
    ref.read(selectedAgentProvider.notifier).state = null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ChatScreen(),
      ),
    );
  }

  void _startNewChatWithPrompt(BuildContext context, WidgetRef ref, String prompt) {
    ref.read(newChatProvider)();
    ref.read(selectedAgentProvider.notifier).state = null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(initialMessage: prompt),
      ),
    );
  }

  void _handleSessionTap(BuildContext context, WidgetRef ref, ChatSession session) {
    ref.read(switchSessionProvider)(session.id);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ChatScreen(),
      ),
    );
  }

  Future<void> _handleSessionDelete(WidgetRef ref, ChatSession session) async {
    await ref.read(deleteSessionProvider)(session.id);
  }

  // ============================================================
  // Helpers
  // ============================================================

  List<_SessionGroup> _groupSessionsByDate(List<ChatSession> sessions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));

    final todaySessions = <ChatSession>[];
    final yesterdaySessions = <ChatSession>[];
    final thisWeekSessions = <ChatSession>[];
    final earlierSessions = <ChatSession>[];

    for (final session in sessions) {
      final sessionDate = DateTime(
        session.createdAt.year,
        session.createdAt.month,
        session.createdAt.day,
      );

      if (sessionDate == today) {
        todaySessions.add(session);
      } else if (sessionDate == yesterday) {
        yesterdaySessions.add(session);
      } else if (sessionDate.isAfter(thisWeekStart) || sessionDate == thisWeekStart) {
        thisWeekSessions.add(session);
      } else {
        earlierSessions.add(session);
      }
    }

    final groups = <_SessionGroup>[];

    if (todaySessions.isNotEmpty) {
      groups.add(_SessionGroup(label: 'Today', sessions: todaySessions));
    }
    if (yesterdaySessions.isNotEmpty) {
      groups.add(_SessionGroup(label: 'Yesterday', sessions: yesterdaySessions));
    }
    if (thisWeekSessions.isNotEmpty) {
      groups.add(_SessionGroup(label: 'This Week', sessions: thisWeekSessions));
    }
    if (earlierSessions.isNotEmpty) {
      groups.add(_SessionGroup(label: 'Earlier', sessions: earlierSessions));
    }

    return groups;
  }
}

class _SessionGroup {
  final String label;
  final List<ChatSession> sessions;

  const _SessionGroup({
    required this.label,
    required this.sessions,
  });
}
