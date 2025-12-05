import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Recording card with Parachute brand styling
///
/// "Think naturally" - Soft, organic shapes with gentle visual hierarchy.
/// Features: Voice indicator, transcript preview, contextual badges
class RecordingCard extends ConsumerWidget {
  final Recording recording;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  const RecordingCard({
    super.key,
    required this.recording,
    this.onTap,
    this.onDeleted,
  });

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Recording'),
          content: const Text(
            'Are you sure you want to delete this recording? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: BrandColors.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && context.mounted) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteRecording(recording.id);
      if (success && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording deleted')));
        onDeleted?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTranscript = recording.transcript.isNotEmpty;
    final hasContext = recording.context.isNotEmpty;
    final isProcessing =
        recording.transcriptionStatus == ProcessingStatus.processing ||
        recording.titleGenerationStatus == ProcessingStatus.processing;
    final isOrphaned =
        recording.transcriptionStatus == ProcessingStatus.failed &&
        recording.transcript.isEmpty;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: isProcessing
            ? Border.all(
                color: SemanticColors.processingBorder,
                width: 1.5,
              )
            : isOrphaned
            ? Border.all(
                color: SemanticColors.errorBorder,
                width: 1.5,
              )
            : Border.all(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.5),
                width: 1,
              ),
        boxShadow: isProcessing || isOrphaned ? null : Elevation.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Padding(
            padding: Spacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Voice badge + menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVoiceNoteBadge(context),
                    const Spacer(),
                    _buildMenuButton(context, ref, isDark),
                  ],
                ),

                SizedBox(height: Spacing.sm),

                // Title
                Text(
                  recording.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                // Transcript preview (if available and not processing)
                if (hasTranscript && !isProcessing && !isOrphaned) ...[
                  SizedBox(height: Spacing.sm),
                  Text(
                    recording.transcript,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                      height: 1.5,
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Processing indicator
                if (isProcessing) ...[
                  SizedBox(height: Spacing.sm),
                  _buildProcessingIndicator(context),
                ],

                // Orphaned file warning
                if (isOrphaned) ...[
                  SizedBox(height: Spacing.sm),
                  _buildOrphanedWarning(context),
                ],

                // Context tag (if available)
                if (hasContext && !isProcessing) ...[
                  SizedBox(height: Spacing.sm),
                  _buildContextBadge(context),
                ],

                SizedBox(height: Spacing.md),

                // Footer: metadata
                _buildFooter(context, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, WidgetRef ref, bool isDark) {
    return SizedBox(
      width: 32,
      height: 32,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_horiz,
          size: 18,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  color: BrandColors.error,
                  size: 18,
                ),
                SizedBox(width: Spacing.sm),
                Text(
                  'Delete',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BrandColors.error,
                  ),
                ),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'delete') {
            _confirmDelete(context, ref);
          }
        },
      ),
    );
  }

  Widget _buildVoiceNoteBadge(BuildContext context) {
    final isOmi = recording.source == RecordingSource.omiDevice;

    final backgroundColor = isOmi
        ? SemanticColors.omiBadgeBackground
        : SemanticColors.voiceBadgeBackground;
    final foregroundColor = isOmi
        ? SemanticColors.omiBadgeForeground
        : SemanticColors.voiceBadgeForeground;
    final borderColor = isOmi
        ? SemanticColors.omiBadgeBorder
        : SemanticColors.voiceBadgeBorder;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOmi ? Icons.bluetooth : Icons.mic,
            size: 12,
            color: foregroundColor,
          ),
          SizedBox(width: Spacing.xs),
          Text(
            isOmi ? 'Omi' : 'Voice',
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator(BuildContext context) {
    String statusText = 'Processing...';
    if (recording.transcriptionStatus == ProcessingStatus.processing) {
      statusText = 'Transcribing...';
    } else if (recording.titleGenerationStatus == ProcessingStatus.processing) {
      statusText = 'Generating title...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: SemanticColors.processingBackground,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                SemanticColors.processingForeground,
              ),
            ),
          ),
          SizedBox(width: Spacing.sm),
          Text(
            statusText,
            style: TextStyle(
              fontSize: TypographyTokens.labelSmall,
              color: SemanticColors.processingForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrphanedWarning(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: SemanticColors.errorBackground,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: SemanticColors.errorBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: SemanticColors.errorForeground,
          ),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Transcription failed. Tap to retry.',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: SemanticColors.errorForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: SemanticColors.contextBadgeBackground,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: SemanticColors.contextBadgeBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.label_outline,
            size: 12,
            color: SemanticColors.contextBadgeForeground,
          ),
          SizedBox(width: Spacing.xs),
          Flexible(
            child: Text(
              recording.context,
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: SemanticColors.contextBadgeForeground,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    final secondaryColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

    return Row(
      children: [
        Icon(
          Icons.access_time,
          size: 12,
          color: secondaryColor,
        ),
        SizedBox(width: Spacing.xs),
        Text(
          recording.timeAgo,
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            color: secondaryColor,
          ),
        ),
        SizedBox(width: Spacing.md),
        Icon(
          Icons.timer_outlined,
          size: 12,
          color: secondaryColor,
        ),
        SizedBox(width: Spacing.xs),
        Text(
          recording.durationString,
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            color: secondaryColor,
          ),
        ),
      ],
    );
  }
}
