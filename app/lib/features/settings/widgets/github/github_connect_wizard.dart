import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/providers/github_auth_provider.dart';
import 'package:app/core/services/github/github_api_service.dart';
import 'package:app/features/settings/widgets/github/repository_selector.dart';
import 'package:app/core/providers/git_sync_provider.dart';

/// GitHub connection wizard - guides user through OAuth and repository selection
///
/// Flow:
/// 1. Connect GitHub account (OAuth)
/// 2. Select existing repository OR create new one
/// 3. Set up Git sync with selected repository
class GitHubConnectWizard extends ConsumerStatefulWidget {
  const GitHubConnectWizard({super.key});

  @override
  ConsumerState<GitHubConnectWizard> createState() =>
      _GitHubConnectWizardState();
}

class _GitHubConnectWizardState extends ConsumerState<GitHubConnectWizard> {
  int _currentStep = 0;
  GitHubRepository? _selectedRepository;
  bool _isSettingUp = false;

  @override
  void initState() {
    super.initState();
    // Skip to step 1 if already authenticated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gitHubAuth = ref.read(gitHubAuthProvider);
      if (gitHubAuth.isAuthenticated) {
        setState(() {
          _currentStep = 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gitHubAuth = ref.watch(gitHubAuthProvider);
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.hub, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Connect GitHub',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sync your Parachute vault across devices using GitHub',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            // Stepper
            Expanded(
              child: Stepper(
                currentStep: _currentStep,
                controlsBuilder: (context, details) {
                  return const SizedBox.shrink(); // Hide default controls
                },
                steps: [
                  // Step 1: Authenticate with GitHub
                  Step(
                    title: const Text('Connect GitHub Account'),
                    isActive: _currentStep >= 0,
                    state: gitHubAuth.isAuthenticated
                        ? StepState.complete
                        : StepState.indexed,
                    content: _buildAuthenticationStep(gitHubAuth),
                  ),

                  // Step 2: Select or create repository
                  Step(
                    title: const Text('Select Repository'),
                    isActive: _currentStep >= 1,
                    state: _selectedRepository != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _buildRepositorySelectionStep(gitHubAuth),
                  ),

                  // Step 3: Complete setup
                  Step(
                    title: const Text('Complete Setup'),
                    isActive: _currentStep >= 2,
                    content: _buildCompleteSetupStep(),
                  ),
                ],
              ),
            ),

            // Action buttons
            _buildActionButtons(gitHubAuth),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthenticationStep(GitHubAuthState gitHubAuth) {
    if (gitHubAuth.isAuthenticated && gitHubAuth.user != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(gitHubAuth.user!.avatarUrl),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gitHubAuth.user!.name ?? gitHubAuth.user!.login,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '@${gitHubAuth.user!.login}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Authorize Parachute to access your GitHub repositories.'),
        const SizedBox(height: 16),
        if (gitHubAuth.error != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gitHubAuth.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRepositorySelectionStep(GitHubAuthState gitHubAuth) {
    if (!gitHubAuth.isAuthenticated) {
      return const Text('Please connect your GitHub account first.');
    }

    return RepositorySelector(
      selectedRepository: _selectedRepository,
      onRepositorySelected: (repo) {
        setState(() {
          _selectedRepository = repo;
          _currentStep = 2; // Move to final step
        });
      },
    );
  }

  Widget _buildCompleteSetupStep() {
    if (_selectedRepository == null) {
      return const Text('Please select a repository first.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready to set up Git sync with:'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedRepository!.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedRepository!.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selectedRepository!.description!,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _selectedRepository!.private
                        ? Icons.lock_outline
                        : Icons.public,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _selectedRepository!.private ? 'Private' : 'Public',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Parachute will sync your captures and spaces to this repository.',
        ),
      ],
    );
  }

  Widget _buildActionButtons(GitHubAuthState gitHubAuth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_currentStep > 0)
          TextButton(
            onPressed: _isSettingUp
                ? null
                : () {
                    setState(() {
                      _currentStep--;
                    });
                  },
            child: const Text('Back'),
          ),
        const SizedBox(width: 8),
        if (_currentStep == 0 && !gitHubAuth.isAuthenticated)
          ElevatedButton.icon(
            onPressed: gitHubAuth.isAuthenticating ? null : _authenticateGitHub,
            icon: gitHubAuth.isAuthenticating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(
              gitHubAuth.isAuthenticating
                  ? 'Authenticating...'
                  : 'Connect GitHub',
            ),
          ),
        if (_currentStep == 0 && gitHubAuth.isAuthenticated)
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentStep = 1;
              });
            },
            child: const Text('Next'),
          ),
        if (_currentStep == 2 && _selectedRepository != null)
          ElevatedButton.icon(
            onPressed: _isSettingUp ? null : _completeSetup,
            icon: _isSettingUp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isSettingUp ? 'Setting up...' : 'Complete Setup'),
          ),
      ],
    );
  }

  Future<void> _authenticateGitHub() async {
    final success = await ref.read(gitHubAuthProvider.notifier).signIn();

    if (success && mounted) {
      setState(() {
        _currentStep = 1;
      });
    }
  }

  Future<void> _completeSetup() async {
    if (_selectedRepository == null) return;

    setState(() {
      _isSettingUp = true;
    });

    try {
      final gitHubAuth = ref.read(gitHubAuthProvider);
      final gitSync = ref.read(gitSyncProvider.notifier);

      // Set up Git sync with the selected repository
      // Use installation token (repository-scoped) for GitHub Apps
      // Falls back to access token for OAuth Apps
      final token = gitHubAuth.installationToken ?? gitHubAuth.accessToken!;

      debugPrint(
        '[GitHubWizard] Setting up Git sync with repository-scoped token',
      );
      final success = await gitSync.setupGitSync(
        repositoryUrl: _selectedRepository!.cloneUrl,
        githubToken: token,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Git sync enabled with ${_selectedRepository!.fullName}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return success
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to set up Git sync: ${ref.read(gitSyncProvider).lastError ?? "Unknown error"}',
            ),
            backgroundColor: Colors.red,
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
        setState(() {
          _isSettingUp = false;
        });
      }
    }
  }
}
