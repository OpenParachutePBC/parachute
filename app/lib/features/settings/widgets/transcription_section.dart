import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/providers/transcription_init_provider.dart';
import './settings_section_header.dart';

/// Transcription settings section (Parakeet model and toggles)
class TranscriptionSection extends ConsumerStatefulWidget {
  const TranscriptionSection({super.key});

  @override
  ConsumerState<TranscriptionSection> createState() =>
      _TranscriptionSectionState();
}

class _TranscriptionSectionState extends ConsumerState<TranscriptionSection> {
  bool _autoTranscribe = false;
  bool _autoEnhance = true;
  bool _autoPauseRecording = false;
  bool _audioDebugOverlay = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storageService = ref.read(storageServiceProvider);

    _autoTranscribe = await storageService.getAutoTranscribe();
    _autoEnhance = await storageService.getAutoEnhance();
    _autoPauseRecording = await storageService.getAutoPauseRecording();
    _audioDebugOverlay = await storageService.getAudioDebugOverlay();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setAutoTranscribe(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoTranscribe(enabled);
    setState(() => _autoTranscribe = enabled);
  }

  Future<void> _setAutoEnhance(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoEnhance(enabled);
    setState(() => _autoEnhance = enabled);
  }

  Future<void> _setAutoPauseRecording(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoPauseRecording(enabled);
    setState(() => _autoPauseRecording = enabled);
  }

  Future<void> _setAudioDebugOverlay(bool enabled) async {
    await ref.read(storageServiceProvider).setAudioDebugOverlay(enabled);
    setState(() => _audioDebugOverlay = enabled);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Watch the transcription init state - this persists across navigation
    final initState = ref.watch(transcriptionInitProvider);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Transcription',
          subtitle:
              'Powered by Parakeet v3 - NVIDIA NeMo 600M parameter multilingual ASR',
          icon: Icons.record_voice_over,
        ),
        SizedBox(height: Spacing.xl),

        // Parakeet Model Status Card
        _buildParakeetModelCard(isDark, initState),
        SizedBox(height: Spacing.xl),

        // Auto-transcribe toggle
        _buildToggleListTile(
          title: 'Auto-transcribe recordings',
          subtitle: 'Automatically transcribe after recording stops',
          value: _autoTranscribe,
          onChanged: _setAutoTranscribe,
          isDark: isDark,
        ),
        SizedBox(height: Spacing.md),

        // Auto-enhance toggle
        _buildToggleListTile(
          title: 'AI enhance transcriptions',
          subtitle: 'Clean up text and generate titles using local AI',
          value: _autoEnhance,
          onChanged: _setAutoEnhance,
          isDark: isDark,
        ),
        SizedBox(height: Spacing.md),

        // Auto-pause toggle
        _buildToggleListTile(
          title: 'Auto-pause recording',
          subtitle: 'Automatically detect silence and segment recordings',
          value: _autoPauseRecording,
          onChanged: _setAutoPauseRecording,
          isDark: isDark,
        ),
        SizedBox(height: Spacing.md),

        // Audio debug overlay toggle
        _buildToggleListTile(
          title: 'Audio debug overlay',
          subtitle: 'Show real-time audio levels and noise filtering graph',
          value: _audioDebugOverlay,
          onChanged: _setAudioDebugOverlay,
          isDark: isDark,
        ),

        SizedBox(height: Spacing.lg),
      ],
    );
  }

  Widget _buildToggleListTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: value
            ? BrandColors.forest.withValues(alpha: 0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark
                ? BrandColors.nightTextSecondary
                : BrandColors.driftwood,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeTrackColor: BrandColors.forest,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildParakeetModelCard(bool isDark, TranscriptionInitState initState) {
    final isReady = initState.isReady;
    final isInProgress = initState.isInProgress;
    final hasFailed = initState.hasFailed;

    // Determine status color
    Color statusColor;
    if (isReady) {
      statusColor = BrandColors.success;
    } else if (hasFailed) {
      statusColor = BrandColors.error;
    } else if (isInProgress) {
      statusColor = BrandColors.turquoise;
    } else {
      statusColor = BrandColors.warning;
    }

    // Determine status text
    String statusText;
    if (isReady) {
      statusText = 'READY';
    } else if (hasFailed) {
      statusText = 'FAILED';
    } else if (isInProgress) {
      statusText = 'LOADING';
    } else {
      statusText = 'PENDING';
    }

    // Determine icon
    IconData icon;
    if (isReady) {
      icon = Icons.check_circle;
    } else if (hasFailed) {
      icon = Icons.error;
    } else if (isInProgress) {
      icon = Icons.downloading;
    } else {
      icon = Icons.cloud_download;
    }

    return Container(
      padding: EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: statusColor, size: 28),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      initState.engineName ?? 'Parakeet v3',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: TypographyTokens.bodyLarge,
                        color: statusColor,
                      ),
                    ),
                    SizedBox(height: Spacing.xs),
                    Text(
                      isReady
                          ? 'Model ready • 25 languages supported'
                          : initState.userFriendlyStatus,
                      style: TextStyle(
                        fontSize: TypographyTokens.bodySmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: Spacing.md),
          const Divider(),
          SizedBox(height: Spacing.sm),
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'NVIDIA NeMo Parakeet multilingual ASR (~500MB)',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          // Show progress indicator during download/init
          if (isInProgress) ...[
            SizedBox(height: Spacing.md),
            _buildProgressIndicator(initState),
          ],

          // Show download button when not ready and not in progress
          if (!isReady && !isInProgress) ...[
            SizedBox(height: Spacing.md),

            // Show error message if failed
            if (hasFailed && initState.errorMessage != null) ...[
              Container(
                padding: EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: BrandColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: BrandColors.error, size: 20),
                    SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        initState.errorMessage!,
                        style: TextStyle(
                          fontSize: TypographyTokens.bodySmall,
                          color: BrandColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: Spacing.md),
            ],

            FilledButton.icon(
              onPressed: () {
                ref.read(transcriptionInitProvider.notifier).downloadAndInitialize();
              },
              icon: Icon(hasFailed ? Icons.refresh : Icons.download),
              label: Text(hasFailed ? 'Retry Download' : 'Download Model Now'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.turquoise,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
            SizedBox(height: Spacing.md),
            SettingsInfoBanner(
              message: hasFailed
                  ? 'Please check your internet connection and try again'
                  : 'Download now or models will be downloaded automatically on first use',
              color: hasFailed ? BrandColors.warning : BrandColors.turquoise,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(TranscriptionInitState state) {
    // Use indeterminate progress for iOS/macOS or when progress is -1
    final isIndeterminate = state.progress < 0;

    return Column(
      children: [
        if (isIndeterminate)
          const LinearProgressIndicator(
            backgroundColor: BrandColors.stone,
            valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
          )
        else
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: BrandColors.stone,
            valueColor: const AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
          ),
        SizedBox(height: Spacing.sm),
        Text(
          state.statusMessage.isNotEmpty
              ? state.statusMessage
              : state.userFriendlyStatus,
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: BrandColors.turquoise,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!isIndeterminate) ...[
          SizedBox(height: Spacing.xs),
          Text(
            '${(state.progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: BrandColors.turquoise,
            ),
          ),
        ],
      ],
    );
  }
}
