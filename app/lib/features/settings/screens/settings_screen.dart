import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/features/recorder/providers/omi_providers.dart';
import 'package:app/features/recorder/utils/platform_utils.dart';
import '../widgets/expandable_settings_section.dart';
import '../widgets/device_integration_section.dart';
import '../widgets/ai_chat_section.dart';
import '../widgets/storage_section.dart';
import '../widgets/omi_device_section.dart';
import '../widgets/transcription_section.dart';
import '../widgets/title_generation_section.dart';
import '../widgets/privacy_section.dart';
import '../widgets/developer_section.dart';

/// Settings screen with expandable sections
///
/// Organized into logical groups for better discoverability:
/// - Recording & Transcription
/// - Storage & Sync
/// - Devices (if available)
/// - Advanced
/// - Developer
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _omiEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOmiState();
  }

  Future<void> _loadOmiState() async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    _omiEnabled = await featureFlagsService.isOmiEnabled();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firmwareService = ref.watch(omiFirmwareServiceProvider);
    final isFirmwareUpdating = firmwareService.isUpdating;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !isFirmwareUpdating,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Cannot navigate away during firmware update! '
              'Interrupting the update may brick your device.',
            ),
            backgroundColor: BrandColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
      },
      child: Scaffold(
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
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDark ? BrandColors.nightForest : BrandColors.forest,
                  ),
                ),
              )
            : ListView(
                padding: EdgeInsets.all(Spacing.lg),
                children: [
                  // Recording & Transcription Section
                  _buildRecordingSection(isDark),

                  // Storage & Sync Section
                  _buildStorageSyncSection(isDark),

                  // Devices Section (only on supported platforms)
                  if (PlatformUtils.shouldShowOmiFeatures)
                    _buildDevicesSection(isDark),

                  // Advanced Section
                  _buildAdvancedSection(isDark),

                  // Developer Section
                  const DeveloperSection(),

                  // Bottom padding
                  SizedBox(height: Spacing.xxl),
                ],
              ),
      ),
    );
  }

  Widget _buildRecordingSection(bool isDark) {
    return ExpandableSettingsSection(
      title: 'Recording & Transcription',
      subtitle: 'Voice capture, AI transcription, and title generation',
      icon: Icons.mic,
      accentColor: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
      initiallyExpanded: true,
      children: const [
        TranscriptionSection(),
        TitleGenerationSection(),
      ],
    );
  }

  Widget _buildStorageSyncSection(bool isDark) {
    return ExpandableSettingsSection(
      title: 'Storage',
      subtitle: 'File locations and folder settings',
      icon: Icons.folder_open,
      accentColor: isDark ? BrandColors.nightForest : BrandColors.forest,
      children: const [
        StorageSection(),
      ],
    );
  }

  Widget _buildDevicesSection(bool isDark) {
    return ExpandableSettingsSection(
      title: 'Devices',
      subtitle: 'Omi wearable and Bluetooth connections',
      icon: Icons.bluetooth,
      accentColor: BrandColors.turquoiseDeep,
      trailing: _omiEnabled
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm,
                vertical: Spacing.xs,
              ),
              decoration: BoxDecoration(
                color: BrandColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text(
                'ENABLED',
                style: TextStyle(
                  fontSize: TypographyTokens.labelSmall - 1,
                  fontWeight: FontWeight.bold,
                  color: BrandColors.success,
                ),
              ),
            )
          : null,
      children: [
        const DeviceIntegrationSection(),
        if (_omiEnabled) const OmiDeviceSection(),
      ],
    );
  }

  Widget _buildAdvancedSection(bool isDark) {
    return ExpandableSettingsSection(
      title: 'Advanced',
      subtitle: 'AI chat server and privacy settings',
      icon: Icons.tune,
      accentColor: BrandColors.driftwood,
      children: const [
        AiChatSection(),
        PrivacySection(),
      ],
    );
  }
}
