import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/services/parakeet_service.dart' as parakeet;
import 'package:app/services/sherpa_onnx_service.dart' as sherpa;
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
  bool _autoPauseRecording = false;
  bool _audioDebugOverlay = false;
  dynamic _parakeetModelInfo;
  bool _isDownloadingParakeet = false;
  double _parakeetDownloadProgress = 0.0;
  String _parakeetDownloadStatus = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storageService = ref.read(storageServiceProvider);

    _autoTranscribe = await storageService.getAutoTranscribe();
    _autoPauseRecording = await storageService.getAutoPauseRecording();
    _audioDebugOverlay = await storageService.getAudioDebugOverlay();
    await _loadParakeetModelInfo();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadParakeetModelInfo() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final parakeetService = parakeet.ParakeetService();
        final modelsDownloaded = await parakeetService.areModelsDownloaded();

        if (modelsDownloaded) {
          _parakeetModelInfo = await parakeetService.getModelInfo();
          _parakeetModelInfo ??= parakeet.ModelInfo(
            version: 'v3',
            languageCount: 25,
            isInitialized: true,
          );
        } else {
          _parakeetModelInfo = null;
        }
      } else if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
        final sherpaService = sherpa.SherpaOnnxService();
        _parakeetModelInfo = await sherpaService.getModelInfo();
      }
    } catch (e) {
      debugPrint('[Settings] Failed to load Parakeet model info: $e');
      _parakeetModelInfo = null;
    }
  }

  Future<void> _downloadParakeetModel() async {
    if (_isDownloadingParakeet) return;

    setState(() {
      _isDownloadingParakeet = true;
      _parakeetDownloadProgress = 0.0;
      _parakeetDownloadStatus = 'Starting download...';
    });

    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final parakeetService = parakeet.ParakeetService();
        await parakeetService.initialize(version: 'v3');
        _parakeetModelInfo = await parakeetService.getModelInfo();
      } else if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
        final sherpaService = sherpa.SherpaOnnxService();
        await sherpaService.initialize(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _parakeetDownloadProgress = progress);
            }
          },
          onStatus: (status) {
            if (mounted) {
              setState(() => _parakeetDownloadStatus = status);
            }
          },
        );
        _parakeetModelInfo = await sherpaService.getModelInfo();
      }

      if (mounted) {
        setState(() {
          _isDownloadingParakeet = false;
          _parakeetDownloadProgress = 1.0;
          _parakeetDownloadStatus = 'Download complete!';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Parakeet model downloaded successfully!'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingParakeet = false;
          _parakeetDownloadProgress = 0.0;
          _parakeetDownloadStatus = 'Download failed';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download Parakeet model: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _setAutoTranscribe(bool enabled) async {
    await ref.read(storageServiceProvider).setAutoTranscribe(enabled);
    setState(() => _autoTranscribe = enabled);
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
        _buildParakeetModelCard(isDark),
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

  Widget _buildParakeetModelCard(bool isDark) {
    final isReady = _parakeetModelInfo?.isInitialized ?? false;
    final version = _parakeetModelInfo?.version ?? 'v3';
    final languageCount = _parakeetModelInfo?.languageCount ?? 600;
    final statusColor = isReady ? BrandColors.success : BrandColors.warning;

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
              Icon(
                isReady ? Icons.check_circle : Icons.downloading,
                color: statusColor,
                size: 28,
              ),
              SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parakeet $version',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: TypographyTokens.bodyLarge,
                        color: statusColor,
                      ),
                    ),
                    SizedBox(height: Spacing.xs),
                    Text(
                      isReady
                          ? 'Model ready • $languageCount languages'
                          : 'Model downloading or not initialized',
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
                  isReady ? 'READY' : 'PENDING',
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
                  'NVIDIA NeMo Parakeet multilingual ASR',
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
          if (!isReady) ...[
            SizedBox(height: Spacing.md),
            if (_isDownloadingParakeet) ...[
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _parakeetDownloadProgress,
                    backgroundColor: BrandColors.stone,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
                  ),
                  SizedBox(height: Spacing.sm),
                  Text(
                    _parakeetDownloadStatus,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: BrandColors.turquoise,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: Spacing.xs),
                  Text(
                    'Progress: ${(_parakeetDownloadProgress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall,
                      color: BrandColors.turquoise,
                    ),
                  ),
                ],
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: _downloadParakeetModel,
                icon: const Icon(Icons.download),
                label: const Text('Download Model Now'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.turquoise,
                  minimumSize: const Size(double.infinity, 44),
                ),
              ),
              SizedBox(height: Spacing.md),
              SettingsInfoBanner(
                message:
                    'Download now or models will be downloaded automatically on first use',
                color: BrandColors.turquoise,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
