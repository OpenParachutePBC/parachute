import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/recording_post_processing_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/features/recorder/widgets/model_download_banner.dart';
import 'package:path/path.dart' as path;

/// Enhanced recording screen with live waveform ring and context input
///
/// Design principles:
/// - Green = recording (go!)
/// - Orange = paused (waiting)
/// - Blue = processing
/// - Live waveform visualization
/// - Context input during + after recording
class SimpleRecordingScreen extends ConsumerStatefulWidget {
  const SimpleRecordingScreen({super.key});

  @override
  ConsumerState<SimpleRecordingScreen> createState() =>
      _SimpleRecordingScreenState();
}

class _SimpleRecordingScreenState extends ConsumerState<SimpleRecordingScreen>
    with TickerProviderStateMixin {
  // Recording state
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSaving = false;
  String _contextInput = '';
  bool _showContextInput = false;

  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;

  // Waveform state
  List<double> _waveformAmplitudes = List.filled(
    24,
    0.0,
  ); // 24 dots around circle
  Timer? _waveformTimer;
  final _random = math.Random();

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _contextSlideController;
  late Animation<Offset> _contextSlideAnimation;

  @override
  void initState() {
    super.initState();

    // Gentle fade animation for recording state (soft and subtle)
    _pulseController = AnimationController(
      duration: const Duration(seconds: 4), // Slow breathing rhythm
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Context input slide animation
    _contextSlideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _contextSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _contextSlideController,
            curve: Curves.easeOut,
          ),
        );

    // Auto-start recording when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecording();
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _waveformTimer?.cancel();
    _pulseController.dispose();
    _contextSlideController.dispose();
    super.dispose();
  }

  void _startRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.startRecording();
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
      });
      _startDurationTimer();
      _startWaveformAnimation();
      _pulseController.repeat(reverse: true); // Gentle fade in/out
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  void _pauseRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.pauseRecording();
      setState(() {
        _isPaused = true;
      });
      _stopWaveformAnimation();
      _pulseController.stop();
    } catch (e) {
      _showError('Failed to pause recording: $e');
    }
  }

  void _resumeRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.resumeRecording();
      setState(() {
        _isPaused = false;
      });
      _startWaveformAnimation();
      _pulseController.repeat(reverse: true); // Resume gentle fade
    } catch (e) {
      _showError('Failed to resume recording: $e');
    }
  }

  void _saveRecording() async {
    setState(() => _isSaving = true);

    final audioService = ref.read(audioServiceProvider);
    final fileSystemService = ref.read(fileSystemServiceProvider);
    final postProcessingService = ref.read(recordingPostProcessingProvider);
    final storageService = ref.read(storageServiceProvider);

    try {
      // Stop recording
      final audioPath = await audioService.stopRecording();
      _stopDurationTimer();
      _stopWaveformAnimation();
      _pulseController.stop();

      if (audioPath == null) {
        throw Exception('No audio path returned');
      }

      // Copy audio file to captures folder immediately (keep as WAV for now)
      final timestamp = FileSystemService.formatTimestampForFilename(
        _startTime!,
      );
      final capturesPath = await fileSystemService.getCapturesPath();
      final audioDestPath = path.join(capturesPath, '$timestamp.wav');
      await File(audioPath).copy(audioDestPath);

      // Create recording with placeholder transcript (using WAV path)
      // Will be compressed to Opus after transcription completes
      final recording = Recording(
        id: timestamp,
        title: 'Untitled Recording',
        filePath: audioDestPath,
        timestamp: _startTime!,
        duration: _recordingDuration,
        tags: [],
        transcript: 'Transcribing...', // Placeholder
        context: _contextInput,
        fileSizeKB: await File(audioDestPath).length() / 1024,
        source: RecordingSource.phone,
        transcriptionStatus: ProcessingStatus.processing, // In progress
        titleGenerationStatus: ProcessingStatus.pending,
        liveTranscriptionStatus: 'in_progress',
      );

      // Save recording immediately with placeholder
      await storageService.saveRecording(recording);
      ref.read(recordingsRefreshTriggerProvider.notifier).state++;

      // Start background transcription (non-blocking)
      // Will compress to Opus after transcription completes
      _processInBackground(
        audioDestPath: audioDestPath,
        recording: recording,
        postProcessingService: postProcessingService,
        storageService: storageService,
      );

      setState(() {
        _isRecording = false;
        _isSaving = false;
        _recordingDuration = Duration.zero;
      });

      // Navigate immediately to detail screen (transcription will update in background)
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RecordingDetailScreen(recording: recording),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Failed to save recording: $e');
    }
  }

  void _discardRecording() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Recording?'),
        content: const Text('This will permanently delete this recording.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final audioService = ref.read(audioServiceProvider);
      await audioService.stopRecording();
      _stopDurationTimer();
      _stopWaveformAnimation();
      _pulseController.stop();

      // Navigate back to home
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _toggleContextInput() {
    setState(() {
      _showContextInput = !_showContextInput;
    });
    if (_showContextInput) {
      _contextSlideController.forward();
    } else {
      _contextSlideController.reverse();
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          _recordingDuration = _recordingDuration + const Duration(seconds: 1);
        });
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _startWaveformAnimation() {
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        // Simulate waveform with random amplitudes
        // In real implementation, this would come from actual audio input
        for (int i = 0; i < _waveformAmplitudes.length; i++) {
          _waveformAmplitudes[i] = 0.3 + _random.nextDouble() * 0.7;
        }
      });
    });
  }

  void _stopWaveformAnimation() {
    _waveformTimer?.cancel();
    _waveformTimer = null;
    setState(() {
      _waveformAmplitudes = List.filled(24, 0.0);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color get _primaryColor {
    if (_isSaving) return Colors.blue;
    if (_isPaused) return Colors.orange;
    if (_isRecording) return Colors.green;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A3A2F), // Dark teal
      body: SafeArea(
        child: Column(
          children: [
            // Model download banner (shows when downloading)
            const ModelDownloadBanner(),

            // Main content
            Expanded(
              child: Stack(
                children: [
                  // Main content
                  Column(
                    children: [
                      _buildHeader(),
                      Expanded(child: _buildRecordingArea()),
                      _buildControls(),
                    ],
                  ),

                  // Context input (slides up from bottom)
                  if (_showContextInput) _buildContextInput(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Discard button (X)
          if (_isRecording || _isPaused)
            IconButton(
              onPressed: _discardRecording,
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Discard recording',
            )
          else
            const SizedBox(width: 48),

          // App title
          const Text(
            'Parachute',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
          ),

          // Spacing to keep title centered
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildRecordingArea() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Waveform ring with center info
          FadeTransition(
            opacity: _pulseAnimation,
            child: SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Waveform ring
                  CustomPaint(
                    size: const Size(280, 280),
                    painter: WaveformRingPainter(
                      amplitudes: _waveformAmplitudes,
                      color: _primaryColor,
                      isRecording: _isRecording && !_isPaused,
                    ),
                  ),

                  // Center content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSaving)
                        const CircularProgressIndicator(color: Colors.white)
                      else if (_isRecording || _isPaused)
                        Icon(
                          _isPaused ? Icons.pause : Icons.mic,
                          size: 48,
                          color: Colors.white,
                        )
                      else
                        const Icon(
                          Icons.mic_none,
                          size: 48,
                          color: Colors.white54,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        _formatDuration(_recordingDuration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Status text
          Text(
            _getStatusText(),
            style: const TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),

          // Context hint (when recording)
          if (_isRecording && !_showContextInput)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _toggleContextInput,
                icon: const Icon(Icons.note_add, size: 16),
                label: const Text('Add context'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white54,
                  textStyle: const TextStyle(fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    if (_isSaving) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text('Processing...', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    if (!_isRecording) {
      // Start recording button
      return Padding(
        padding: const EdgeInsets.all(32),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.fiber_manual_record),
                SizedBox(width: 8),
                Text('Start Recording', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
        ),
      );
    }

    // Pause/Resume and Save buttons
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isPaused ? Colors.green : Colors.orange,
                  side: BorderSide(
                    color: _isPaused ? Colors.green : Colors.orange,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    const SizedBox(width: 8),
                    Text(
                      _isPaused ? 'Resume' : 'Pause',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _saveRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0A3A2F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check),
                    SizedBox(width: 8),
                    Text('Save', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextInput() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleContextInput,
        child: Container(
          color: Colors.black54,
          child: SlideTransition(
            position: _contextSlideAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Context',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleContextInput,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      autofocus: true,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'What is this recording about?',
                        hintStyle: TextStyle(color: Colors.black38),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (value) => _contextInput = value,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            // TODO: Voice input for context
                          },
                          icon: const Icon(Icons.mic),
                          tooltip: 'Voice input',
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _toggleContextInput,
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusText() {
    if (_isSaving) return 'Transcribing and processing...';
    if (_isPaused) return 'Paused • Tap Resume to continue or Save to finish';
    if (_isRecording) return 'Recording • Speak naturally';
    return 'Ready to record';
  }

  /// Process transcription in background without blocking UI
  void _processInBackground({
    required String audioDestPath,
    required Recording recording,
    required RecordingPostProcessingService postProcessingService,
    required StorageService storageService,
  }) async {
    try {
      // Process in background
      final result = await postProcessingService.process(
        audioPath: audioDestPath,
      );

      // Compress WAV to Opus after successful transcription
      debugPrint(
        '[SimpleRecording] Transcription complete, compressing to Opus...',
      );
      final compressionService = AudioCompressionServiceDart();
      final opusPath = await compressionService.compressToOpus(
        wavPath: audioDestPath,
        deleteOriginal: false, // Keep WAV for playback and local use
      );
      debugPrint('[SimpleRecording] Compression complete: $opusPath');

      // Update recording with transcript and new Opus file path
      final updatedRecording = recording.copyWith(
        transcript: result.transcript,
        transcriptionStatus: ProcessingStatus.completed,
        liveTranscriptionStatus: 'completed',
        filePath: opusPath,
        fileSizeKB: await File(opusPath).length() / 1024,
      );

      // Save updated recording
      await storageService.updateRecording(updatedRecording);

      // Only trigger refresh if widget is still mounted
      if (mounted) {
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      }
    } catch (e) {
      debugPrint('[SimpleRecording] Background transcription failed: $e');
      // Update recording to show error state
      final errorRecording = recording.copyWith(
        transcript: 'Transcription failed. Please try again.',
        transcriptionStatus: ProcessingStatus.failed,
        liveTranscriptionStatus: 'failed',
      );
      await storageService.updateRecording(errorRecording);

      // Only trigger refresh if widget is still mounted
      if (mounted) {
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      }
    }
  }
}

/// Custom painter for waveform ring
class WaveformRingPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;
  final bool isRecording;

  WaveformRingPainter({
    required this.amplitudes,
    required this.color,
    required this.isRecording,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final angleStep = (2 * math.pi) / amplitudes.length;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < amplitudes.length; i++) {
      final angle = i * angleStep - math.pi / 2; // Start from top
      final amplitude = isRecording ? amplitudes[i] : 0.2;
      final dotRadius = 4 + (amplitude * 8); // 4-12 based on amplitude

      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(WaveformRingPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes ||
        oldDelegate.color != color ||
        oldDelegate.isRecording != isRecording;
  }
}

/// Post-save context input modal
