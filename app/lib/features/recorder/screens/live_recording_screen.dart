import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/services/live_transcription_service_v3.dart'
    as v3;
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/widgets/audio_debug_overlay.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/providers/file_system_provider.dart';
import 'package:path/path.dart' as path;

/// Live journaling screen with auto-pause transcription
///
/// User flow:
/// 1. Start listening → Begin speaking your thoughts
/// 2. Auto-pause detects silence → Text appears naturally
/// 3. Continue speaking → Seamless journaling experience
/// 4. Tap "Pause" if you need a break
/// 5. Tap "Save Journal Entry" → Save your thoughts
class LiveRecordingScreen extends ConsumerStatefulWidget {
  const LiveRecordingScreen({super.key});

  @override
  ConsumerState<LiveRecordingScreen> createState() =>
      _LiveRecordingScreenState();
}

class _LiveRecordingScreenState extends ConsumerState<LiveRecordingScreen> {
  v3.AutoPauseTranscriptionService? _transcriptionService; // Always V3 for now
  bool _showDebugOverlay = false; // Determined at init time
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();

  // Stream subscriptions - must be cancelled in dispose
  StreamSubscription<v3.TranscriptionSegment>? _segmentSubscription;
  StreamSubscription<bool>? _processingSubscription;
  StreamSubscription<bool>? _healthSubscription;

  // State
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  bool _streamHealthy = true;
  bool _isSaving = false; // Prevent UI flash during save transition
  bool _enableDiarization = false; // Toggle for speaker identification
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;

  // Segments (from transcription service)
  final List<v3.TranscriptionSegment> _segments = [];

  @override
  void initState() {
    super.initState();
    // Initialize service asynchronously (non-blocking)
    // This allows the UI to appear immediately
    Future.microtask(() => _initializeService());
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    // Cancel stream subscriptions to prevent memory leaks
    _segmentSubscription?.cancel();
    _processingSubscription?.cancel();
    _healthSubscription?.cancel();
    // Don't dispose service here - it's managed by the provider now
    _textController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );
      final storageService = ref.read(storageServiceProvider);

      // Check if debug overlay is enabled
      _showDebugOverlay = await storageService.getAudioDebugOverlay();
      if (!mounted) return;

      // Always use auto-pause (V3) for now
      debugPrint('[LiveRecordingScreen] Using AUTO-PAUSE mode (V3)');
      _transcriptionService = v3.AutoPauseTranscriptionService(
        transcriptionService,
      );

      await _transcriptionService!.initialize();
      if (!mounted) return;

      // Listen to segment updates (store subscription for cleanup)
      _segmentSubscription =
          _transcriptionService!.segmentStream.listen(_handleSegmentUpdate);

      // Listen to processing state (store subscription for cleanup)
      _processingSubscription =
          _transcriptionService!.isProcessingStream.listen((isProcessing) {
        if (mounted) {
          setState(() {
            _isProcessing = isProcessing;
          });
        }
      });

      // Listen to stream health (store subscription for cleanup)
      _healthSubscription =
          _transcriptionService!.streamHealthStream.listen((isHealthy) {
        if (mounted) {
          setState(() {
            _streamHealthy = isHealthy;
          });
        }
      });

      if (!mounted) return;
      setState(() {
        _isInitializing = false;
      });

      // Auto-start recording
      await _startRecording();
    } catch (e) {
      debugPrint('[LiveRecordingScreen] Initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize recorder: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _handleSegmentUpdate(v3.TranscriptionSegment segment) {
    if (!mounted) return;

    setState(() {
      // Update or add segment
      final index = _segments.indexWhere((s) => s.index == segment.index);
      if (index != -1) {
        _segments[index] = segment;
      } else {
        _segments.add(segment);
      }

      // Update text controller with all completed segments
      _updateTextController();
    });

    // Auto-scroll when new text appears
    if (segment.status == v3.TranscriptionSegmentStatus.completed) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  void _updateTextController() {
    final completedText = _segments
        .where((s) => s.status == v3.TranscriptionSegmentStatus.completed)
        .map((s) => s.text)
        .join('\n\n');

    if (_textController.text != completedText) {
      _textController.text = completedText;
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _startRecording() async {
    if (_transcriptionService == null) return;

    debugPrint('[LiveRecordingScreen] 🎙️ Attempting to start recording...');
    final success = await _transcriptionService!.startRecording();
    if (!mounted) return;

    debugPrint('[LiveRecordingScreen] Recording start result: $success');

    if (success) {
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
      });
      _startDurationTimer();
      debugPrint('[LiveRecordingScreen] ✅ Recording started successfully');
    } else {
      debugPrint('[LiveRecordingScreen] ❌ Failed to start recording');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to start listening. Check permissions.'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _togglePause() async {
    if (_transcriptionService == null) return;

    if (_isPaused) {
      await _transcriptionService!.resumeRecording();
      if (!mounted) return;
      setState(() {
        _isPaused = false;
      });
      _startDurationTimer();
    } else {
      _durationTimer?.cancel();
      await _transcriptionService!.pauseRecording();
      if (!mounted) return;
      setState(() {
        _isPaused = true;
      });
    }
  }

  Future<void> _stopAndSave() async {
    // Capture values early to avoid null issues after async gaps
    final transcriptionService = _transcriptionService;
    final startTime = _startTime;
    if (transcriptionService == null || startTime == null) return;

    _durationTimer?.cancel();

    setState(() {
      _isRecording = false;
      _isSaving = true; // Show saving state instead of empty state
    });

    // Register service with provider BEFORE stopping
    final activeRecording = ref.read(activeRecordingProvider.notifier);
    activeRecording.startSession(transcriptionService, startTime);

    // Stop recording (triggers final chunk, returns immediately)
    final audioPath = await activeRecording.stopRecording();

    // Get current transcript (partial, may not include final segment yet)
    final partialTranscript = transcriptionService.getCombinedText();

    // Save WAV file immediately
    await _saveWavFile(audioPath);

    // Start background monitoring so transcription continues even if screen is closed
    final fileSystem = ref.read(fileSystemServiceProvider);
    final capturesPath = await fileSystem.getCapturesPath();
    final timestamp = FileSystemService.formatTimestampForFilename(startTime);

    final backgroundService = ref.read(backgroundTranscriptionProvider);
    backgroundService.startMonitoring(
      service: transcriptionService,
      timestamp: timestamp,
      audioPath: audioPath ?? '',
      duration: _recordingDuration,
      capturesPath: capturesPath,
    );

    debugPrint(
      '[LiveRecording] 🔄 Background transcription monitoring started',
    );

    // Navigate to detail screen with partial transcript
    // Transcription continues in background via provider
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => RecordingDetailScreen.transcribing(
            timestamp: timestamp,
            audioPath: audioPath,
            initialTranscript: partialTranscript,
            duration: _recordingDuration,
          ),
        ),
      );
    }
  }

  Future<void> _saveWavFile(String? audioPath) async {
    if (audioPath == null) return;

    // Capture values before any async operations to avoid null issues
    final startTime = _startTime;
    final transcriptionService = _transcriptionService;
    if (startTime == null || transcriptionService == null) {
      debugPrint('[LiveRecording] ❌ Cannot save: missing startTime or transcriptionService');
      return;
    }

    try {
      final fileSystem = ref.read(fileSystemServiceProvider);
      final timestamp = FileSystemService.formatTimestampForFilename(
        startTime,
      );
      final capturesPath = await fileSystem.getCapturesPath();

      // Save WAV file
      if (await File(audioPath).exists()) {
        final audioDestPath = path.join(capturesPath, '$timestamp.wav');
        await File(audioPath).copy(audioDestPath);
        debugPrint('[LiveRecording] ✅ WAV file saved: $audioDestPath');
      }

      // Save placeholder .md file IMMEDIATELY so recording is visible
      // This will be updated when transcription completes
      final markdownPath = path.join(capturesPath, '$timestamp.md');
      final partialTranscript = transcriptionService.getCombinedText();

      final metadata = StringBuffer();
      metadata.writeln('---');
      metadata.writeln('title: Untitled Recording');
      metadata.writeln('created: ${startTime.toIso8601String()}');
      metadata.writeln('duration: ${_recordingDuration.inSeconds}');
      metadata.writeln(
        'words: ${partialTranscript.trim().isEmpty ? 0 : partialTranscript.trim().split(RegExp(r'\\s+')).length}',
      );
      metadata.writeln('source: live_recording');
      metadata.writeln('transcription_status: in_progress');
      metadata.writeln('---');
      metadata.writeln();
      metadata.writeln('# Untitled Recording');
      metadata.writeln();

      if (partialTranscript.isNotEmpty) {
        metadata.writeln('## Transcription');
        metadata.writeln();
        metadata.writeln(partialTranscript);
        metadata.writeln();
        metadata.writeln('_Transcription in progress..._');
      } else {
        metadata.writeln('_Transcribing audio..._');
      }

      await File(markdownPath).writeAsString(metadata.toString());
      debugPrint('[LiveRecording] ✅ Placeholder .md file saved: $markdownPath');

      // Trigger refresh so recording appears immediately in list
      if (mounted) {
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      }
    } catch (e) {
      debugPrint('[LiveRecording] ❌ Error saving files: $e');
    }
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isRecording || _isPaused) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_startTime != null) {
          _recordingDuration = DateTime.now().difference(_startTime!);
        }
      });
    });
  }

  String get _formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while initializing
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Getting ready...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing to listen...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: _buildBodyWithDebugOverlay(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () async {
          if (_isRecording) {
            final shouldExit = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Discard Note?'),
                content: const Text(
                  'Are you sure you want to discard this note?',
                ),
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

            if (shouldExit == true) {
              // Cancel immediately without processing
              if (_transcriptionService != null) {
                await _transcriptionService!.cancelRecording();
              }
              if (mounted) {
                Navigator.of(context).pop();
              }
            }
          } else {
            Navigator.of(context).pop();
          }
        },
      ),
      title: _buildSyncStatusIndicator(),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildSyncStatusIndicator() {
    // Show stream health warning if broken (overrides other indicators)
    if (!_streamHealthy && _isRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red),
          const SizedBox(width: 6),
          Text(
            'Microphone issue',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show auto-pause indicator (always enabled now)
        Icon(Icons.auto_awesome, size: 16, color: Colors.blue),
        const SizedBox(width: 4),
        Text('Auto-pause', style: TextStyle(fontSize: 14, color: Colors.blue)),

        // Speaker identification indicator (if enabled)
        if (_enableDiarization) ...[
          const SizedBox(width: 12),
          Icon(Icons.people, size: 16, color: Colors.purple),
          const SizedBox(width: 4),
          Text(
            'Speakers',
            style: TextStyle(fontSize: 14, color: Colors.purple),
          ),
        ],
      ],
    );
  }

  Widget _buildBodyWithDebugOverlay() {
    // Wrap body with debug overlay if enabled
    if (_showDebugOverlay && _transcriptionService != null) {
      return Stack(
        children: [
          _buildBody(),
          // Only show overlay while recording
          if (_isRecording)
            AudioDebugOverlay(
              metricsStream: _transcriptionService!.debugMetricsStream,
            ),
        ],
      );
    }

    return _buildBody();
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Content area with segments and inline status
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                // Add subtle border when listening
                border: _isRecording
                    ? Border.all(
                        color: _isPaused
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.blue.withValues(alpha: 0.4),
                        width: 2,
                      )
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: _buildContentList(),
            ),
          ),
        ),

        // Instruction text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildInstructionText(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Build the content list showing segments and current status inline
  Widget _buildContentList() {
    if (_segments.isEmpty && !_isRecording && !_isProcessing && !_isSaving) {
      // Empty state - warm, inviting (only show when truly idle)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Ready to listen',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start speaking your thoughts...',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // If saving, show the transcript that was just recorded
    if (_isSaving && _segments.isNotEmpty) {
      return ListView.builder(
        controller: _scrollController,
        itemCount: _segments.length,
        itemBuilder: (context, index) {
          final segment = _segments[index];
          if (segment.status == v3.TranscriptionSegmentStatus.completed) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                segment.text,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Colors.black87,
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount:
          _segments.length +
          (_isRecording && !_isPaused ? 1 : 0) +
          (_isPaused ? 1 : 0),
      itemBuilder: (context, index) {
        // Show all segments (completed, processing, pending)
        if (index < _segments.length) {
          final segment = _segments[index];

          // Show completed segments as text
          if (segment.status == v3.TranscriptionSegmentStatus.completed) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                segment.text,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            );
          }

          // Show processing segments with indicator
          if (segment.status == v3.TranscriptionSegmentStatus.processing) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildProcessingIndicator(segmentNumber: segment.index),
            );
          }

          // Show pending (queued) segments with indicator
          if (segment.status == v3.TranscriptionSegmentStatus.pending) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildQueuedIndicator(segmentNumber: segment.index),
            );
          }

          // Show failed segments with indicator
          if (segment.status == v3.TranscriptionSegmentStatus.failed) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildFailedIndicator(segmentNumber: segment.index),
            );
          }

          return const SizedBox.shrink();
        }

        // Show recording/paused indicator after all segments
        final statusIndex = index - _segments.length;

        if (statusIndex == 0) {
          if (_isPaused) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildPausedIndicator(),
            );
          } else if (_isRecording) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildRecordingIndicator(),
            );
          }
        }

        return const SizedBox.shrink();
      },
    );
  }

  /// Build processing status indicator
  Widget _buildProcessingIndicator({int? segmentNumber}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segmentNumber != null
                      ? 'Transcribing #$segmentNumber'
                      : 'Transcribing',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Transcribing audio...',
                  style: TextStyle(
                    color: Colors.orange.shade700.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build queued (pending) status indicator
  Widget _buildQueuedIndicator({required int segmentNumber}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.blue.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Segment #$segmentNumber queued',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Waiting to process...',
                  style: TextStyle(
                    color: Colors.blue.shade700.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build failed status indicator
  Widget _buildFailedIndicator({required int segmentNumber}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.red.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Segment #$segmentNumber failed',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Transcription error',
                  style: TextStyle(
                    color: Colors.red.shade700.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build paused status indicator
  Widget _buildPausedIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pause_circle_filled,
            color: Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paused',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ready when you are...',
                  style: TextStyle(
                    color: Colors.orange.shade700.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build recording status indicator
  Widget _buildRecordingIndicator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.blue.shade700.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listening',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedDuration,
                  style: TextStyle(
                    color: Colors.blue.shade700.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionText() {
    if (!_isRecording) {
      return Text(
        'Ready to record',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        textAlign: TextAlign.center,
      );
    } else if (_isPaused) {
      return Text(
        _isProcessing
            ? 'Processing your words...'
            : 'Tap Resume to continue or Edit to modify text',
        style: TextStyle(
          color: _isProcessing ? Colors.orange : Colors.blue,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    } else {
      return Text(
        'Speak your thoughts, then tap Pause',
        style: TextStyle(
          color: Colors.red.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: (_isRecording || _isSaving)
            ? _buildRecordingControls()
            : _buildIdleControls(),
      ),
    );
  }

  Widget _buildIdleControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Speaker identification toggle (iOS/macOS only)
        if (Platform.isIOS || Platform.isMacOS)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.people,
                  size: 20,
                  color: _enableDiarization
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Identify speakers',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ),
                Switch(
                  value: _enableDiarization,
                  onChanged: (value) {
                    setState(() => _enableDiarization = value);
                  },
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),

        // Start recording button
        ElevatedButton.icon(
          onPressed: _startRecording,
          icon: const Icon(Icons.mic, size: 28),
          label: const Text(
            'Start Listening',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      children: [
        // Pause/Resume button (disabled during save)
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _togglePause,
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
            label: Text(
              _isPaused ? 'Resume' : 'Pause',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPaused
                  ? Colors.green
                  : Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Stop & Save button (disabled during save to prevent double-click)
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _stopAndSave,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.save, size: 28),
            label: Text(
              _isSaving ? 'Saving...' : 'Save Note',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 3,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Keyboard/Edit button
        IconButton(
          icon: const Icon(Icons.edit),
          iconSize: 28,
          color: Theme.of(context).colorScheme.primary,
          onPressed: () {
            _textFocusNode.requestFocus();
          },
          tooltip: 'Edit text',
        ),
      ],
    );
  }
}
