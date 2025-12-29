import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:parachute_chat/core/theme/design_tokens.dart';
import 'package:parachute_chat/core/services/logging_service.dart';
import './settings_section_header.dart';

/// Privacy & Debugging settings section
class PrivacySection extends ConsumerStatefulWidget {
  const PrivacySection({super.key});

  @override
  ConsumerState<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends ConsumerState<PrivacySection> {
  bool _crashReportingEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _crashReportingEnabled = logger.isCrashReportingEnabled;
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setCrashReportingEnabled(bool enabled) async {
    await logger.setCrashReportingEnabled(enabled);
    setState(() => _crashReportingEnabled = enabled);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Crash reporting enabled - helps improve Parachute!'
                : 'Crash reporting disabled',
          ),
          backgroundColor: enabled ? BrandColors.success : BrandColors.warning,
        ),
      );
    }
  }

  Future<void> _viewLogFiles() async {
    final logPaths = await logger.getLogFilePaths();
    if (logPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No log files found')),
        );
      }
      return;
    }

    final latestLog = logPaths.first;
    final logDir = latestLog.substring(0, latestLog.lastIndexOf('/'));
    final uri = Uri.file(logDir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Privacy & Debugging',
          subtitle: 'Help improve Parachute by sharing crash reports',
          icon: Icons.shield_outlined,
        ),
        SizedBox(height: Spacing.lg),

        // Crash Reporting Toggle
        Container(
          padding: EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: _crashReportingEnabled
                ? BrandColors.success.withValues(alpha: 0.1)
                : (isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.stone.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: _crashReportingEnabled
                  ? BrandColors.success
                  : (isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood)
                      .withValues(alpha: 0.3),
              width: _crashReportingEnabled ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _crashReportingEnabled
                        ? Icons.bug_report
                        : Icons.bug_report_outlined,
                    color: _crashReportingEnabled
                        ? BrandColors.success
                        : (isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood),
                    size: 32,
                  ),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crash Reporting',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: TypographyTokens.bodyLarge,
                            color: isDark
                                ? BrandColors.nightText
                                : BrandColors.charcoal,
                          ),
                        ),
                        SizedBox(height: Spacing.xs),
                        Text(
                          _crashReportingEnabled
                              ? 'Automatically send crash reports to help fix bugs'
                              : 'Crash reports are not sent',
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
                  Switch(
                    value: _crashReportingEnabled,
                    onChanged: _setCrashReportingEnabled,
                    activeTrackColor: BrandColors.success,
                  ),
                ],
              ),
              SizedBox(height: Spacing.md),
              SettingsInfoBanner(
                message:
                    'Only crash data and logs are sent. No personal data, recordings, or transcripts are ever shared.',
                icon: Icons.privacy_tip_outlined,
                color: BrandColors.turquoise,
              ),
            ],
          ),
        ),
        SizedBox(height: Spacing.lg),

        // View Logs Button (desktop only)
        if (isDesktop) ...[
          OutlinedButton.icon(
            onPressed: _viewLogFiles,
            icon: const Icon(Icons.folder_open),
            label: const Text('View Local Log Files'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          SizedBox(height: Spacing.sm),
          Center(
            child: Text(
              'Log files are stored locally and rotated automatically',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
          ),
        ],
        SizedBox(height: Spacing.lg),
      ],
    );
  }
}
