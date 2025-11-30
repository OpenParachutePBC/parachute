import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/core/providers/feature_flags_provider.dart';
import 'package:app/features/recorder/utils/platform_utils.dart';
import './settings_section_header.dart';

/// Device Integration settings section (Omi device toggle)
class DeviceIntegrationSection extends ConsumerStatefulWidget {
  const DeviceIntegrationSection({super.key});

  @override
  ConsumerState<DeviceIntegrationSection> createState() =>
      _DeviceIntegrationSectionState();
}

class _DeviceIntegrationSectionState
    extends ConsumerState<DeviceIntegrationSection> {
  bool _omiEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    _omiEnabled = await featureFlagsService.isOmiEnabled();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setOmiEnabled(bool enabled) async {
    final featureFlagsService = ref.read(featureFlagsServiceProvider);
    await featureFlagsService.setOmiEnabled(enabled);
    setState(() => _omiEnabled = enabled);

    // Invalidate the provider to update the UI
    ref.invalidate(omiEnabledNotifierProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Omi device integration enabled'
                : 'Omi device integration disabled',
          ),
          backgroundColor: BrandColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show on supported platforms
    if (!PlatformUtils.shouldShowOmiFeatures) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Device Integration',
          subtitle: 'Connect Bluetooth devices like Omi wearables',
          icon: Icons.headphones,
        ),
        SizedBox(height: Spacing.lg),

        // Omi Enable Toggle
        SettingsToggleCard(
          title: 'Enable Omi Device',
          subtitle: _omiEnabled
              ? 'Omi device support is enabled'
              : 'Enable to connect Omi wearable',
          icon: Icons.bluetooth,
          value: _omiEnabled,
          onChanged: _setOmiEnabled,
          activeColor: BrandColors.turquoise,
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
