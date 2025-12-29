import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/file_system_provider.dart';
import 'package:parachute_chat/core/services/export_detection_service.dart';
import '../providers/context_providers.dart';

/// Dialog shown when AGENTS.md or prompts.yaml don't exist
///
/// Offers to create default files to help the AI understand the user better.
/// If exports are detected, offers to use them to pre-populate the vault.
class VaultSetupDialog extends ConsumerStatefulWidget {
  const VaultSetupDialog({super.key});

  /// Show the dialog and return true if files were created
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const VaultSetupDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<VaultSetupDialog> createState() => _VaultSetupDialogState();
}

class _VaultSetupDialogState extends ConsumerState<VaultSetupDialog> {
  bool _isCreating = false;
  bool _useClaudeMemories = true;

  Future<void> _createFiles({DetectedExport? claudeExport}) async {
    setState(() => _isCreating = true);

    try {
      String? memoriesContext;

      // If we have a Claude export with memories, format them as context
      if (claudeExport != null && claudeExport.hasMemories && _useClaudeMemories) {
        final exportService = ref.read(exportDetectionServiceProvider);
        memoriesContext = await exportService.formatClaudeMemoriesAsContext(claudeExport.path);
      }

      // Initialize with or without memories
      await ref.read(initializeVaultWithMemoriesProvider)(memoriesContext);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create files: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final exportsAsync = ref.watch(availableExportsProvider);

    return AlertDialog(
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      title: Text(
        'Set up your vault',
        style: TextStyle(
          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: exportsAsync.when(
        loading: () => const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => _buildContent(isDark, []),
        data: (exports) => _buildContent(isDark, exports),
      ),
      actions: exportsAsync.when(
        loading: () => [],
        error: (_, __) => _buildActions(isDark, []),
        data: (exports) => _buildActions(isDark, exports),
      ),
    );
  }

  Widget _buildContent(bool isDark, List<DetectedExport> exports) {
    final claudeExport = exports.where((e) => e.type == ExportType.claude && e.hasMemories).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          claudeExport != null
              ? 'We found your Claude export! Create your vault profile with your existing context.'
              : 'Create your vault profile to help the AI understand you better.',
          style: TextStyle(
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            height: TypographyTokens.lineHeightRelaxed,
          ),
        ),
        const SizedBox(height: Spacing.lg),

        // Show Claude export info if found
        if (claudeExport != null) ...[
          _ExportInfoCard(
            export: claudeExport,
            isDark: isDark,
            useMemories: _useClaudeMemories,
            onToggleMemories: (value) {
              setState(() => _useClaudeMemories = value);
            },
          ),
          const SizedBox(height: Spacing.lg),
        ],

        _SetupItem(
          icon: Icons.description_outlined,
          title: 'AGENTS.md',
          subtitle: claudeExport != null && _useClaudeMemories
              ? 'Pre-filled with your Claude context'
              : 'Your profile and vault context',
          isDark: isDark,
          highlight: claudeExport != null && _useClaudeMemories,
        ),
        const SizedBox(height: Spacing.sm),
        _SetupItem(
          icon: Icons.bolt_outlined,
          title: 'prompts.yaml',
          subtitle: 'Quick actions for common tasks',
          isDark: isDark,
        ),

        // Show import tip only if no exports found
        if (exports.isEmpty) ...[
          const SizedBox(height: Spacing.lg),
          _ImportTip(isDark: isDark),
        ],
      ],
    );
  }

  List<Widget> _buildActions(bool isDark, List<DetectedExport> exports) {
    final claudeExport = exports.where((e) => e.type == ExportType.claude && e.hasMemories).firstOrNull;

    return [
      TextButton(
        onPressed: _isCreating ? null : () => Navigator.of(context).pop(false),
        child: Text(
          'Skip for now',
          style: TextStyle(
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
      ),
      FilledButton(
        onPressed: _isCreating ? null : () => _createFiles(claudeExport: claudeExport),
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        child: _isCreating
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(claudeExport != null && _useClaudeMemories
                ? 'Import & create'
                : 'Create files'),
      ),
    ];
  }
}

class _ExportInfoCard extends StatelessWidget {
  final DetectedExport export;
  final bool isDark;
  final bool useMemories;
  final ValueChanged<bool> onToggleMemories;

  const _ExportInfoCard({
    required this.export,
    required this.isDark,
    required this.useMemories,
    required this.onToggleMemories,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightForest.withValues(alpha: 0.15)
            : BrandColors.forestMist.withValues(alpha: 0.7),
        borderRadius: Radii.card,
        border: Border.all(
          color: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.3)
              : BrandColors.forest.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 20,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Claude Export Found',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightForest : BrandColors.forestDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Includes ${export.summary}',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Use memories to pre-fill your profile',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
              ),
              Switch(
                value: useMemories,
                onChanged: onToggleMemories,
                activeColor: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetupItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final bool highlight;

  const _SetupItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(Spacing.sm),
          decoration: BoxDecoration(
            color: highlight
                ? (isDark
                    ? BrandColors.nightForest.withValues(alpha: 0.2)
                    : BrandColors.forestMist)
                : (isDark
                    ? BrandColors.nightSurface
                    : BrandColors.stone.withValues(alpha: 0.5)),
            borderRadius: Radii.badge,
          ),
          child: Icon(
            icon,
            size: 20,
            color: highlight
                ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                : (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise),
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: highlight
                      ? (isDark ? BrandColors.nightForest : BrandColors.forest)
                      : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood),
                  fontWeight: highlight ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImportTip extends StatelessWidget {
  final bool isDark;

  const _ImportTip({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightSurface
            : BrandColors.stone.withValues(alpha: 0.3),
        borderRadius: Radii.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                size: 20,
                color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'Pro tip: Import your AI history',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            'Drop your ChatGPT or Claude export into ~/Parachute/imports/ and restart setup to use your existing context.',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              height: TypographyTokens.lineHeightRelaxed,
            ),
          ),
        ],
      ),
    );
  }
}
