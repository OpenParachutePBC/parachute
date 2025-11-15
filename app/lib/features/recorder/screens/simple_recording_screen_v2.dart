import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:path/path.dart' as path;

/// Beautiful, simple recording screen
///
/// A warm, human recording experience with:
/// - Clean visual hierarchy
/// - Subtle animations and feedback
/// - Thoughtful instruction text
/// - Optional speaker identification
class SimpleRecordingScreen extends ConsumerStatefulWidget {
  const SimpleRecordingScreen({super.key});

  @override
  ConsumerState<SimpleRecordingScreen> createState() =>
      _SimpleRecordingScreenState();
}

class _SimpleRecordingScreenState extends ConsumerState<SimpleRecordingScreen>
    with SingleTickerProviderStateMixin {
  // State
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSaving = false;
  bool _enableDiarization = false;

  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _durationTimer?.cancel();
    _stopRecordingService();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final audioService = ref.read(audioServiceProvider);

      _startTime = DateTime.now();
      final success = await audioService.startRecording();

      if (success) {
        setState(() {
          _isRecording = true;
          _isPaused = false;
          _recordingDuration = Duration.zero;
        });

        _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted && !_isPaused) {
            setState(() {
              _recordingDuration = Duration(
                seconds: _recordingDuration.inSeconds + 1,
              );
            });
          }
        });

        debugPrint('[SimpleRecording] 🎙️ Recording started');
      }
    } catch (e) {
      debugPrint('[SimpleRecording] ❌ Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _togglePause() async {
    final audioService = ref.read(audioServiceProvider);

    if (_isPaused) {
      await audioService.resumeRecording();
      setState(() => _isPaused = false);
      debugPrint('[SimpleRecording] ▶️ Recording resumed');
    } else {
      await audioService.pauseRecording();
      setState(() => _isPaused = true);
      debugPrint('[SimpleRecording] ⏸️ Recording paused');
    }
  }

  Future<void> _stopAndSave() async {
    if (_startTime == null) return;

    setState(() => _isSaving = true);
    _durationTimer?.cancel();

    try {
      final audioService = ref.read(audioServiceProvider);
      final processingService = ref.read(recordingPostProcessingProvider);
      final storageService = ref.read(storageServiceProvider);
      final fileSystem = ref.read(fileSystemServiceProvider);

      // Step 1: Stop recording
      final audioPath = await audioService.stopRecording();
      if (audioPath == null || !await File(audioPath).exists()) {
        throw Exception('Failed to save audio file');
      }

      // Step 2: Save audio file
      final timestamp = FileSystemService.formatTimestampForFilename(
        _startTime!,
      );
      final capturesPath = await fileSystem.getCapturesPath();
      final audioDestPath = path.join(capturesPath, '$timestamp.wav');
      await File(audioPath).copy(audioDestPath);

      // Step 3: Process (transcribe + optional diarization)
      final result = await processingService.process(
        audioPath: audioDestPath,
        enableDiarization: _enableDiarization,
        onProgress: (status, progress) {
          debugPrint('[SimpleRecording] $status ($progress)');
        },
      );

      // Step 4: Create and save recording
      final recording = Recording(
        id: timestamp,
        title: 'Untitled Recording',
        filePath: audioDestPath,
        timestamp: _startTime!,
        duration: _recordingDuration,
        tags: [],
        transcript: result.transcript,
        context: '',
        fileSizeKB: await File(audioDestPath).length() / 1024,
        source: RecordingSource.phone,
        speakerSegments: result.speakerSegments,
        transcriptionStatus: ProcessingStatus.completed,
        titleGenerationStatus: ProcessingStatus.pending,
        liveTranscriptionStatus: 'completed',
      );

      await storageService.saveRecording(recording);
      ref.read(recordingsRefreshTriggerProvider.notifier).state++;

      debugPrint(
        '[SimpleRecording] ✅ Complete! ${result.speakerSegments?.length ?? 0} speakers',
      );

      // Navigate to detail screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RecordingDetailScreen(recording: recording),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('[SimpleRecording] ❌ Error: $e\n$stack');

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _stopRecordingService() async {
    if (_isRecording) {
      final audioService = ref.read(audioServiceProvider);
      await audioService.stopRecording();
    }
  }

  Future<void> _confirmDiscard() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard Recording?'),
        content: const Text('Are you sure you want to discard this recording?'),
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

    if (shouldDiscard == true && mounted) {
      await _stopRecordingService();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _isRecording
            ? _confirmDiscard
            : () => Navigator.of(context).pop(),
      ),
      title: _buildStatusIndicator(),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
    );
  }

  Widget _buildStatusIndicator() {
    if (_isSaving) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Processing...',
            style: TextStyle(fontSize: 14, color: Colors.blue.shade700),
          ),
        ],
      );
    }

    if (_isRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fiber_manual_record,
            size: 14,
            color: _isPaused ? Colors.orange.shade700 : Colors.red.shade600,
          ),
          const SizedBox(width: 6),
          Text(
            _isPaused ? 'Paused' : 'Recording',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _isPaused ? Colors.orange.shade700 : Colors.red.shade700,
            ),
          ),
          if (_enableDiarization) ...[
            const SizedBox(width: 10),
            Icon(Icons.people, size: 14, color: Colors.purple.shade600),
          ],
        ],
      );
    }

    return const Text('');
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Main content area
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: _isRecording
                    ? Border.all(
                        color: _isPaused
                            ? Colors.orange.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3),
                        width: 2,
                      )
                    : null,
              ),
              padding: const EdgeInsets.all(24),
              child: _buildContentArea(),
            ),
          ),
        ),

        // Instruction text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _buildInstructionText(),
        ),
      ],
    );
  }

  Widget _buildContentArea() {
    if (_isSaving) {
      return _buildSavingState();
    }

    if (_isRecording) {
      return _buildRecordingState();
    }

    return _buildIdleState();
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          Text(
            'Ready to record',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to start',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated recording indicator
          if (!_isPaused)
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade50,
                  border: Border.all(
                    color: Colors.red.shade600.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
                child: Icon(Icons.mic, size: 40, color: Colors.red.shade600),
              ),
            )
          else
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.shade50,
                border: Border.all(
                  color: Colors.orange.shade600.withValues(alpha: 0.5),
                  width: 3,
                ),
              ),
              child: Icon(Icons.pause, size: 40, color: Colors.orange.shade700),
            ),

          const SizedBox(height: 32),

          // Duration
          Text(
            _formatDuration(_recordingDuration),
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: _isPaused ? Colors.orange.shade700 : Colors.black87,
            ),
          ),

          const SizedBox(height: 12),

          // Status
          Text(
            _isPaused ? 'Paused' : 'Recording...',
            style: TextStyle(
              fontSize: 18,
              color: _isPaused ? Colors.orange.shade600 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),

          // Speaker indicator
          if (_enableDiarization) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.shade200, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people, size: 16, color: Colors.purple.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Identifying speakers',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.purple.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSavingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Processing recording...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _enableDiarization
                ? 'Transcribing and identifying speakers'
                : 'Transcribing audio',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'This is fast! ⚡',
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionText() {
    if (_isSaving) {
      return const SizedBox.shrink();
    }

    if (!_isRecording) {
      return Text(
        _enableDiarization
            ? 'Speaker identification is enabled for this recording'
            : 'Perfect for voice notes, ideas, and quick thoughts',
        style: TextStyle(
          color: _enableDiarization
              ? Colors.purple.shade600
              : Colors.grey.shade600,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      );
    }

    if (_isPaused) {
      return Text(
        'Tap Resume to continue, or Save to finish',
        style: TextStyle(
          color: Colors.orange.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      'Speak naturally, pause anytime',
      style: TextStyle(
        color: Colors.red.shade700,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Speaker identification toggle (iOS/macOS only)
        if (Platform.isIOS || Platform.isMacOS)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _enableDiarization
                  ? Colors.purple.shade50
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _enableDiarization
                    ? Colors.purple.shade200
                    : Colors.grey.shade200,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _enableDiarization
                        ? Colors.purple.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.people,
                    size: 20,
                    color: _enableDiarization
                        ? Colors.purple.shade700
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Identify speakers',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'For meetings & conversations',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enableDiarization,
                  onChanged: (value) {
                    setState(() => _enableDiarization = value);
                  },
                  activeColor: Colors.purple.shade600,
                ),
              ],
            ),
          ),

        // Start recording button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.fiber_manual_record, size: 24),
                SizedBox(width: 12),
                Text(
                  'Start Recording',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingControls() {
    return Row(
      children: [
        // Pause/Resume
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _togglePause,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPaused
                  ? Colors.green.shade600
                  : Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 24),
                const SizedBox(width: 8),
                Text(
                  _isPaused ? 'Resume' : 'Pause',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Save
        Expanded(
          flex: 3,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _stopAndSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              disabledBackgroundColor: Colors.blue.shade300,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSaving)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.check_circle, size: 24),
                const SizedBox(width: 8),
                Text(
                  _isSaving ? 'Processing...' : 'Save',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
