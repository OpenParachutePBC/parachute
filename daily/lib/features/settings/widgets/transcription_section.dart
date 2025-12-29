import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import 'package:parachute_daily/features/recorder/providers/transcription_init_provider.dart'
    show TranscriptionInitPhase, TranscriptionInitState, transcriptionInitProvider;

/// Simplified transcription settings section for Parachute Daily
class TranscriptionSection extends ConsumerWidget {
  const TranscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final transcriptionState = ref.watch(transcriptionInitProvider);

    return Card(
      color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transcription',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(context, isDark, transcriptionState),
            const SizedBox(height: 8),
            Text(
              'Voice recordings are transcribed locally using Parakeet/Whisper.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, bool isDark, TranscriptionInitState state) {
    final theme = Theme.of(context);

    IconData icon;
    Color iconColor;
    String statusText;

    switch (state.phase) {
      case TranscriptionInitPhase.unknown:
      case TranscriptionInitPhase.notDownloaded:
        icon = Icons.circle_outlined;
        iconColor = isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood;
        statusText = 'Not initialized';
      case TranscriptionInitPhase.checking:
      case TranscriptionInitPhase.downloading:
      case TranscriptionInitPhase.extracting:
      case TranscriptionInitPhase.initializing:
        icon = Icons.downloading;
        iconColor = BrandColors.turquoise;
        statusText = state.statusMessage.isNotEmpty ? state.statusMessage : 'Loading...';
      case TranscriptionInitPhase.ready:
        icon = Icons.check_circle;
        iconColor = BrandColors.forest;
        statusText = 'Ready (${state.engineName ?? 'Unknown'})';
      case TranscriptionInitPhase.failed:
        icon = Icons.error;
        iconColor = Colors.red;
        statusText = state.errorMessage ?? 'Error';
    }

    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            statusText,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
