import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/feature_flags_provider.dart';
import 'features/spaces/screens/space_list_screen.dart';
import 'features/recorder/screens/home_screen.dart' as recorder;
import 'features/recorder/providers/service_providers.dart';
import 'features/recorder/providers/model_download_provider.dart';
import 'features/recorder/services/transcription_service_adapter.dart';
import 'features/files/screens/file_browser_screen.dart';
import 'features/onboarding/screens/onboarding_flow.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file (optional, fails silently if not found)
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('[Main] ✅ Loaded .env file');
  } catch (e) {
    debugPrint(
      '[Main] ⚠️  No .env file found (this is ok, using --dart-define or defaults)',
    );
  }

  // Disable verbose FlutterBluePlus logs (reduces spam from onCharacteristicChanged)
  FlutterBluePlus.setLogLevel(LogLevel.none, color: false);

  // Initialize Opus codec for audio decoding (required for Omi device recordings)
  try {
    debugPrint('[Main] Loading Opus library...');

    // opus_flutter doesn't support macOS, so we need to manually load the library
    if (Platform.isMacOS) {
      debugPrint('[Main] Platform: macOS - loading Opus library manually');

      // Try to load from bundled library first, then fall back to system paths
      final possiblePaths = [
        '@executable_path/../Frameworks/libopus.dylib', // Bundled with app
        'libopus.dylib', // Relative to app
      ];

      DynamicLibrary? loadedLib;
      for (final path in possiblePaths) {
        try {
          debugPrint('[Main] Trying to load Opus from: $path');
          loadedLib = DynamicLibrary.open(path);
          debugPrint('[Main] ✅ Successfully loaded Opus from: $path');
          break;
        } catch (e) {
          debugPrint('[Main] Failed to load from $path: $e');
        }
      }

      if (loadedLib == null) {
        throw Exception(
          'Could not find libopus.dylib in app bundle. The library should be bundled with the app.',
        );
      }

      debugPrint('[Main] Initializing Opus codec...');
      // Cast to dynamic to work around static analysis issue with conditional exports
      opus_dart.initOpus(loadedLib as dynamic);
      debugPrint('[Main] ✅ Opus codec initialized successfully');
    } else {
      // Use opus_flutter for supported platforms (Android, iOS, Windows)
      final library = await opus_flutter.load();
      debugPrint('[Main] Opus library loaded via opus_flutter: $library');

      debugPrint('[Main] Initializing Opus codec...');
      opus_dart.initOpus(library);
      debugPrint('[Main] ✅ Opus codec initialized successfully');
    }

    // Verify initialization by getting version
    try {
      final version = opus_dart.getOpusVersion();
      debugPrint('[Main] Opus version: $version');
    } catch (e) {
      debugPrint('[Main] ⚠️  Warning: Could not get Opus version: $e');
    }
  } catch (e, stackTrace) {
    debugPrint('[Main] ❌ Failed to initialize Opus codec: $e');
    debugPrint('[Main] Stack trace: $stackTrace');
    // Continue anyway - only affects Omi device recordings with Opus codec
  }

  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log the error
    FlutterError.presentError(details);

    // In production, you could send to crash reporting service
    if (kReleaseMode) {
      // TODO: Send to crash reporting (Firebase Crashlytics, Sentry, etc.)
      debugPrint('Error caught in release mode: ${details.exception}');
    }
  };

  // Catch errors not caught by Flutter
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack trace: $stack');

    // In production, send to crash reporting
    if (kReleaseMode) {
      // TODO: Send to crash reporting
    }

    return true; // Prevents error from propagating
  };

  runApp(const ProviderScope(child: ParachuteApp()));
}

class ParachuteApp extends StatelessWidget {
  const ParachuteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parachute',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int? _selectedIndex; // Will be set to recorder index on first build
  bool _hasSeenWelcome = true; // Default to true, will be updated
  bool _isCheckingWelcome = true;

  @override
  void initState() {
    super.initState();
    _checkWelcomeScreen();
    _setupTranscriptionCallbacks();
  }

  /// Set up global callbacks for lazy transcription initialization
  /// Models will download when first transcription is attempted
  void _setupTranscriptionCallbacks() {
    final downloadNotifier = ref.read(modelDownloadProvider.notifier);

    TranscriptionServiceAdapter.setGlobalProgressCallbacks(
      onProgress: (progress) {
        // Update UI with progress
        downloadNotifier.updateProgress(
          progress,
          downloadNotifier.state.status,
        );
      },
      onStatus: (status) {
        // Update UI with status
        debugPrint('[Main] $status');
        downloadNotifier.updateProgress(
          downloadNotifier.state.progress,
          status,
        );

        // Start download indicator on first meaningful status
        if (status.contains('Downloading') || status.contains('Initializing')) {
          downloadNotifier.startDownload();
        }

        // Complete when done
        if (status == 'Ready') {
          downloadNotifier.complete();
        }
      },
    );
  }

  Future<void> _checkWelcomeScreen() async {
    final hasSeenWelcome = await OnboardingFlow.hasCompletedOnboarding();
    if (mounted) {
      setState(() {
        _hasSeenWelcome = hasSeenWelcome;
        _isCheckingWelcome = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking welcome status
    if (_isCheckingWelcome) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show onboarding flow if not completed before
    if (!_hasSeenWelcome) {
      return OnboardingFlow(
        onComplete: () {
          setState(() {
            _hasSeenWelcome = true;
          });
        },
      );
    }

    final aiChatEnabledAsync = ref.watch(aiChatEnabledNotifierProvider);

    return aiChatEnabledAsync.when(
      data: (aiChatEnabled) {
        // Build screens list based on feature flags
        final screens = <Widget>[];
        final navItems = <BottomNavigationBarItem>[];

        int recorderIndex = 0;
        int filesIndex = 1;

        // Add Spaces tab if enabled (local-first knowledge management)
        if (aiChatEnabled) {
          screens.add(const SpaceListScreen());
          navItems.add(
            const BottomNavigationBarItem(
              icon: Icon(Icons.space_dashboard_outlined),
              activeIcon: Icon(Icons.space_dashboard),
              label: 'Spaces',
              tooltip: 'Knowledge Spaces',
            ),
          );
          recorderIndex = 1;
          filesIndex = 2;
        }

        // Always show Recorder tab (core feature)
        screens.add(const recorder.HomeScreen());
        navItems.add(
          const BottomNavigationBarItem(
            icon: Icon(Icons.mic_none),
            activeIcon: Icon(Icons.mic),
            label: 'Recorder',
            tooltip: 'Voice Recorder',
          ),
        );

        // Always show Files tab
        screens.add(const FileBrowserScreen());
        navItems.add(
          const BottomNavigationBarItem(
            icon: Icon(Icons.folder_outlined),
            activeIcon: Icon(Icons.folder),
            label: 'Files',
            tooltip: 'Browse Files',
          ),
        );

        // Initialize to recorder on first build, or ensure selected index is valid
        if (_selectedIndex == null || _selectedIndex! >= screens.length) {
          _selectedIndex = recorderIndex; // Default to recorder
        }

        return Scaffold(
          body: IndexedStack(index: _selectedIndex!, children: screens),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex!,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: navItems,
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) {
        // On error, show a minimal interface with just Recorder
        // Default to Recorder (index 0) on error
        final currentIndex = (_selectedIndex ?? 0).clamp(0, 1);

        return Scaffold(
          body: IndexedStack(
            index: currentIndex,
            children: const [recorder.HomeScreen(), FileBrowserScreen()],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.mic_none),
                activeIcon: Icon(Icons.mic),
                label: 'Recorder',
                tooltip: 'Voice Recorder',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder_outlined),
                activeIcon: Icon(Icons.folder),
                label: 'Files',
                tooltip: 'Browse Files',
              ),
            ],
          ),
        );
      },
    );
  }
}
