import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/git_sync_provider.dart';

/// Compact Git sync status indicator for app bar
///
/// Shows:
/// - Sync status (synced, syncing, error, not configured)
/// - File counts when syncing
/// - Tap to manually trigger sync
class GitSyncStatusIndicator extends ConsumerWidget {
  const GitSyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gitSyncState = ref.watch(gitSyncProvider);

    // Don't show anything if Git sync is not enabled
    if (!gitSyncState.isEnabled) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: _buildIcon(gitSyncState),
      tooltip: _buildTooltip(gitSyncState),
      onPressed: () => _onTap(context, ref),
    );
  }

  Widget _buildIcon(GitSyncState state) {
    // Syncing - show animated spinner with file count
    if (state.isSyncing) {
      return Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          if (state.filesUploading > 0 || state.filesDownloading > 0)
            Positioned(
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${state.filesUploading + state.filesDownloading}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Error - show warning icon
    if (state.lastError != null) {
      return const Icon(Icons.cloud_off, color: Colors.red, size: 20);
    }

    // Synced - show check icon
    return const Icon(Icons.cloud_done, color: Colors.green, size: 20);
  }

  String _buildTooltip(GitSyncState state) {
    if (state.isSyncing) {
      final uploadText = state.filesUploading > 0
          ? '${state.filesUploading} uploading'
          : '';
      final downloadText = state.filesDownloading > 0
          ? '${state.filesDownloading} downloading'
          : '';
      final parts = [uploadText, downloadText].where((s) => s.isNotEmpty);

      if (parts.isEmpty) {
        return 'Syncing...';
      }
      return 'Syncing: ${parts.join(', ')}';
    }

    if (state.lastError != null) {
      return 'Sync error: ${state.lastError}';
    }

    if (state.lastSyncTime != null) {
      final time = _formatTime(state.lastSyncTime!);
      return 'Synced $time';
    }

    return 'Git sync enabled';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 30) {
      return 'just now';
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _onTap(BuildContext context, WidgetRef ref) async {
    debugPrint('[GitSyncIndicator] 🔵 Sync button tapped');
    final gitSync = ref.read(gitSyncProvider.notifier);
    final state = ref.read(gitSyncProvider);

    debugPrint(
      '[GitSyncIndicator] Current state: isSyncing=${state.isSyncing}, isEnabled=${state.isEnabled}',
    );

    // Don't allow manual sync if already syncing
    if (state.isSyncing) {
      debugPrint('[GitSyncIndicator] ⚠️  Already syncing, ignoring tap');
      return;
    }

    // Trigger manual sync
    debugPrint('[GitSyncIndicator] 📞 Calling gitSync.sync()...');
    final success = await gitSync.sync();
    debugPrint('[GitSyncIndicator] 📞 gitSync.sync() returned: $success');

    if (context.mounted) {
      final message = success
          ? '✅ Sync successful'
          : '❌ Sync failed${state.lastError != null ? ': ${state.lastError}' : ''}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
