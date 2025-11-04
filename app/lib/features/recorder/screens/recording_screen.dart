import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/post_recording_screen.dart';
import 'package:app/features/recorder/services/audio_service.dart';
import 'package:app/features/recorder/widgets/recording_visualizer.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/whisper_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';

class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  RecordingState _recordingState = RecordingState.stopped;
  Duration _recordingDuration = Duration.zero;
  Duration _pausedDuration = Duration.zero;
  DateTime? _startTime;
  DateTime? _pauseStartTime;
  Timer? _timer;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _initializeAndStartRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initializeAndStartRecording() async {
    final audioService = ref.read(audioServiceProvider);

    try {
      // Initialize audio service (required)
      await audioService.initialize();

      // Start audio recording
      final success = await audioService.startRecording();
      if (success) {
        _startTime = DateTime.now();
        _startTimer();
        if (mounted) {
          setState(() {
            _recordingState = RecordingState.recording;
          });
        }
        // Try to initialize transcription (optional, non-blocking)
        _initializeTranscription();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to start recording. Please check permissions.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting recording: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _initializeTranscription() async {
    // NOTE: Real-time transcription is disabled due to microphone conflict.
    // On Android, speech_to_text and flutter_sound cannot access the microphone
    // simultaneously. iOS supports concurrent access but Android does not.
    //
    // Alternative solutions:
    // 1. Use post-recording transcription with cloud APIs (Whisper, Google STT)
    // 2. Use vosk_flutter for offline transcription with audio stream
    // 3. Implement transcription after recording completes
    //
    // For now, transcription is left as a placeholder for future implementation.
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_recordingState == RecordingState.recording && _startTime != null) {
        setState(() {
          // Calculate total duration minus paused time
          final totalElapsed = DateTime.now().difference(_startTime!);
          _recordingDuration = totalElapsed - _pausedDuration;
        });
      } else if (_recordingState == RecordingState.stopped) {
        timer.cancel();
      }
    });
  }

  Future<void> _pauseRecording() async {
    final audioService = ref.read(audioServiceProvider);

    if (_recordingState == RecordingState.recording) {
      final success = await audioService.pauseRecording();
      if (success) {
        _pauseStartTime = DateTime.now();
        _timer?.cancel();
        setState(() {
          _recordingState = RecordingState.paused;
        });
      }
    } else if (_recordingState == RecordingState.paused) {
      final success = await audioService.resumeRecording();
      if (success) {
        // Add the paused duration to total paused time
        if (_pauseStartTime != null) {
          _pausedDuration += DateTime.now().difference(_pauseStartTime!);
          _pauseStartTime = null;
        }
        setState(() {
          _recordingState = RecordingState.recording;
        });
        _startTimer();
      }
    }
  }

  Future<void> _stopRecording() async {
    final audioService = ref.read(audioServiceProvider);
    final storageService = ref.read(storageServiceProvider);

    _timer?.cancel();
    setState(() {
      _recordingState = RecordingState.stopped;
    });

    final path = await audioService.stopRecording();

    if (path != null && mounted) {
      _recordingPath = path;
      // Calculate final duration
      if (_startTime != null) {
        final totalElapsed = DateTime.now().difference(_startTime!);
        _recordingDuration = totalElapsed - _pausedDuration;
      }

      // Save immediately without waiting for transcription
      await _saveRecordingImmediately(path, storageService);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save recording'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _saveRecordingImmediately(
    String recordingPath,
    dynamic storageService,
  ) async {
    try {
      // Generate default title with timestamp
      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final title = 'Recording $dateStr';

      final fileSizeKB = await ref
          .read(audioServiceProvider)
          .getFileSizeKB(recordingPath);
      final fileName = recordingPath.split('/').last;
      final recordingId = fileName.replaceAll('.m4a', '').split('-').last;

      final recording = Recording(
        id: recordingId,
        title: title,
        filePath: recordingPath,
        timestamp: DateTime.now(),
        duration: _recordingDuration,
        tags: [],
        transcript: '', // Will be processed in background
        fileSizeKB: fileSizeKB,
      );

      await storageService.saveRecording(recording);

      debugPrint(
        '[RecordingScreen] ✅ Recording saved, starting background processing...',
      );

      // Start background processing (fire and forget)
      _startBackgroundProcessing(recordingId, recordingPath).catchError((e) {
        debugPrint('[RecordingScreen] ❌ Background processing failed: $e');
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording saved! Processing in background...'),
            duration: Duration(seconds: 1),
          ),
        );

        // Navigate to recording detail page
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RecordingDetailScreen(recording: recording),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startBackgroundProcessing(
    String recordingId,
    String recordingPath,
  ) async {
    debugPrint(
      '[RecordingScreen] 🎬 Background processing started for: $recordingId',
    );

    final storageService = ref.read(storageServiceProvider);
    final autoTranscribe = await storageService.getAutoTranscribe();

    debugPrint('[RecordingScreen] Auto-transcribe enabled: $autoTranscribe');

    if (!autoTranscribe) {
      debugPrint(
        '[RecordingScreen] ⏭️ Auto-transcribe disabled, skipping background processing',
      );
      return;
    }

    try {
      debugPrint('[RecordingScreen] 🔄 Starting background transcription...');

      // Mark as processing
      var recording = await storageService.getRecording(recordingId);
      if (recording != null) {
        recording = recording.copyWith(
          transcriptionStatus: ProcessingStatus.processing,
        );
        await storageService.updateRecording(recording);
      }

      // Get transcription mode
      final modeString = await storageService.getTranscriptionMode();
      final mode =
          TranscriptionMode.fromString(modeString) ?? TranscriptionMode.api;

      String transcript;
      if (mode == TranscriptionMode.local) {
        final localService = ref.read(whisperLocalServiceProvider);
        final isReady = await localService.isReady();
        if (!isReady) {
          debugPrint('[RecordingScreen] Whisper model not ready, skipping');
          return;
        }
        transcript = await localService.transcribeAudio(recordingPath);
      } else {
        final whisperService = ref.read(whisperServiceProvider);
        final isConfigured = await whisperService.isConfigured();
        if (!isConfigured) {
          debugPrint('[RecordingScreen] API key not configured, skipping');
          return;
        }
        transcript = await whisperService.transcribeAudio(recordingPath);
      }

      debugPrint(
        '[RecordingScreen] ✅ Transcription complete: ${transcript.length} chars',
      );

      // Update with transcript first
      recording = recording?.copyWith(
        transcript: transcript,
        transcriptionStatus: ProcessingStatus.completed,
        titleGenerationStatus: ProcessingStatus.processing,
      );
      if (recording != null) {
        await storageService.updateRecording(recording);
        debugPrint('[RecordingScreen] ✅ Transcript saved');
      }

      // Generate title from transcript
      String? generatedTitle;
      ProcessingStatus titleStatus = ProcessingStatus.completed;
      try {
        final titleService = ref.read(titleGenerationServiceProvider);
        generatedTitle = await titleService.generateTitle(transcript);
        debugPrint('[RecordingScreen] ✅ Title generated: "$generatedTitle"');
      } catch (e) {
        debugPrint('[RecordingScreen] ⚠️ Title generation failed: $e');
        titleStatus = ProcessingStatus.failed;
      }

      // Update with final title
      final updatedRecording = await storageService.getRecording(recordingId);
      if (updatedRecording != null) {
        final finalRecording = updatedRecording.copyWith(
          title: generatedTitle ?? updatedRecording.title,
          titleGenerationStatus: titleStatus,
        );
        await storageService.updateRecording(finalRecording);
        debugPrint('[RecordingScreen] ✅ Recording fully updated');
      }
    } catch (e) {
      debugPrint('[RecordingScreen] ❌ Background processing failed: $e');
    }
  }

  void _navigateToPostRecording(String transcription) {
    if (_recordingPath != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PostRecordingScreen(
            recordingPath: _recordingPath!,
            duration: _recordingDuration,
            initialTranscript: transcription.isNotEmpty ? transcription : null,
          ),
        ),
      );
    }
  }

  String get _formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Recording'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Recording status
            Text(
              _recordingState == RecordingState.recording
                  ? 'Recording...'
                  : _recordingState == RecordingState.paused
                  ? 'Paused'
                  : 'Initializing...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _recordingState == RecordingState.recording
                    ? Theme.of(context).colorScheme.primary
                    : _recordingState == RecordingState.paused
                    ? Colors.orange
                    : Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            // Recording visualizer
            RecordingVisualizer(
              isRecording: _recordingState == RecordingState.recording,
            ),
            const SizedBox(height: 30),
            // Duration display
            Text(
              _formattedDuration,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 20),
            // Recording indicator
            if (_recordingState == RecordingState.recording)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('recording...'),
                ],
              ),
            const SizedBox(height: 20),
            const Spacer(),
            // Control buttons
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Pause/Resume button
                  FloatingActionButton(
                    heroTag: 'pauseButton',
                    onPressed: _recordingState != RecordingState.stopped
                        ? _pauseRecording
                        : null,
                    backgroundColor: _recordingState != RecordingState.stopped
                        ? Colors.orange
                        : Colors.grey,
                    child: Icon(
                      _recordingState == RecordingState.recording
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                  // Stop button
                  FloatingActionButton(
                    heroTag: 'stopButton',
                    onPressed: _recordingState != RecordingState.stopped
                        ? _stopRecording
                        : null,
                    backgroundColor: _recordingState != RecordingState.stopped
                        ? Colors.red
                        : Colors.grey,
                    child: const Icon(Icons.stop, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Text('Tap stop to finish recording'),
          ],
        ),
      ),
    );
  }
}
