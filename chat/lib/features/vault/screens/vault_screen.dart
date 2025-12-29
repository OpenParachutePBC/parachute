import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/settings/screens/settings_screen.dart';
import 'package:parachute_chat/features/vault/widgets/browse_content.dart';

/// Vault screen for browsing vault files
///
/// Provides file system navigation with folder hierarchy.
/// Search and Ask functionality is available through the AI agent in Chat.
class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
      body: const BrowseContent(),
    );
  }
}
