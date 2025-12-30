import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import '../widgets/storage_section.dart';
import '../widgets/local_ai_models_section.dart';
import '../widgets/omi_device_section.dart';

/// Settings screen for Parachute Daily
///
/// Contains:
/// - Storage settings (vault path)
/// - Local AI Models (transcription, embeddings)
/// - Omi Device (pairing, firmware)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor:
            isDark ? BrandColors.nightSurface : BrandColors.softWhite,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          StorageSection(),
          SizedBox(height: 24),
          LocalAiModelsSection(),
          SizedBox(height: 24),
          OmiDeviceSection(),
        ],
      ),
    );
  }
}
