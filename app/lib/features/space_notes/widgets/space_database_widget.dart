import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/api_provider.dart';
import 'package:app/core/models/space_database_stats.dart';
import '../screens/table_viewer_screen.dart';

final spaceDatabaseStatsProvider =
    FutureProvider.family<SpaceDatabaseStats, String>((ref, spaceId) async {
      final apiClient = ref.read(apiClientProvider);
      return apiClient.getSpaceDatabaseStats(spaceId);
    });

class SpaceDatabaseWidget extends ConsumerWidget {
  final String spaceId;

  const SpaceDatabaseWidget({super.key, required this.spaceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(spaceDatabaseStatsProvider(spaceId));

    return statsAsync.when(
      data: (stats) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(spaceDatabaseStatsProvider(spaceId));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOverviewCard(context, stats),
              const SizedBox(height: 16),
              _buildMetadataCard(context, stats),
              const SizedBox(height: 16),
              _buildTablesCard(context, stats),
              const SizedBox(height: 16),
              _buildTagsCard(context, stats),
              const SizedBox(height: 16),
              _buildRecentNotesCard(context, stats),
            ],
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error loading database stats'),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context, SpaceDatabaseStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Database Overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Total Notes',
              stats.totalNotes.toString(),
              Icons.note,
            ),
            _buildStatRow(
              context,
              'Unique Tags',
              stats.allTags.length.toString(),
              Icons.label,
            ),
            _buildStatRow(
              context,
              'Schema Version',
              stats.schemaVersion,
              Icons.numbers,
            ),
            _buildStatRow(
              context,
              'Created',
              stats.createdAtFormatted,
              Icons.calendar_today,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataCard(BuildContext context, SpaceDatabaseStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (stats.metadata.isEmpty)
              const Text('No metadata')
            else
              ...stats.metadata.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablesCard(BuildContext context, SpaceDatabaseStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Database Tables',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (stats.tables.isEmpty)
              const Text('No tables')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stats.tables
                    .map(
                      (table) => ActionChip(
                        label: Text(table),
                        avatar: const Icon(Icons.table_rows, size: 16),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TableViewerScreen(
                                spaceId: spaceId,
                                tableName: table,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsCard(BuildContext context, SpaceDatabaseStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.label_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'All Tags',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (stats.allTags.isEmpty)
              const Text('No tags')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stats.allTags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentNotesCard(BuildContext context, SpaceDatabaseStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Notes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (stats.recentNotes.isEmpty)
              const Text('No recent notes')
            else
              ...stats.recentNotes.map(
                (note) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.filename,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      if (note.context.isNotEmpty)
                        Text(
                          note.context,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            note.linkedTimeAgo,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                          ),
                          if (note.tags.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 4,
                              children: note.tags
                                  .take(3)
                                  .map(
                                    (tag) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tag,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(fontSize: 10),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 24),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
