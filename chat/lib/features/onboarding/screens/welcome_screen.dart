import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Welcome screen shown on first app launch
class WelcomeScreen extends ConsumerWidget {
  final VoidCallback onComplete;

  const WelcomeScreen({super.key, required this.onComplete});

  static const String _hasSeenWelcomeKey = 'has_seen_welcome';

  /// Check if user has seen the welcome screen
  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenWelcomeKey) ?? false;
  }

  /// Mark welcome screen as seen
  static Future<void> markWelcomeAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenWelcomeKey, true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),

              // App icon/logo
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.mic,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Welcome title
              Text(
                'Welcome to Parachute',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Subtitle
              Text(
                'Your simple, privacy-first voice recorder',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // Feature highlights
              _buildFeatureItem(
                context,
                icon: Icons.mic,
                title: 'Record Your Thoughts',
                description:
                    'Quick voice recordings with local or cloud transcription',
              ),

              const SizedBox(height: 24),

              _buildFeatureItem(
                context,
                icon: Icons.folder,
                title: 'Your Files, Your Way',
                description:
                    'All recordings stored locally in ~/Parachute/ - perfect for Obsidian users',
              ),

              const SizedBox(height: 24),

              _buildFeatureItem(
                context,
                icon: Icons.tune,
                title: 'Optional Advanced Features',
                description:
                    'Enable AI chat or Omi device support in Settings when you\'re ready',
              ),

              const Spacer(),

              // Get started button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await markWelcomeAsSeen();
                    onComplete();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Privacy note
              Text(
                'Privacy first: Your recordings stay on your device unless you choose to enable cloud features.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 24,
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
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
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
