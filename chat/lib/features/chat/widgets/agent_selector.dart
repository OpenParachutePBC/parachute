import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import '../models/agent.dart';
import '../providers/chat_providers.dart';

/// Dropdown for selecting an AI agent
class AgentSelector extends ConsumerWidget {
  const AgentSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final agentsAsync = ref.watch(agentsProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);

    return agentsAsync.when(
      data: (agents) {
        // Include default vault agent at the start
        final allAgents = [vaultAgent, ...agents];
        final currentAgent = selectedAgent ?? vaultAgent;

        return PopupMenuButton<Agent>(
          initialValue: currentAgent,
          onSelected: (agent) {
            ref.read(selectedAgentProvider.notifier).state =
                agent.path.isEmpty ? null : agent;
          },
          tooltip: 'Select agent',
          offset: const Offset(0, 40),
          shape: RoundedRectangleBorder(borderRadius: Radii.card),
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.xs,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated
                  : BrandColors.stone.withValues(alpha: 0.5),
              borderRadius: Radii.badge,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  currentAgent.path.isEmpty
                      ? Icons.chat_bubble_outline
                      : Icons.smart_toy_outlined,
                  size: 16,
                  color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                ),
                const SizedBox(width: Spacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    currentAgent.name,
                    style: TextStyle(
                      fontSize: TypographyTokens.labelMedium,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => allAgents.map((agent) {
            final isSelected = agent.path == currentAgent.path;
            return PopupMenuItem<Agent>(
              value: agent,
              child: Row(
                children: [
                  Icon(
                    agent.path.isEmpty
                        ? Icons.chat_bubble_outline
                        : Icons.smart_toy_outlined,
                    size: 18,
                    color: isSelected
                        ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                        : (isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          agent.name,
                          style: TextStyle(
                            fontSize: TypographyTokens.bodyMedium,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                        if (agent.description != null &&
                            agent.description!.isNotEmpty)
                          Text(
                            agent.description!,
                            style: TextStyle(
                              fontSize: TypographyTokens.labelSmall,
                              color: isDark
                                  ? BrandColors.nightTextSecondary
                                  : BrandColors.driftwood,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check,
                      size: 18,
                      color:
                          isDark ? BrandColors.nightForest : BrandColors.forest,
                    ),
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.5),
          borderRadius: Radii.badge,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: TypographyTokens.labelMedium,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ),
      error: (_, _) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        decoration: BoxDecoration(
          color: BrandColors.errorLight,
          borderRadius: Radii.badge,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 16,
              color: BrandColors.error,
            ),
            const SizedBox(width: Spacing.xs),
            Text(
              'Error',
              style: TextStyle(
                fontSize: TypographyTokens.labelMedium,
                color: BrandColors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
