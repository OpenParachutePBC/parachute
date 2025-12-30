import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/features/onboarding/screens/onboarding_flow.dart';
import './expandable_settings_section.dart';

/// Developer section with testing and debug options
class DeveloperSection extends ConsumerStatefulWidget {
  const DeveloperSection({super.key});

  @override
  ConsumerState<DeveloperSection> createState() => _DeveloperSectionState();
}

class _DeveloperSectionState extends ConsumerState<DeveloperSection> {
  bool _showOnboardingOnNextLaunch = false;
  bool _isLoading = true;

  static const String _showOnboardingKey = 'debug_show_onboarding_next_launch';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _showOnboardingOnNextLaunch = prefs.getBool(_showOnboardingKey) ?? false;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setShowOnboarding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showOnboardingKey, value);

    // If enabling, also clear the "has seen onboarding" flag
    if (value) {
      await prefs.remove('has_seen_onboarding_v1');
    }

    setState(() => _showOnboardingOnNextLaunch = value);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Onboarding will show on next app launch'
                : 'Onboarding reset cancelled',
          ),
          backgroundColor: value ? BrandColors.success : BrandColors.driftwood,
        ),
      );
    }
  }

  Future<void> _resetOnboardingNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Onboarding?'),
        content: const Text(
          'This will clear the onboarding completion flag. '
          'The onboarding flow will show on your next app launch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await OnboardingFlow.markOnboardingComplete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('has_seen_onboarding_v1');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Onboarding reset! Restart the app to see it.',
            ),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const SizedBox.shrink();
    }

    return ExpandableSettingsSection(
      title: 'Developer',
      subtitle: 'Testing and debug options',
      icon: Icons.code,
      accentColor: BrandColors.driftwood,
      children: [
        // Show onboarding toggle
        SettingsToggleRow(
          title: 'Show onboarding on next launch',
          subtitle: 'Reset onboarding to test the flow',
          icon: Icons.restart_alt,
          value: _showOnboardingOnNextLaunch,
          onChanged: _setShowOnboarding,
        ),

        SizedBox(height: Spacing.md),

        // Reset onboarding button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetOnboardingNow,
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Onboarding Now'),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
              side: BorderSide(
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.3)
                    : BrandColors.driftwood.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),

        SizedBox(height: Spacing.lg),

        // Info banner
        Container(
          padding: EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: BrandColors.turquoise.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: BrandColors.turquoise.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: BrandColors.turquoiseDeep,
                size: 16,
              ),
              SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'These options are for testing purposes. '
                  'Restart the app after making changes.',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightText
                        : BrandColors.turquoiseDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
