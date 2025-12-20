import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Bottom sheet for selecting a local recording to use with a doc agent
///
/// Shows recent recordings grouped by date, with search functionality.
class DocumentPicker extends ConsumerStatefulWidget {
  final String agentName;
  final void Function(Recording recording) onSelect;

  const DocumentPicker({
    super.key,
    required this.agentName,
    required this.onSelect,
  });

  /// Show the document picker as a bottom sheet
  static Future<Recording?> show(
    BuildContext context, {
    required String agentName,
  }) async {
    return showModalBottomSheet<Recording>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _DocumentPickerContent(
          agentName: agentName,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  ConsumerState<DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends ConsumerState<DocumentPicker> {
  @override
  Widget build(BuildContext context) {
    return _DocumentPickerContent(
      agentName: widget.agentName,
      onSelect: widget.onSelect,
    );
  }
}

class _DocumentPickerContent extends ConsumerStatefulWidget {
  final String agentName;
  final ScrollController? scrollController;
  final void Function(Recording recording)? onSelect;

  const _DocumentPickerContent({
    required this.agentName,
    this.scrollController,
    this.onSelect,
  });

  @override
  ConsumerState<_DocumentPickerContent> createState() =>
      _DocumentPickerContentState();
}

class _DocumentPickerContentState
    extends ConsumerState<_DocumentPickerContent> {
  List<Recording> _recordings = [];
  List<Recording> _filteredRecordings = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    final storageService = ref.read(storageServiceProvider);
    final recordings = await storageService.getRecordings();

    // Filter to only include recordings with transcripts
    final withTranscripts =
        recordings.where((r) => r.transcript.isNotEmpty).toList();

    if (mounted) {
      setState(() {
        _recordings = withTranscripts;
        _filteredRecordings = withTranscripts;
        _isLoading = false;
      });
    }
  }

  void _filterRecordings(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredRecordings = _recordings;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredRecordings = _recordings.where((r) {
          return r.title.toLowerCase().contains(lowerQuery) ||
              r.transcript.toLowerCase().contains(lowerQuery) ||
              r.context.toLowerCase().contains(lowerQuery);
        }).toList();
      }
    });
  }

  void _selectRecording(Recording recording) {
    if (widget.onSelect != null) {
      widget.onSelect!(recording);
    } else {
      Navigator.of(context).pop(recording);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      child: Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: Spacing.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.stone,
                borderRadius: Radii.pill,
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: isDark ? BrandColors.nightForest : BrandColors.forest,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Select a recording',
                        style: TextStyle(
                          fontSize: TypographyTokens.titleMedium,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? BrandColors.nightText
                              : BrandColors.charcoal,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  'Choose a recording to process with ${widget.agentName}',
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

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: _filterRecordings,
              decoration: InputDecoration(
                hintText: 'Search recordings...',
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _filterRecordings('');
                        },
                        icon: Icon(
                          Icons.clear,
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: Radii.pill,
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
              ),
            ),
          ),

          const SizedBox(height: Spacing.md),

          // Recording list
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: isDark
                          ? BrandColors.nightTurquoise
                          : BrandColors.turquoise,
                    ),
                  )
                : _filteredRecordings.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                        ),
                        itemCount: _filteredRecordings.length,
                        itemBuilder: (context, index) {
                          final recording = _filteredRecordings[index];
                          return _RecordingTile(
                            recording: recording,
                            onTap: () => _selectRecording(recording),
                            searchQuery: _searchQuery,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'No recordings found',
              style: TextStyle(
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Try a different search term',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                    : BrandColors.driftwood.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_off_outlined,
            size: 48,
            color: isDark
                ? BrandColors.nightTextSecondary
                : BrandColors.driftwood,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No recordings with transcripts',
            style: TextStyle(
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Record and transcribe some notes first',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark
                  ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                  : BrandColors.driftwood.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual recording tile in the picker
class _RecordingTile extends StatelessWidget {
  final Recording recording;
  final VoidCallback onTap;
  final String searchQuery;

  const _RecordingTile({
    required this.recording,
    required this.onTap,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.card,
          child: Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurfaceElevated
                  : BrandColors.cream,
              borderRadius: Radii.card,
              border: Border.all(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.stone.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and date row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        recording.title,
                        style: TextStyle(
                          fontSize: TypographyTokens.bodyMedium,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? BrandColors.nightText
                              : BrandColors.charcoal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      _formatDate(recording.timestamp),
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                            : BrandColors.driftwood,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: Spacing.xs),

                // Transcript preview
                Text(
                  recording.transcript,
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                    height: TypographyTokens.lineHeightNormal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                // Context tag if present
                if (recording.context.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm,
                      vertical: Spacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? BrandColors.nightForest.withValues(alpha: 0.2)
                          : BrandColors.forestMist,
                      borderRadius: Radii.badge,
                    ),
                    child: Text(
                      recording.context,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightForest
                            : BrandColors.forest,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
