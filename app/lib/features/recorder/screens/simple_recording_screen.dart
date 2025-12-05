import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/recording_post_processing_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/services/audio_service.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';
import 'package:app/core/providers/file_system_provider.dart';
import 'package:app/features/recorder/widgets/model_download_banner.dart';
import 'package:path/path.dart' as path;

/// Recording screen with Parachute brand styling
///
/// "Think naturally" - A calm, immersive space for voice capture.
///
/// State colors:
/// - Forest green = recording (natural, grounded)
/// - Warm amber = paused (waiting, calm)
/// - Turquoise = processing (flow, clarity)
class SimpleRecordingScreen extends ConsumerStatefulWidget {
  /// If set, records a new segment to append to an existing recording
  final String? appendToRecordingId;

  const SimpleRecordingScreen({
    super.key,
    this.appendToRecordingId,
  });

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

  // Waveform state - smooth animation using real amplitude
  List<double> _waveformAmplitudes = List.filled(24, 0.0);
  List<double> _targetAmplitudes = List.filled(24, 0.0);
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  late AnimationController _waveformController;
  double _currentAmplitude = 0.0;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _contextSlideController;
  late Animation<Offset> _contextSlideAnimation;

  @override
  void initState() {
    super.initState();

    // Gentle breathing animation (4s - calm, unhurried)
    _pulseController = AnimationController(
      duration: Motion.breathing,
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Motion.breathe),
    );

    // Smooth waveform animation - listener fires every frame while animating
    _waveformController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..addListener(_updateWaveformAmplitudes);

    // Context input slide animation
    _contextSlideController = AnimationController(
      duration: Motion.gentle,
      vsync: this,
    );
    _contextSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _contextSlideController,
            curve: Motion.settling,
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
    _amplitudeSubscription?.cancel();
    _waveformController.dispose();
    _pulseController.dispose();
    _contextSlideController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.startRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
      });
      _startDurationTimer();
      _startWaveformAnimation();
      _pulseController.repeat(reverse: true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _pauseRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.pauseRecording();
      if (!mounted) return;
      setState(() {
        _isPaused = true;
      });
      _stopWaveformAnimation();
      _pulseController.stop();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to pause recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.resumeRecording();
      if (!mounted) return;
      setState(() {
        _isPaused = false;
      });
      _startWaveformAnimation();
      _pulseController.repeat(reverse: true);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to resume recording: $e');
    }
  }

  Future<void> _saveRecording() async {
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

      // Capture values before any async gaps to avoid null issues
      final startTime = _startTime;
      if (startTime == null) {
        throw Exception('Recording start time not set');
      }

      // Check if we're appending to an existing recording
      if (widget.appendToRecordingId != null) {
        await _saveAppendedRecording(
          audioPath: audioPath,
          audioService: audioService,
          fileSystemService: fileSystemService,
          postProcessingService: postProcessingService,
          storageService: storageService,
        );
        return;
      }

      // Copy audio file to captures folder immediately (keep as WAV for now)
      final timestamp = FileSystemService.formatTimestampForFilename(
        startTime,
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
        timestamp: startTime,
        duration: _recordingDuration,
        tags: [],
        transcript: 'Transcribing...',
        context: _contextInput,
        fileSizeKB: await File(audioDestPath).length() / 1024,
        source: RecordingSource.phone,
        transcriptionStatus: ProcessingStatus.processing,
        titleGenerationStatus: ProcessingStatus.pending,
        liveTranscriptionStatus: 'in_progress',
      );

      // Save recording immediately with placeholder
      await storageService.saveRecording(recording);
      if (mounted) {
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      }

      // Start background transcription (non-blocking)
      _processInBackground(
        audioDestPath: audioDestPath,
        recording: recording,
        postProcessingService: postProcessingService,
        storageService: storageService,
      );

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _isSaving = false;
        _recordingDuration = Duration.zero;
      });

      // Navigate immediately to detail screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RecordingDetailScreen(recording: recording),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Failed to save recording: $e');
    }
  }

  /// Save a segment appended to an existing recording
  Future<void> _saveAppendedRecording({
    required String audioPath,
    required AudioService audioService,
    required FileSystemService fileSystemService,
    required RecordingPostProcessingService postProcessingService,
    required StorageService storageService,
  }) async {
    try {
      final existingId = widget.appendToRecordingId!;
      final capturesPath = await fileSystemService.getCapturesPath();

      // Get existing recording
      final existing = await storageService.getRecording(existingId);
      if (existing == null) {
        throw Exception('Recording not found: $existingId');
      }

      // Find the existing WAV file
      final existingWavPath = path.join(capturesPath, '$existingId.wav');
      final existingOpusPath = path.join(capturesPath, '$existingId.opus');

      String targetWavPath = existingWavPath;
      if (!await File(existingWavPath).exists()) {
        if (await File(existingOpusPath).exists()) {
          debugPrint('[SimpleRecording] Decompressing opus to wav for append...');
          final compressionService = AudioCompressionServiceDart();
          await compressionService.decompressToWav(
            opusPath: existingOpusPath,
            outputPath: existingWavPath,
          );
          targetWavPath = existingWavPath;
        } else {
          throw Exception('No audio file found for recording: $existingId');
        }
      }

      // Append the new audio to the existing WAV
      debugPrint('[SimpleRecording] Appending audio segment...');
      final segmentDuration = await audioService.appendWavFile(
        targetWavPath,
        audioPath,
      );

      // Get original duration
      final originalDurationSeconds = existing.duration.inMilliseconds / 1000;
      final newTotalDuration = originalDurationSeconds + segmentDuration;

      // Get new file size
      final newFileSizeKB = await File(targetWavPath).length() / 1024;

      // Transcribe the new segment
      debugPrint('[SimpleRecording] Transcribing appended segment...');
      final result = await postProcessingService.process(audioPath: audioPath);

      // Update the recording with appended content
      final success = await storageService.appendToRecording(
        recordingId: existingId,
        newTranscript: result.transcript,
        newSegmentEndSeconds: newTotalDuration,
        segmentRecordedAt: _startTime!,
        newFileSizeKB: newFileSizeKB,
      );

      if (!success) {
        throw Exception('Failed to update recording metadata');
      }

      // Re-compress to opus after successful append
      debugPrint('[SimpleRecording] Re-compressing to opus after append...');
      final compressionService = AudioCompressionServiceDart();
      await compressionService.compressToOpus(
        wavPath: targetWavPath,
        deleteOriginal: false,
      );

      // Clean up temp audio file
      try {
        await File(audioPath).delete();
      } catch (_) {}

      ref.read(recordingsRefreshTriggerProvider.notifier).state++;

      setState(() {
        _isRecording = false;
        _isSaving = false;
        _recordingDuration = Duration.zero;
      });

      // Navigate back with success result
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      _showError('Failed to append recording: $e');
    }
  }

  Future<void> _discardRecording() async {
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
            style: TextButton.styleFrom(foregroundColor: BrandColors.error),
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
    final audioService = ref.read(audioServiceProvider);

    // Subscribe to real audio amplitude from the recorder
    _amplitudeSubscription = audioService.recorder.onAmplitudeChanged(
      const Duration(milliseconds: 50),
    ).listen((amp) {
      // Convert dBFS to 0-1 range (dBFS is typically -160 to 0)
      // amp.current is the current amplitude in dBFS
      final normalized = ((amp.current + 50) / 50).clamp(0.0, 1.0);
      _currentAmplitude = normalized;

      // Generate target amplitudes based on current level with some variation
      final random = math.Random();
      for (int i = 0; i < _targetAmplitudes.length; i++) {
        // Base amplitude from audio + small random variation for organic feel
        final variation = (random.nextDouble() - 0.5) * 0.3;
        _targetAmplitudes[i] = (_currentAmplitude + variation).clamp(0.1, 1.0);
      }
    });

    // Start smooth interpolation animation
    _waveformController.repeat();
  }

  /// Smoothly interpolate current amplitudes toward targets (called every frame)
  void _updateWaveformAmplitudes() {
    if (!mounted) return;

    const smoothing = 0.15; // Lower = smoother but slower response

    for (int i = 0; i < _waveformAmplitudes.length; i++) {
      final diff = _targetAmplitudes[i] - _waveformAmplitudes[i];
      _waveformAmplitudes[i] += diff * smoothing;
    }

    // Always trigger rebuild - shouldRepaint handles optimization
    setState(() {});
  }

  void _stopWaveformAnimation() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _waveformController.stop();

    // Smoothly fade out to zero
    for (int i = 0; i < _targetAmplitudes.length; i++) {
      _targetAmplitudes[i] = 0.0;
    }
    _currentAmplitude = 0.0;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: BrandColors.error),
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
    if (_isSaving) return BrandColors.turquoise;
    if (_isPaused) return BrandColors.warning;
    if (_isRecording) return BrandColors.forest;
    return BrandColors.driftwood;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.forestDeep,
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
      padding: EdgeInsets.all(Spacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Discard button (X)
          if (_isRecording || _isPaused)
            IconButton(
              onPressed: _discardRecording,
              icon: Icon(
                Icons.close,
                color: BrandColors.cream.withValues(alpha: 0.9),
              ),
              tooltip: 'Discard recording',
            )
          else
            SizedBox(width: Spacing.xxxl),

          // App title or append mode indicator
          Text(
            widget.appendToRecordingId != null
                ? 'Adding Content'
                : 'Parachute',
            style: TextStyle(
              color: BrandColors.cream,
              fontSize: TypographyTokens.headlineMedium,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.2,
            ),
          ),

          // Spacing to keep title centered
          SizedBox(width: Spacing.xxxl),
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
                        CircularProgressIndicator(
                          color: BrandColors.cream,
                          strokeWidth: 2,
                        )
                      else if (_isRecording || _isPaused)
                        Icon(
                          _isPaused ? Icons.pause : Icons.mic,
                          size: 48,
                          color: BrandColors.cream,
                        )
                      else
                        Icon(
                          Icons.mic_none,
                          size: 48,
                          color: BrandColors.cream.withValues(alpha: 0.5),
                        ),
                      SizedBox(height: Spacing.lg),
                      Text(
                        _formatDuration(_recordingDuration),
                        style: TextStyle(
                          color: BrandColors.cream,
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: Spacing.xxl),

          // Status text
          Text(
            _getStatusText(),
            style: TextStyle(
              color: BrandColors.cream.withValues(alpha: 0.7),
              fontSize: TypographyTokens.bodyLarge,
            ),
            textAlign: TextAlign.center,
          ),

          // Context hint (when recording)
          if (_isRecording && !_showContextInput)
            Padding(
              padding: EdgeInsets.only(top: Spacing.sm),
              child: TextButton.icon(
                onPressed: _toggleContextInput,
                icon: Icon(
                  Icons.note_add,
                  size: 16,
                  color: BrandColors.cream.withValues(alpha: 0.5),
                ),
                label: Text(
                  'Add context',
                  style: TextStyle(
                    color: BrandColors.cream.withValues(alpha: 0.5),
                    fontSize: TypographyTokens.bodyMedium,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    if (_isSaving) {
      return Padding(
        padding: EdgeInsets.all(Spacing.xxl),
        child: Center(
          child: Text(
            'Processing...',
            style: TextStyle(
              color: BrandColors.cream.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    if (!_isRecording) {
      // Start recording button
      return Padding(
        padding: EdgeInsets.all(Spacing.xxl),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandColors.forest,
              foregroundColor: BrandColors.cream,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.full),
              ),
              elevation: Elevation.low,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fiber_manual_record),
                SizedBox(width: Spacing.sm),
                Text(
                  'Start Recording',
                  style: TextStyle(fontSize: TypographyTokens.titleMedium),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Pause/Resume and Save buttons
    return Padding(
      padding: EdgeInsets.all(Spacing.xxl),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isPaused
                      ? BrandColors.forest
                      : BrandColors.warning,
                  side: BorderSide(
                    color: _isPaused ? BrandColors.forest : BrandColors.warning,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    SizedBox(width: Spacing.sm),
                    Text(
                      _isPaused ? 'Resume' : 'Pause',
                      style: TextStyle(fontSize: TypographyTokens.titleMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: Spacing.lg),
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _saveRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.cream,
                  foregroundColor: BrandColors.forestDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  elevation: Elevation.low,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check),
                    SizedBox(width: Spacing.sm),
                    Text(
                      'Save',
                      style: TextStyle(fontSize: TypographyTokens.titleMedium),
                    ),
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
          color: BrandColors.ink.withValues(alpha: 0.6),
          child: SlideTransition(
            position: _contextSlideAnimation,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.all(Spacing.xl),
                decoration: BoxDecoration(
                  color: BrandColors.softWhite,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(Radii.xl),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add Context',
                          style: TextStyle(
                            fontSize: TypographyTokens.headlineMedium,
                            fontWeight: FontWeight.w600,
                            color: BrandColors.charcoal,
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleContextInput,
                          icon: Icon(
                            Icons.close,
                            color: BrandColors.charcoal,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: Spacing.lg),
                    TextField(
                      autofocus: true,
                      maxLines: 3,
                      style: TextStyle(
                        color: BrandColors.charcoal,
                        fontSize: TypographyTokens.bodyLarge,
                      ),
                      decoration: InputDecoration(
                        hintText: 'What is this recording about?',
                        hintStyle: TextStyle(
                          color: BrandColors.driftwood,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        filled: true,
                        fillColor: BrandColors.softWhite,
                      ),
                      onChanged: (value) => _contextInput = value,
                    ),
                    SizedBox(height: Spacing.lg),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            // TODO: Voice input for context
                          },
                          icon: Icon(
                            Icons.mic,
                            color: BrandColors.forest,
                          ),
                          tooltip: 'Voice input',
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _toggleContextInput,
                          child: Text(
                            'Done',
                            style: TextStyle(color: BrandColors.forest),
                          ),
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
    final isAppendMode = widget.appendToRecordingId != null;
    if (_isSaving) {
      return isAppendMode
          ? 'Appending and transcribing...'
          : 'Transcribing and processing...';
    }
    if (_isPaused) return 'Paused • Tap Resume to continue or Save to finish';
    if (_isRecording) {
      return isAppendMode
          ? 'Recording new segment • Speak naturally'
          : 'Recording • Speak naturally';
    }
    return isAppendMode ? 'Ready to add more content' : 'Ready to record';
  }

  /// Process transcription in background without blocking UI
  Future<void> _processInBackground({
    required String audioDestPath,
    required Recording recording,
    required RecordingPostProcessingService postProcessingService,
    required StorageService storageService,
  }) async {
    // Capture the refresh notifier before async work starts
    // This allows us to trigger refresh even after widget is disposed
    // (which happens immediately via Navigator.pushReplacement)
    final refreshNotifier = ref.read(recordingsRefreshTriggerProvider.notifier);

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
        deleteOriginal: false,
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

      // Trigger refresh using captured notifier (works even after widget disposed)
      debugPrint('[SimpleRecording] Triggering recordings refresh...');
      refreshNotifier.state++;
    } catch (e) {
      debugPrint('[SimpleRecording] Background transcription failed: $e');
      // Update recording to show error state
      final errorRecording = recording.copyWith(
        transcript: 'Transcription failed. Please try again.',
        transcriptionStatus: ProcessingStatus.failed,
        liveTranscriptionStatus: 'failed',
      );
      await storageService.updateRecording(errorRecording);

      // Trigger refresh using captured notifier (works even after widget disposed)
      debugPrint('[SimpleRecording] Triggering recordings refresh after error...');
      refreshNotifier.state++;
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
    // Always repaint when recording - amplitudes change every frame
    if (isRecording) return true;
    return oldDelegate.color != color ||
        oldDelegate.isRecording != isRecording;
  }
}
