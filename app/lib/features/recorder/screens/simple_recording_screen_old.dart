import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/screens/recording_detail_screen.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/core/providers/git_sync_provider.dart';
import 'package:path/path.dart' as path;

/// Simple recording screen with manual pause/resume
///
/// User flow:
/// 1. Optional: Toggle "Identify Speakers" for meetings/conversations
/// 2. Tap "Start Recording" → Speak your thoughts
/// 3. Tap "Pause" when you need a break
/// 4. Tap "Save" → Automatic transcription + optional speaker diarization
///
/// Fast transcription with Parakeet v3 - processes 1 hour in ~19 seconds!
class SimpleRecordingScreen extends ConsumerStatefulWidget {
  const SimpleRecordingScreen({super.key});

  @override
  ConsumerState<SimpleRecordingScreen> createState() =>
      _SimpleRecordingScreenState();
}

class _SimpleRecordingScreenState extends ConsumerState<SimpleRecordingScreen> {
  // State
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSaving = false;
  bool _enableDiarization = false; // Toggle for speaker identification

  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  DateTime? _startTime;
  String? _audioPath;

  @override
  void dispose() {
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

        // Start duration timer
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
      // Resume
      await audioService.resumeRecording();
      setState(() => _isPaused = false);
      debugPrint('[SimpleRecording] ▶️ Recording resumed');
    } else {
      // Pause
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

      // Step 1: Stop recording and get audio path
      debugPrint('[SimpleRecording] Step 1: Stopping recording...');
      final audioPath = await audioService.stopRecording();
      if (audioPath == null || !await File(audioPath).exists()) {
        throw Exception('Failed to save audio file');
      }

      // Step 2: Save audio file to captures folder
      final timestamp = FileSystemService.formatTimestampForFilename(
        _startTime!,
      );
      final capturesPath = await fileSystem.getCapturesPath();
      final audioDestPath = path.join(capturesPath, '$timestamp.wav');
      await File(audioPath).copy(audioDestPath);
      debugPrint('[SimpleRecording] ✅ Audio saved: $audioDestPath');

      // Step 3: Run unified post-processing pipeline
      debugPrint(
        '[SimpleRecording] Step 2: Processing (diarization: $_enableDiarization)...',
      );

      String processingStatus = 'Transcribing...';
      setState(() {}); // Update UI with status

      final result = await processingService.process(
        audioPath: audioDestPath,
        enableDiarization: _enableDiarization,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() => processingStatus = status);
          }
          debugPrint('[SimpleRecording] Progress: $status ($progress)');
        },
      );

      debugPrint('[SimpleRecording] ✅ Processing complete');
      debugPrint(
        '[SimpleRecording]   - Transcript: ${result.transcript.length} chars',
      );
      debugPrint(
        '[SimpleRecording]   - Speakers: ${result.speakerSegments?.length ?? 0}',
      );

      // Step 4: Create recording object
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

      // Step 5: Save recording
      await storageService.saveRecording(recording);
      debugPrint('[SimpleRecording] ✅ Recording saved: ${recording.id}');

      // Step 6: Trigger UI refresh
      ref.read(recordingsRefreshTriggerProvider.notifier).state++;

      // Step 7: Navigate to detail screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RecordingDetailScreen(recording: recording),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('[SimpleRecording] ❌ Error saving: $e');
      debugPrint('[SimpleRecording] Stack: $stack');

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save recording: $e'),
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
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Processing...', style: TextStyle(fontSize: 14)),
        ],
      );
    }

    if (_isRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fiber_manual_record,
            size: 16,
            color: _isPaused ? Colors.orange : Colors.red,
          ),
          const SizedBox(width: 6),
          Text(
            _isPaused ? 'Paused' : 'Recording',
            style: TextStyle(
              fontSize: 14,
              color: _isPaused ? Colors.orange : Colors.red,
            ),
          ),
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

    return Text('New Recording', style: TextStyle(fontSize: 16));
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Recording duration display
          if (_isRecording) ...[
            Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isPaused ? 'Paused' : 'Recording...',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ] else if (_isSaving) ...[
            SizedBox(
              width: 80,
              height: 80,
              child: CircularProgressIndicator(strokeWidth: 6),
            ),
            const SizedBox(height: 24),
            Text(
              'Processing recording...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              _enableDiarization
                  ? 'Transcribing and identifying speakers'
                  : 'Transcribing audio',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ] else ...[
            Icon(Icons.mic_none, size: 120, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              'Ready to record',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
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
                    'Identify speakers (for meetings/conversations)',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ),
                Switch(
                  value: _enableDiarization,
                  onChanged: (value) {
                    setState(() => _enableDiarization = value);
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),

        // Start recording button
        ElevatedButton.icon(
          onPressed: _startRecording,
          icon: const Icon(Icons.mic, size: 28),
          label: const Text(
            'Start Recording',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
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
        // Pause/Resume button
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

        // Save button
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
                : const Icon(Icons.check, size: 24),
            label: Text(
              _isSaving ? 'Processing...' : 'Save',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
