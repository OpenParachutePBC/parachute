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
import 'features/onboarding/screens/onboarding_flow.dart';
import 'features/chat/screens/agent_hub_screen.dart';
import 'features/vault/screens/vault_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  bool envLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    envLoaded = true;
    debugPrint('[Main] Loaded .env file');
  } catch (e) {
    debugPrint('[Main] No .env file found (using defaults)');
  }

  // Initialize logging with Sentry (release mode only)
  final sentryDsn = (kReleaseMode && envLoaded) ? dotenv.env['SENTRY_DSN'] : null;
  await logger.initialize(
    sentryDsn: sentryDsn,
    environment: kReleaseMode ? 'production' : 'development',
    release: 'parachute-chat@1.0.0',
  );

  // Initialize Opus codec for Omi BLE audio (iOS/Android only)
  if (Platform.isIOS || Platform.isAndroid) {
    try {
      debugPrint('[Main] Initializing Opus codec...');
      final opusLib = await opus_flutter.load();
      opus_dart.initOpus(opusLib);
      debugPrint('[Main] Opus codec initialized');
    } catch (e, stackTrace) {
      debugPrint('[Main] Opus codec init failed: $e');
      debugPrint('$stackTrace');
    }
  }

  // Disable verbose BLE logs
  flutter_blue_plus.FlutterBluePlus.setLogLevel(
    flutter_blue_plus.LogLevel.none,
    color: false,
  );

  // Initialize Flutter Gemma for local AI
  try {
    logger.info('Main', 'Initializing FlutterGemma...');
    await FlutterGemma.initialize();
    logger.info('Main', 'FlutterGemma initialized');
  } catch (e, stackTrace) {
    logger.error('Main', 'FlutterGemma init failed', error: e, stackTrace: stackTrace);
  }

  // Global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
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

  PlatformDispatcher.instance.onError = (error, stack) {
    logger.captureException(error, stackTrace: stack, tag: 'PlatformDispatcher');
    return true;
  };

  runApp(const ProviderScope(child: ParachuteChatApp()));
}

class ParachuteChatApp extends StatelessWidget {
  const ParachuteChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parachute Chat',
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
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  bool _hasSeenWelcome = true;
  bool _isCheckingWelcome = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _checkWelcomeScreen();
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
    if (_isCheckingWelcome) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasSeenWelcome) {
      return OnboardingFlow(
        onComplete: () => setState(() => _hasSeenWelcome = true),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Chat is the main feature - always shown
    final screens = <Widget>[
      const AgentHubScreen(),
      const VaultScreen(),
    ];

    final destinations = <NavigationDestination>[
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
      NavigationDestination(
        icon: Icon(
          Icons.folder_outlined,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        selectedIcon: Icon(
          Icons.folder,
          color: isDark ? BrandColors.nightForest : BrandColors.forest,
        ),
        label: 'Vault',
      ),
    ];

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
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
          indicatorColor: isDark
              ? BrandColors.nightForest.withValues(alpha: 0.2)
              : BrandColors.forestMist,
          destinations: destinations,
        ),
      ),
    );
  }
}
