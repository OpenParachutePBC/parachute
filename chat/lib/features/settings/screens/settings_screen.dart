import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/providers/feature_flags_provider.dart';
import '../widgets/expandable_settings_section.dart';
import '../widgets/ai_chat_section.dart';
import '../widgets/storage_section.dart';
import '../widgets/chat_import_section.dart';
import '../widgets/privacy_section.dart';
import '../widgets/developer_section.dart';
import '../widgets/system_prompt_section.dart';
import '../widgets/generation_section.dart';

/// Settings screen with expandable sections
///
/// Organized into logical groups:
/// - Storage
/// - Advanced (AI chat, generation, import, privacy)
/// - Developer
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
        elevation: 0,
      ),
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg),
        children: [
          // Storage Section
          _buildStorageSection(isDark),

          // Advanced Section (AI chat, generation, etc.)
          _buildAdvancedSection(isDark, ref),

          // Developer Section
          const DeveloperSection(),

          // Bottom padding
          SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }

  Widget _buildStorageSection(bool isDark) {
    return ExpandableSettingsSection(
      title: 'Storage',
      subtitle: 'File locations and folder settings',
      icon: Icons.folder_open,
      accentColor: isDark ? BrandColors.nightForest : BrandColors.forest,
      initiallyExpanded: true,
      children: const [
        StorageSection(),
      ],
    );
  }

  Widget _buildAdvancedSection(bool isDark, WidgetRef ref) {
    // Watch AI Chat enabled state to conditionally show import section
    final aiChatEnabled = ref.watch(aiChatEnabledNotifierProvider).valueOrNull ?? false;

    return ExpandableSettingsSection(
      title: 'Advanced',
      subtitle: 'AI chat, generation, and privacy settings',
      icon: Icons.tune,
      accentColor: BrandColors.driftwood,
      children: [
        const AiChatSection(),
        // Only show these sections when AI Chat is enabled
        if (aiChatEnabled) ...[
          const SystemPromptSection(),
          const GenerationSection(),
          const ChatImportSection(),
        ],
        const PrivacySection(),
      ],
    );
  }
}
