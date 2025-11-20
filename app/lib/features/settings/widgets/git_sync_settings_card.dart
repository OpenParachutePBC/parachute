import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/providers/git_sync_provider.dart';
import 'package:app/core/providers/github_auth_provider.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/settings/widgets/github/github_connect_wizard.dart';

class GitSyncSettingsCard extends ConsumerStatefulWidget {
  const GitSyncSettingsCard({super.key});

  @override
  ConsumerState<GitSyncSettingsCard> createState() =>
      _GitSyncSettingsCardState();
}

class _GitSyncSettingsCardState extends ConsumerState<GitSyncSettingsCard> {
  bool _isSaving = false;

  Future<void> _disableGitSync() async {
    setState(() => _isSaving = true);

    try {
      final storageService = ref.read(storageServiceProvider);
      final gitSync = ref.read(gitSyncProvider.notifier);

      await gitSync.disable();
      await storageService.setGitSyncEnabled(false);
      await storageService.deleteGitHubToken();
      await storageService.deleteGitHubRepositoryUrl();

      // Also sign out from GitHub OAuth
      ref.read(gitHubAuthProvider.notifier).signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Git sync disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _syncNow() async {
    final gitSync = ref.read(gitSyncProvider.notifier);
    final success = await gitSync.sync();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✅ Sync successful' : '❌ Sync failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _showGitHubWizard() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const GitHubConnectWizard(),
    );

    // Wizard handles all state updates via providers, no need to reload
  }

  @override
  Widget build(BuildContext context) {
    final gitSyncState = ref.watch(gitSyncProvider);
    final githubAuthState = ref.watch(gitHubAuthProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_sync,
                  color: gitSyncState.isEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Git Sync (Multi-Device)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sync your captures and spaces across devices using GitHub',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),

            // Token revocation warning
            if (githubAuthState.needsReauth &&
                githubAuthState.error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        githubAuthState.error!,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Status indicator
            if (gitSyncState.isEnabled) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Git Sync Enabled',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (gitSyncState.currentBranch != null)
                            Text(
                              'Branch: ${gitSyncState.currentBranch}',
                              style: theme.textTheme.bodySmall,
                            ),
                          if (gitSyncState.lastSyncTime != null)
                            Text(
                              'Last sync: ${_formatTime(gitSyncState.lastSyncTime!)}',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons
            if (!gitSyncState.isEnabled) ...[
              // Connect with GitHub OAuth
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showGitHubWizard,
                  icon: const Icon(Icons.hub),
                  label: const Text('Connect with GitHub'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else ...[
              // Sync Now button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: gitSyncState.isSyncing ? null : _syncNow,
                  icon: gitSyncState.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    gitSyncState.isSyncing ? 'Syncing...' : 'Sync Now',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Change Repository and Disable buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _showGitHubWizard,
                      icon: const Icon(Icons.edit),
                      label: const Text('Change Repo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _disableGitSync,
                      icon: const Icon(Icons.cloud_off),
                      label: const Text('Disable'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Error message
            if (gitSyncState.lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gitSyncState.lastError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
