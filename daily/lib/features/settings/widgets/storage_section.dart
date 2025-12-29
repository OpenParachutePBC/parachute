import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import 'package:parachute_daily/core/providers/file_system_provider.dart';

/// Simplified storage settings section for Parachute Daily
class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final vaultPath = ref.watch(vaultPathProvider);

    return Card(
      color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            vaultPath.when(
              data: (path) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vault Location',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Journals are stored in ~/Parachute/Daily/',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }
}
