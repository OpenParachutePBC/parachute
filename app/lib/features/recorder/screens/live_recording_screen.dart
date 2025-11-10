import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/services/live_transcription_service_v2.dart'
    as v2;
import 'package:app/features/recorder/services/live_transcription_service_v3.dart'
    as v3;
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/widgets/audio_debug_overlay.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/core/providers/git_sync_provider.dart';
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
  dynamic
  _transcriptionService; // SimpleTranscriptionService OR AutoPauseTranscriptionService
  bool _useAutoPause = false; // Determined at init time
  bool _showDebugOverlay = false; // Determined at init time
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();

  // State
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isProcessing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;
  int _wordCount = 0;

  // Segments (using dynamic type to support both v2 and v3)
  final List<dynamic> _segments = [];

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
    _transcriptionService.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeService() async {
    try {
      final whisperService = ref.read(whisperLocalServiceProvider);
      final storageService = ref.read(storageServiceProvider);

      // Check if auto-pause is enabled
      _useAutoPause = await storageService.getAutoPauseRecording();

      // Check if debug overlay is enabled
      _showDebugOverlay = await storageService.getAudioDebugOverlay();

      // Initialize appropriate service
      if (_useAutoPause) {
        debugPrint('[LiveRecordingScreen] Using AUTO-PAUSE mode (V3)');
        _transcriptionService = v3.AutoPauseTranscriptionService(
          whisperService,
        );
      } else {
        debugPrint('[LiveRecordingScreen] Using MANUAL mode (V2)');
        _transcriptionService = v2.SimpleTranscriptionService(whisperService);
      }

      await _transcriptionService.initialize();

      // Listen to segment updates
      _transcriptionService.segmentStream.listen(_handleSegmentUpdate);

      // Listen to processing state
      _transcriptionService.isProcessingStream.listen((isProcessing) {
        if (mounted) {
          setState(() {
            _isProcessing = isProcessing;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }

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

  void _handleSegmentUpdate(dynamic segment) {
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
    if (segment.status.toString().contains('completed')) {
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  void _updateTextController() {
    final completedText = _segments
        .where((s) => s.status.toString().contains('completed'))
        .map((s) => s.text)
        .join('\n\n');

    if (_textController.text != completedText) {
      _textController.text = completedText;
    }

    // Update word count
    _wordCount = completedText.trim().isEmpty
        ? 0
        : completedText.trim().split(RegExp(r'\s+')).length;
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
    final success = await _transcriptionService.startRecording();
    if (success) {
      setState(() {
        _isRecording = true;
        _isPaused = false;
        _startTime = DateTime.now();
      });
      _startDurationTimer();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start listening. Check permissions.'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      await _transcriptionService.resumeRecording();
      setState(() {
        _isPaused = false;
      });
      _startDurationTimer();
    } else {
      _durationTimer?.cancel();
      await _transcriptionService.pauseRecording();
      setState(() {
        _isPaused = true;
      });
    }
  }

  Future<void> _stopAndSave() async {
    _durationTimer?.cancel();

    setState(() {
      _isRecording = false;
    });

    // Show "Finishing transcription..." feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Finishing transcription and saving...'),
            ],
          ),
          duration: Duration(seconds: 30), // Long duration for processing
        ),
      );
    }

    // Stop recording (this will process any remaining audio and wait for completion)
    final audioPath = await _transcriptionService.stopRecording();

    // Dismiss the processing snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
    }

    // Save recording
    await _saveRecording(audioPath);
  }

  Future<void> _saveRecording(String? audioPath) async {
    try {
      // Get file system service
      final fileSystem = ref.read(fileSystemServiceProvider);

      // Generate timestamp and filenames
      final now = DateTime.now();
      final timestamp = FileSystemService.formatTimestampForFilename(now);

      final fullTranscript = _transcriptionService.getCombinedText();

      // Get captures folder path
      final capturesPath = await fileSystem.getCapturesPath();

      // Create markdown file
      final markdownPath = path.join(capturesPath, '$timestamp.md');
      final markdownFile = File(markdownPath);

      // Create metadata section
      final metadata = StringBuffer();
      metadata.writeln('---');
      metadata.writeln('created: ${now.toIso8601String()}');
      metadata.writeln('duration: $_formattedDuration');
      metadata.writeln('words: $_wordCount');
      metadata.writeln('source: live_recording');
      metadata.writeln('---');
      metadata.writeln();

      // Write markdown file
      await markdownFile.writeAsString('${metadata.toString()}$fullTranscript');

      // Copy audio file to captures folder if it exists
      if (audioPath != null && await File(audioPath).exists()) {
        final audioDestPath = path.join(capturesPath, '$timestamp.wav');
        await File(audioPath).copy(audioDestPath);
      }

      // Trigger Git sync if enabled (async, don't wait for it)
      debugPrint('[LiveRecording] 🔄 Attempting to trigger auto-sync...');
      _triggerAutoSync();

      if (mounted) {
        // Navigate immediately - don't wait for transcription
        Navigator.of(context).pop();

        // Show subtle notification that note is saved
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Note saved!\n$timestamp${_isProcessing ? ' (transcribing in background...)' : '\n$_wordCount words'}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save note: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Trigger Git sync in the background (don't block UI)
  void _triggerAutoSync() {
    debugPrint('[LiveRecording] 🔍 _triggerAutoSync called');

    Future.delayed(Duration.zero, () async {
      try {
        debugPrint('[LiveRecording] 📡 Reading git sync state...');

        final gitSync = ref.read(gitSyncProvider.notifier);
        final gitSyncState = ref.read(gitSyncProvider);

        debugPrint('[LiveRecording] Git sync state:');
        debugPrint('  - isEnabled: ${gitSyncState.isEnabled}');
        debugPrint('  - isSyncing: ${gitSyncState.isSyncing}');
        debugPrint('  - hasRemote: ${gitSyncState.hasRemote}');
        debugPrint('  - repositoryUrl: ${gitSyncState.repositoryUrl}');

        if (!gitSyncState.isEnabled) {
          debugPrint(
            '[LiveRecording] ⚠️  Git sync is NOT enabled, skipping auto-sync',
          );
          return;
        }

        if (gitSyncState.isSyncing) {
          debugPrint(
            '[LiveRecording] ⚠️  Git sync already in progress, skipping',
          );
          return;
        }

        debugPrint(
          '[LiveRecording] 🚀 Triggering auto-sync after recording save',
        );
        final success = await gitSync.sync();

        if (success) {
          debugPrint('[LiveRecording] ✅ Auto-sync completed successfully');
        } else {
          debugPrint('[LiveRecording] ❌ Auto-sync failed');
        }
      } catch (e, stackTrace) {
        debugPrint('[LiveRecording] ❌ Auto-sync error: $e');
        debugPrint('[LiveRecording] Stack trace: $stackTrace');
      }
    });
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
              await _transcriptionService.cancelRecording();
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show auto-pause indicator if enabled
        if (_useAutoPause) ...[
          Icon(Icons.auto_awesome, size: 16, color: Colors.blue),
          const SizedBox(width: 4),
          Text(
            'Auto-pause',
            style: TextStyle(fontSize: 14, color: Colors.blue),
          ),
          const SizedBox(width: 12),
        ],
        // Git sync status
        Icon(Icons.cloud_done, size: 16, color: Colors.green),
        const SizedBox(width: 4),
        Text('Synced', style: TextStyle(fontSize: 14, color: Colors.green)),
      ],
    );
  }

  Widget _buildBodyWithDebugOverlay() {
    // Wrap body with debug overlay if enabled and using auto-pause (V3)
    if (_showDebugOverlay &&
        _useAutoPause &&
        _transcriptionService is v3.AutoPauseTranscriptionService) {
      return Stack(
        children: [
          _buildBody(),
          // Only show overlay while recording
          if (_isRecording)
            AudioDebugOverlay(
              metricsStream:
                  (_transcriptionService as v3.AutoPauseTranscriptionService)
                      .debugMetricsStream,
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
    if (_segments.isEmpty && !_isRecording && !_isProcessing) {
      // Empty state - warm, inviting
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
          if (segment.status.toString().contains('completed')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                segment.text,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            );
          }

          // Show processing segments with indicator
          if (segment.status.toString().contains('processing')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildProcessingIndicator(segmentNumber: segment.index),
            );
          }

          // Show pending (queued) segments with indicator
          if (segment.status.toString().contains('pending')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: _buildQueuedIndicator(segmentNumber: segment.index),
            );
          }

          // Show failed segments with indicator
          if (segment.status.toString().contains('failed')) {
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
        child: _isRecording ? _buildRecordingControls() : _buildIdleControls(),
      ),
    );
  }

  Widget _buildIdleControls() {
    return ElevatedButton.icon(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      children: [
        // Pause/Resume button (always available)
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _togglePause,
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

        // Stop & Save button (prominent, single action)
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: _stopAndSave, // Single action to finish
            icon: const Icon(Icons.save, size: 28),
            label: const Text(
              'Save Note',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
