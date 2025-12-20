import 'package:flutter/material.dart';
import 'package:app/features/recorder/models/recording.dart';

/// Visual indicator for background processing status
class ProcessingStatusIndicator extends StatelessWidget {
  final String label;
  final ProcessingStatus status;
  final bool compact;

  const ProcessingStatusIndicator({
    super.key,
    required this.label,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (status == ProcessingStatus.pending && compact) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIcon(),
        if (!compact) ...[
          const SizedBox(width: 8),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: compact ? 12 : 14,
              color: _statusColor(context),
              fontStyle: status == ProcessingStatus.processing
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIcon() {
    switch (status) {
      case ProcessingStatus.pending:
        return Icon(
          Icons.pending_outlined,
          size: compact ? 14 : 16,
          color: Colors.grey,
        );
      case ProcessingStatus.processing:
        return SizedBox(
          width: compact ? 14 : 16,
          height: compact ? 14 : 16,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      case ProcessingStatus.completed:
        return Icon(
          Icons.check_circle,
          size: compact ? 14 : 16,
          color: Colors.green,
        );
      case ProcessingStatus.failed:
        return Icon(Icons.error, size: compact ? 14 : 16, color: Colors.red);
    }
  }

  String get _statusText {
    switch (status) {
      case ProcessingStatus.pending:
        return '$label: Pending';
      case ProcessingStatus.processing:
        return '$label: Processing...';
      case ProcessingStatus.completed:
        return '$label: Done';
      case ProcessingStatus.failed:
        return '$label: Failed';
    }
  }

  Color _statusColor(BuildContext context) {
    switch (status) {
      case ProcessingStatus.pending:
        return Colors.grey;
      case ProcessingStatus.processing:
        return Theme.of(context).colorScheme.primary;
      case ProcessingStatus.completed:
        return Colors.green;
      case ProcessingStatus.failed:
        return Colors.red;
    }
  }
}

/// Shows all processing statuses for a recording
class ProcessingStatusBar extends StatelessWidget {
  final Recording recording;
  final bool compact;

  const ProcessingStatusBar({
    super.key,
    required this.recording,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnyProcessing =
        recording.transcriptionStatus != ProcessingStatus.pending ||
        recording.titleGenerationStatus != ProcessingStatus.pending ||
        recording.summaryStatus != ProcessingStatus.pending;

    if (!hasAnyProcessing && compact) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 8.0 : 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              Text(
                'Processing Status',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (!compact) const SizedBox(height: 8),
            ProcessingStatusIndicator(
              label: 'Transcription',
              status: recording.transcriptionStatus,
              compact: compact,
            ),
            if (!compact ||
                recording.titleGenerationStatus != ProcessingStatus.pending)
              const SizedBox(height: 6),
            if (!compact ||
                recording.titleGenerationStatus != ProcessingStatus.pending)
              ProcessingStatusIndicator(
                label: 'AI Title',
                status: recording.titleGenerationStatus,
                compact: compact,
              ),
            // Summary will be shown when implemented
            if (recording.summaryStatus != ProcessingStatus.pending) ...[
              const SizedBox(height: 6),
              ProcessingStatusIndicator(
                label: 'AI Summary',
                status: recording.summaryStatus,
                compact: compact,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
