import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Modern recording tile matching RecordingDetailScreen design
/// Features: transcript preview, menu actions, status indicators
class RecordingTile extends ConsumerWidget {
  final Recording recording;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  const RecordingTile({
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: isProcessing
                ? Border.all(
                    color: Colors.orange.shade700.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: title, status, menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Play icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title and metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recording.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        _buildMetadataRow(context),
                      ],
                    ),
                  ),

                  // Menu button
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
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
                ],
              ),

              // Processing status indicator
              if (isProcessing) ...[
                const SizedBox(height: 12),
                _buildProcessingIndicator(context),
              ],

              // Transcript preview
              if (hasTranscript && !isProcessing) ...[
                const SizedBox(height: 12),
                _buildTranscriptPreview(context),
              ],

              // Context preview
              if (hasContext && !isProcessing) ...[
                const SizedBox(height: 8),
                _buildContextPreview(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          recording.timeAgo,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(width: 12),
        Icon(Icons.timer, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          recording.durationString,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(width: 12),
        Icon(
          recording.source == RecordingSource.omiDevice
              ? Icons.bluetooth
              : Icons.phone_android,
          size: 14,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          recording.source == RecordingSource.omiDevice ? 'Omi' : 'Phone',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildProcessingIndicator(BuildContext context) {
    String statusText = 'Processing';
    if (recording.transcriptionStatus == ProcessingStatus.processing) {
      statusText = 'Transcribing audio...';
    } else if (recording.titleGenerationStatus == ProcessingStatus.processing) {
      statusText = 'Generating title...';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptPreview(BuildContext context) {
    const maxLength = 120;
    final preview = recording.transcript.length > maxLength
        ? '${recording.transcript.substring(0, maxLength)}...'
        : recording.transcript;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.description_outlined,
            size: 16,
            color: Colors.grey.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preview,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.grey.shade800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextPreview(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.label_outline, size: 14, color: Colors.blue.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            recording.context,
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade700,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
