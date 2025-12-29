import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/chat/providers/chat_providers.dart';
import 'package:parachute_chat/features/chat/models/system_prompt_info.dart';
import './settings_section_header.dart';

/// Provider for fetching default prompt info
final defaultPromptProvider = FutureProvider<DefaultPromptInfo>((ref) async {
  final service = ref.watch(chatServiceProvider);
  return service.getDefaultPrompt();
});

/// Provider for fetching AGENTS.md info
final agentsMdProvider = FutureProvider<AgentsMdInfo>((ref) async {
  final service = ref.watch(chatServiceProvider);
  return service.getAgentsMd();
});

/// Settings section for viewing and customizing the system prompt
class SystemPromptSection extends ConsumerStatefulWidget {
  const SystemPromptSection({super.key});

  @override
  ConsumerState<SystemPromptSection> createState() => _SystemPromptSectionState();
}

class _SystemPromptSectionState extends ConsumerState<SystemPromptSection> {
  Future<void> _copyToAgentsMd(String defaultContent) async {
    final service = ref.read(chatServiceProvider);

    try {
      // Add a header comment to help users understand
      final contentWithHeader = '''# Custom System Prompt

<!--
  This file overrides Parachute's built-in default prompt.
  Edit this to customize how your AI assistant behaves.
  Delete this file to return to the default behavior.
-->

$defaultContent''';

      await service.saveAgentsMd(contentWithHeader);

      // Invalidate the providers to refresh the UI
      ref.invalidate(defaultPromptProvider);
      ref.invalidate(agentsMdProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Created AGENTS.md - you can now edit it in your vault'),
            backgroundColor: BrandColors.success,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create AGENTS.md: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  void _showPromptViewer(BuildContext context, String content, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.md),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'Default System Prompt',
                      style: TextStyle(
                        fontSize: TypographyTokens.titleMedium,
                        fontWeight: FontWeight.w600,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.copy,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                    tooltip: 'Copy to clipboard',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(Spacing.lg),
                child: SelectableText(
                  content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultPromptAsync = ref.watch(defaultPromptProvider);
    final agentsMdAsync = ref.watch(agentsMdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'System Prompt',
          subtitle: 'Customize how your AI assistant behaves',
          icon: Icons.psychology_outlined,
        ),
        const SizedBox(height: Spacing.md),

        // Main card
        Container(
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                  : BrandColors.stone,
            ),
          ),
          child: defaultPromptAsync.when(
            data: (promptInfo) => agentsMdAsync.when(
              data: (agentsMd) => _buildContent(
                context,
                isDark,
                promptInfo,
                agentsMd,
              ),
              loading: () => _buildLoading(isDark),
              error: (e, _) => _buildContent(
                context,
                isDark,
                promptInfo,
                const AgentsMdInfo(exists: false),
              ),
            ),
            loading: () => _buildLoading(isDark),
            error: (e, _) => _buildError(isDark, e.toString()),
          ),
        ),

        const SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildLoading(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
        ),
      ),
    );
  }

  Widget _buildError(bool isDark, String error) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: BrandColors.error),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Could not load prompt info: $error',
              style: TextStyle(
                color: BrandColors.error,
                fontSize: TypographyTokens.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool isDark,
    DefaultPromptInfo promptInfo,
    AgentsMdInfo agentsMd,
  ) {
    final hasOverride = agentsMd.exists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status row
        Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: (hasOverride ? BrandColors.turquoise : BrandColors.forest)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  hasOverride ? Icons.edit_document : Icons.auto_awesome,
                  color: hasOverride ? BrandColors.turquoise : BrandColors.forest,
                  size: 24,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasOverride ? 'Custom Prompt Active' : 'Using Default Prompt',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: TypographyTokens.bodyMedium,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      hasOverride
                          ? 'Your AGENTS.md overrides the default'
                          : 'Parachute\'s built-in system prompt',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasOverride)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm,
                    vertical: Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: BrandColors.turquoise.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    'CUSTOM',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall - 1,
                      fontWeight: FontWeight.bold,
                      color: BrandColors.turquoise,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Actions
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            children: [
              // View default prompt button
              _ActionTile(
                icon: Icons.visibility_outlined,
                title: 'View Default Prompt',
                subtitle: 'See what Parachute uses by default',
                onTap: () => _showPromptViewer(context, promptInfo.content, isDark),
                isDark: isDark,
              ),

              if (!hasOverride) ...[
                const SizedBox(height: Spacing.sm),
                // Customize button (only when no override exists)
                _ActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Customize Prompt',
                  subtitle: 'Copy default to AGENTS.md and edit',
                  onTap: () => _showCustomizeDialog(context, promptInfo.content, isDark),
                  isDark: isDark,
                  accent: true,
                ),
              ],

              if (hasOverride) ...[
                const SizedBox(height: Spacing.sm),
                // View current override
                _ActionTile(
                  icon: Icons.description_outlined,
                  title: 'View Current AGENTS.md',
                  subtitle: 'See your custom system prompt',
                  onTap: () => _showPromptViewer(
                    context,
                    agentsMd.content ?? '',
                    isDark,
                  ),
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),

        // Info footer
        Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurface
                : BrandColors.stone.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(Radii.md),
              bottomRight: Radius.circular(Radii.md),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  hasOverride
                      ? 'Edit AGENTS.md in your vault to change behavior. Delete it to return to default.'
                      : 'Create AGENTS.md in your vault root to customize.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomizeDialog(
    BuildContext context,
    String defaultContent,
    bool isDark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        title: Row(
          children: [
            Icon(
              Icons.edit_document,
              color: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            const SizedBox(width: Spacing.sm),
            const Text('Customize System Prompt'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will create AGENTS.md in your vault with the default prompt as a starting point.',
              style: TextStyle(
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurface
                    : BrandColors.stone.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: BrandColors.turquoise,
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'You can edit AGENTS.md in any text editor or Obsidian.',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create AGENTS.md'),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _copyToAgentsMd(defaultContent);
    }
  }
}

/// A tappable action tile for the prompt section
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;
  final bool accent;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? (isDark ? BrandColors.nightForest : BrandColors.forest)
        : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: accent
              ? BoxDecoration(
                  color: (isDark ? BrandColors.nightForest : BrandColors.forest)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                    color: (isDark ? BrandColors.nightForest : BrandColors.forest)
                        .withValues(alpha: 0.3),
                  ),
                )
              : null,
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
