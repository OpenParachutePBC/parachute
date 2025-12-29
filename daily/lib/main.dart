import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as flutter_blue_plus;
import 'package:opus_dart/opus_dart.dart' as opus_dart;
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'core/theme/app_theme.dart';
import 'core/services/logger_service.dart';
import 'features/journal/screens/journal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final log = logger.createLogger('Main');

  // Initialize Opus codec for Omi BLE audio decoding (iOS/Android only)
  if (Platform.isIOS || Platform.isAndroid) {
    try {
      log.debug('Initializing Opus codec...');
      final opusLib = await opus_flutter.load();
      opus_dart.initOpus(opusLib);
      log.info('Opus codec initialized successfully');
    } catch (e, stackTrace) {
      log.warn('Failed to initialize Opus codec', error: e);
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Disable verbose FlutterBluePlus logs
  flutter_blue_plus.FlutterBluePlus.setLogLevel(
    flutter_blue_plus.LogLevel.none,
    color: false,
  );

  // Initialize Flutter Gemma for on-device AI (embeddings, title generation)
  try {
    log.info('Initializing FlutterGemma...');
    await FlutterGemma.initialize();
    log.info('FlutterGemma initialized successfully');
  } catch (e, stackTrace) {
    log.error('Failed to initialize FlutterGemma', error: e, stackTrace: stackTrace);
  }

  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    log.error(
      'Flutter error: ${details.exception}',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.error('Platform error: $error', error: error, stackTrace: stack);
    return true;
  };

  runApp(const ProviderScope(child: ParachuteDailyApp()));
}

class ParachuteDailyApp extends StatelessWidget {
  const ParachuteDailyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parachute Daily',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const JournalScreen(),
    );
  }
}
