import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue_plus;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'core/theme/app_theme.dart';
import 'core/theme/design_tokens.dart';
import 'core/services/logging_service.dart';
import 'core/services/file_system_service.dart';
import 'core/services/asset_migration_service.dart';
import 'core/providers/feature_flags_provider.dart';
import 'features/recorder/providers/model_download_provider.dart';
import 'features/recorder/services/transcription_service_adapter.dart';
import 'features/onboarding/screens/onboarding_flow.dart';
import 'features/chat/screens/agent_hub_screen.dart';
import 'features/files/screens/files_screen.dart';
import 'features/journal/screens/journal_screen.dart';
import 'services/sherpa_onnx_service.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file (optional, fails silently if not found)
  bool envLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    envLoaded = true;
    debugPrint('[Main] ✅ Loaded .env file');
  } catch (e) {
    debugPrint(
      '[Main] ⚠️  No .env file found (this is ok, using --dart-define or defaults)',
    );
  }

  // Initialize logging service with Sentry (only in release mode)
  // This keeps debug output clean and avoids Sentry SDK warnings during development
  // Only access dotenv.env if it was successfully loaded
  final sentryDsn = (kReleaseMode && envLoaded) ? dotenv.env['SENTRY_DSN'] : null;
  await logger.initialize(
    sentryDsn: sentryDsn,
    environment: kReleaseMode ? 'production' : 'development',
    release: 'parachute@1.0.0', // Update this with your version
  );

  // Initialize Opus codec for Omi BLE audio decoding (iOS/Android only)
  // macOS doesn't support opus_flutter, so we skip initialization there
  if (Platform.isIOS || Platform.isAndroid) {
    try {
      debugPrint('[Main] Initializing Opus codec...');
      // Load the native opus library via opus_flutter
      final opusLib = await opus_flutter.load();
      // Initialize opus_dart with the loaded library
      opus_dart.initOpus(opusLib as DynamicLibrary);
      debugPrint('[Main] ✅ Opus codec initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[Main] ⚠️  Failed to initialize Opus codec: $e');
      debugPrint('[Main] Stack trace: $stackTrace');
      debugPrint('[Main] Omi device audio decoding will not work');
      // Continue anyway - only affects Omi device integration
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
  bool _hasSeenWelcome = true; // Default to true, will be updated
  bool _isCheckingWelcome = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkWelcomeScreen();
    _setupTranscriptionCallbacks();
    _preInitializeTranscription();
    _runAssetMigration();
  }

  /// Run asset migration if needed (moves audio files to unified assets/ folder)
  void _runAssetMigration() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final fileSystem = FileSystemService();
        await fileSystem.initialize();
        final migration = AssetMigrationService(fileSystem);
        final migrated = await migration.runMigrationIfNeeded();
        if (migrated > 0) {
          debugPrint('[Main] Migrated $migrated audio files to unified assets folder');
        }
      } catch (e) {
        debugPrint('[Main] Asset migration error (non-fatal): $e');
      }
    });
  }

  /// Pre-initialize transcription model after first frame to avoid UI freeze during recording
  void _preInitializeTranscription() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pre-initialize Sherpa-ONNX if models are already downloaded
      // This runs on the main thread but after the UI has rendered,
      // so the user sees the Journal screen before any potential model loading
      SherpaOnnxService().preInitializeIfReady();
    });
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

    // Watch AI chat enabled state
    final aiChatEnabled = ref.watch(aiChatEnabledNotifierProvider);
    final isAiChatEnabled = aiChatEnabled.valueOrNull ?? false;

    // Show bottom navigation with Journal, Record, and other tabs
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Build the list of screens and destinations based on enabled features
    // Journal is the main hub - Record tab removed in favor of inline recording
    final screens = <Widget>[
      const JournalScreen(),
    ];

    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(
          Icons.book_outlined,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        selectedIcon: Icon(
          Icons.book,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        label: 'Journal',
      ),
    ];

    // Add Chat tab if AI chat is enabled
    if (isAiChatEnabled) {
      screens.add(const AgentHubScreen());
      destinations.add(
        NavigationDestination(
          icon: Icon(
            Icons.chat_outlined,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
          selectedIcon: Icon(
            Icons.chat,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          label: 'Chat',
        ),
      );
    }

    // Always add Files tab
    screens.add(const FilesScreen());
    destinations.add(
      NavigationDestination(
        icon: Icon(
          Icons.folder_outlined,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        selectedIcon: Icon(
          Icons.folder,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        label: 'Files',
      ),
    );

    // Get keyboard height for padding adjustment
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor:
              isDark ? BrandColors.nightSurface : BrandColors.softWhite,
          indicatorColor: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.2)
              : BrandColors.forestMist,
          destinations: destinations,
        ),
      ),
    );
  }
}
