import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/vault/widgets/search_content.dart';
import 'package:app/features/vault/widgets/browse_content.dart';
import 'package:app/features/vault/widgets/ask_content.dart';

/// Tab options for the Vault screen
enum VaultTab { search, ask, browse }

/// Provider for current vault tab
final vaultTabProvider = StateProvider<VaultTab>((ref) => VaultTab.search);

/// Unified Vault screen combining Search and File Browser
///
/// Provides two sub-tabs:
/// - Search: Keyword and semantic search across vault content
/// - Browse: File system navigation with folder hierarchy
class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currentTab = ref.watch(vaultTabProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Vault',
          style: TextStyle(
            fontSize: TypographyTokens.titleLarge,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab selector
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.md,
              Spacing.sm,
              Spacing.md,
              0,
            ),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<VaultTab>(
                segments: [
                  ButtonSegment<VaultTab>(
                    value: VaultTab.search,
                    label: const Text('Search'),
                    icon: const Icon(Icons.search, size: 18),
                  ),
                  ButtonSegment<VaultTab>(
                    value: VaultTab.ask,
                    label: const Text('Ask'),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                  ),
                  ButtonSegment<VaultTab>(
                    value: VaultTab.browse,
                    label: const Text('Browse'),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                  ),
                ],
                selected: {currentTab},
                onSelectionChanged: (Set<VaultTab> newSelection) {
                  ref.read(vaultTabProvider.notifier).state = newSelection.first;
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return isDark ? BrandColors.nightForest : BrandColors.forest;
                    }
                    return Colors.transparent;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return isDark ? BrandColors.nightText : BrandColors.charcoal;
                  }),
                ),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: switch (currentTab) {
              VaultTab.search => const SearchContent(),
              VaultTab.ask => const AskContent(),
              VaultTab.browse => const BrowseContent(),
            },
          ),
        ],
      ),
    );
  }
}
