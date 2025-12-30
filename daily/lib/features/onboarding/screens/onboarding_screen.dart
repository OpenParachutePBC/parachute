import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:parachute_daily/core/theme/design_tokens.dart';
import 'package:parachute_daily/core/providers/file_system_provider.dart';
import 'package:parachute_daily/features/home/screens/home_screen.dart';

/// Onboarding screen for first-time users
///
/// Prompts the user to select their Parachute Daily folder location.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _isLoading = false;
  String? _selectedPath;
  String? _error;
  bool _needsManageStoragePermission = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _checkAndroidPermissions();
    }
  }

  Future<void> _checkAndroidPermissions() async {
    // On Android 11+ (SDK 30+), we need MANAGE_EXTERNAL_STORAGE for full file access
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 30) {
      final status = await Permission.manageExternalStorage.status;
      setState(() {
        _needsManageStoragePermission = !status.isGranted;
      });
    }
  }

  Future<void> _requestAndroidPermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;

    if (androidInfo.version.sdkInt >= 30) {
      // Android 11+ requires opening settings for MANAGE_EXTERNAL_STORAGE
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        // Open app settings for manual permission grant
        await openAppSettings();
      }
      // Recheck after returning from settings
      await _checkAndroidPermissions();
    } else {
      // Android 10 and below can use regular storage permission
      final status = await Permission.storage.request();
      if (status.isGranted) {
        setState(() {
          _needsManageStoragePermission = false;
        });
      }
    }
  }

  Future<void> _chooseDailyFolder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // On Android 11+, check if we need to request permission first
      if (Platform.isAndroid && _needsManageStoragePermission) {
        await _requestAndroidPermission();
        if (_needsManageStoragePermission) {
          setState(() {
            _error = 'Please grant "All files access" permission to choose a custom folder, or use the default location.';
            _isLoading = false;
          });
          return;
        }
      }

      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose Parachute Daily Folder',
      );

      if (result != null) {
        setState(() {
          _selectedPath = result;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error selecting folder: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _useDefaultFolder() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      await fileSystemService.initialize();
      await fileSystemService.markAsConfigured();
      _navigateToHome();
    } catch (e) {
      setState(() {
        _error = 'Error setting up folder: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedPath == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fileSystemService = ref.read(fileSystemServiceProvider);
      final success = await fileSystemService.setRootPath(
        _selectedPath!,
        migrateFiles: false,
      );

      if (success) {
        _navigateToHome();
      } else {
        setState(() {
          _error = 'Failed to set folder. Please try another location.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error setting up folder: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  String _getDisplayPath(String path) {
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && path.startsWith(home)) {
        return path.replaceFirst(home, '~');
      }
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 600;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isCompact ? 24 : 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon
                  Icon(
                    Icons.folder_special,
                    size: 80,
                    color: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Welcome to Parachute Daily',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'Choose where to store your journal entries. '
                    'This folder will contain your daily journals and audio recordings.',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Android permission banner
                  if (Platform.isAndroid && _needsManageStoragePermission) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BrandColors.warningLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: BrandColors.warning),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_off, color: BrandColors.warning, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Files Access Required',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: BrandColors.charcoal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'To choose a custom folder, grant "All files access" in Settings. Or use the default location below.',
                            style: TextStyle(
                              fontSize: 13,
                              color: BrandColors.driftwood,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _requestAndroidPermission,
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('Open Settings'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: BrandColors.warning,
                                side: BorderSide(color: BrandColors.warning),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Selected path display
                  if (_selectedPath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? BrandColors.nightSurfaceElevated : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            color: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getDisplayPath(_selectedPath!),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 20,
                              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                            ),
                            onPressed: () => setState(() => _selectedPath = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Error display
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Buttons
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else ...[
                    // Choose folder button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _chooseDailyFolder,
                        icon: const Icon(Icons.folder_open),
                        label: Text(_selectedPath == null ? 'Choose Folder' : 'Choose Different Folder'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirm button (shown when path is selected)
                    if (_selectedPath != null) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _confirmSelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Continue with This Folder'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Use default button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _useDefaultFolder,
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          Platform.isMacOS || Platform.isLinux
                              ? 'Use default (~/Parachute/Daily)'
                              : 'Use default location',
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Tip
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (isDark ? BrandColors.nightTurquoise : BrandColors.forest).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: isDark ? BrandColors.nightTurquoise : BrandColors.forest,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Tip: Choose a folder that syncs with your other devices (e.g., iCloud, Dropbox, Syncthing) to access your journals everywhere.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
