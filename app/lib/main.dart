import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue_plus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:git2dart/git2dart.dart' as git2dart;
import 'package:git2dart_binaries/git2dart_binaries.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/feature_flags_provider.dart';
import 'core/services/logging_service.dart';
import 'features/spaces/screens/space_list_screen.dart';
import 'features/recorder/screens/home_screen.dart' as recorder;
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

  // Initialize logging service with Sentry (only in release mode)
  // This keeps debug output clean and avoids Sentry SDK warnings during development
  final sentryDsn = kReleaseMode ? dotenv.env['SENTRY_DSN'] : null;
  await logger.initialize(
    sentryDsn: sentryDsn,
    environment: kReleaseMode ? 'production' : 'development',
    release: 'parachute@1.0.0', // Update this with your version
  );

  // Initialize Git SSL certificates for Android
  if (Platform.isAndroid) {
    try {
      logger.info('Main', 'Initializing Android SSL certificates for Git...');

      // 1. Initialize libgit2 FIRST
      final version = git2dart.Libgit2.version;
      logger.info('Main', 'libgit2 version: $version');

      // 2. NOW initialize SSL
      final certPath = await AndroidSSLHelper.initialize();
      git2dart.Libgit2.setSSLCertLocations(file: certPath);
      logger.info('Main', 'Git SSL certificates configured: $certPath');
    } catch (e, stackTrace) {
      logger.error(
        'Main',
        'Failed to initialize Git SSL',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  // Disable verbose FlutterBluePlus logs (reduces spam from onCharacteristicChanged)
  flutter_blue_plus.FlutterBluePlus.setLogLevel(
    flutter_blue_plus.LogLevel.none,
    color: false,
  );

  // Initialize Flutter Gemma for on-device AI title generation
  try {
    logger.info('Main', 'Initializing FlutterGemma...');
    await FlutterGemma.initialize();
    logger.info('Main', 'FlutterGemma initialized successfully');
  } catch (e, stackTrace) {
    logger.error(
      'Main',
      'Failed to initialize FlutterGemma',
      error: e,
      stackTrace: stackTrace,
    );
    // Continue anyway - only affects title generation feature
  }

  // Initialize Opus codec for audio decoding (required for Omi device recordings)
  try {
    logger.info('Main', 'Loading Opus library...');

    // opus_flutter doesn't support macOS, so we need to manually load the library
    if (Platform.isMacOS) {
      logger.debug('Main', 'Platform: macOS - loading Opus library manually');

      // Try to load from bundled library first, then fall back to other paths
      // During development, the library may be in the project's macos/Frameworks folder
      final possiblePaths = [
        '@executable_path/../Frameworks/libopus.dylib', // Bundled with app (release)
        'libopus.dylib', // Relative to app
        // Homebrew paths (try both symlink and versioned file)
        '/opt/homebrew/opt/opus/lib/libopus.0.dylib', // Homebrew keg-only (versioned)
        '/opt/homebrew/opt/opus/lib/libopus.dylib', // Homebrew keg-only (symlink)
        '/opt/homebrew/lib/libopus.0.dylib', // Apple Silicon Homebrew (versioned)
        '/opt/homebrew/lib/libopus.dylib', // Apple Silicon Homebrew (symlink)
        '/usr/local/opt/opus/lib/libopus.0.dylib', // Intel Homebrew keg-only (versioned)
        '/usr/local/opt/opus/lib/libopus.dylib', // Intel Homebrew keg-only (symlink)
        '/usr/local/lib/libopus.0.dylib', // Intel Homebrew (versioned)
        '/usr/local/lib/libopus.dylib', // Intel Homebrew (symlink)
      ];

      DynamicLibrary? loadedLib;
      for (final path in possiblePaths) {
        try {
          logger.debug('Main', 'Trying to load Opus from: $path');
          loadedLib = DynamicLibrary.open(path);
          logger.info('Main', 'Successfully loaded Opus from: $path');
          break;
        } catch (e) {
          logger.debug('Main', 'Failed to load from $path: $e');
        }
      }

      if (loadedLib == null) {
        throw Exception(
          'Could not find libopus.dylib in app bundle. The library should be bundled with the app.',
        );
      }

      logger.debug('Main', 'Initializing Opus codec...');
      // Cast to dynamic to work around static analysis issue with conditional exports
      opus_dart.initOpus(loadedLib as dynamic);
      logger.info('Main', 'Opus codec initialized successfully');
    } else {
      // Use opus_flutter for supported platforms (Android, iOS, Windows)
      final library = await opus_flutter.load();
      logger.debug('Main', 'Opus library loaded via opus_flutter: $library');

      logger.debug('Main', 'Initializing Opus codec...');
      opus_dart.initOpus(library);
      logger.info('Main', 'Opus codec initialized successfully');
    }

    // Verify initialization by getting version
    try {
      final version = opus_dart.getOpusVersion();
      logger.debug('Main', 'Opus version: $version');
    } catch (e) {
      logger.warning('Main', 'Could not get Opus version', error: e);
    }
  } catch (e, stackTrace) {
    logger.error(
      'Main',
      'Failed to initialize Opus codec',
      error: e,
      stackTrace: stackTrace,
    );
    // Continue anyway - only affects Omi device recordings with Opus codec
  }

  // Set up global error handling with Sentry integration
  FlutterError.onError = (FlutterErrorDetails details) {
    // Log the error
    FlutterError.presentError(details);

    // Send to logging service (which sends to Sentry if enabled)
    logger.captureException(
      details.exception,
      stackTrace: details.stack,
      tag: 'FlutterError',
      extras: {
        'library': details.library ?? 'unknown',
        'context': details.context?.toString() ?? 'unknown',
      },
    );
  };

  // Catch errors not caught by Flutter
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.captureException(
      error,
      stackTrace: stack,
      tag: 'PlatformDispatcher',
    );
    return true; // Prevents error from propagating
  };

  // Run the app
  // Note: runZonedGuarded removed to avoid zone mismatch with Flutter bindings
  // Error handling is already comprehensive via:
  // - Sentry SDK integration
  // - FlutterError.onError
  // - PlatformDispatcher.instance.onError
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
        // Update UI with progress - read current state to get status
        final currentState = ref.read(modelDownloadProvider);
        downloadNotifier.updateProgress(progress, currentState.status);
      },
      onStatus: (status) {
        // Update UI with status - read current state to get progress
        debugPrint('[Main] $status');
        final currentState = ref.read(modelDownloadProvider);
        downloadNotifier.updateProgress(currentState.progress, status);

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
