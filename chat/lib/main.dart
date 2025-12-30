import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme/app_theme.dart';
import 'core/services/logging_service.dart';
import 'features/onboarding/screens/onboarding_flow.dart';
import 'features/chat/screens/agent_hub_screen.dart';

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
      home: const MainScreen(),
    );
  }
}

/// Main screen - shows onboarding or chat
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  bool _hasSeenWelcome = true;
  bool _isCheckingWelcome = true;

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

    // Chat is the only screen - simple and focused
    return const AgentHubScreen();
  }
}
