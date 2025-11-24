import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';

class WelcomeStep extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const WelcomeStep({super.key, required this.onNext, required this.onSkip});

  @override
  ConsumerState<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends ConsumerState<WelcomeStep> {
  String _folderLocation = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadFolderLocation();
  }

  Future<void> _loadFolderLocation() async {
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final location = await fileSystemService.getRootPathDisplay();
    if (mounted) {
      setState(() => _folderLocation = location);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            // App icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.mic,
                size: 50,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Welcome to Parachute',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            Text(
              'Your privacy-first voice recorder with AI superpowers',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Note system compatibility badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.purple.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.purple[700]),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Works with Obsidian, Logseq, and other markdown vaults',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.purple[900],
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Feature highlights
            _buildFeature(
              context,
              icon: Icons.folder_open,
              title: 'One Folder, All Your Data',
              description:
                  'Everything lives in $_folderLocation - open, portable, and yours',
            ),

            const SizedBox(height: 20),

            _buildFeature(
              context,
              icon: Icons.mic,
              title: 'Voice Recording',
              description: 'Quick captures with local or Omi device recording',
            ),

            const SizedBox(height: 20),

            _buildFeature(
              context,
              icon: Icons.transcribe,
              title: 'Auto-Transcription',
              description: 'Local Whisper models or cloud-based transcription',
            ),

            const SizedBox(height: 20),

            _buildFeature(
              context,
              icon: Icons.sync_disabled,
              title: 'Sync How You Want',
              description:
                  'Use iCloud, Dropbox, Syncthing, or any sync tool you trust',
            ),

            const SizedBox(height: 48),

            // Continue button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.onNext,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Get Started',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Skip button
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('Skip setup'),
            ),

            const SizedBox(height: 8),

            // Note about changing folder location
            Text(
              'You can change the folder location later in Settings',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
