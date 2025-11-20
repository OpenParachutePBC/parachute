import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:app/features/recorder/models/recording.dart';

import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/providers/model_download_provider.dart';
import 'package:app/features/recorder/services/live_transcription_service_v3.dart';
import 'package:app/features/recorder/services/background_transcription_service.dart';
import 'package:app/features/recorder/widgets/model_download_banner.dart';
import 'package:app/features/recorder/widgets/playback_controls.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/core/services/file_system_service.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/space_notes/screens/link_capture_to_space_screen.dart';
import 'package:app/features/spaces/providers/space_provider.dart';
import 'package:app/features/spaces/providers/space_knowledge_provider.dart';
import 'package:app/core/models/space.dart';

/// Unified recording detail screen with inline editing
/// Inspired by LiveRecordingScreen design - clean, focused, contextual status
class RecordingDetailScreen extends ConsumerStatefulWidget {
  // Existing mode: viewing a saved recording
  final Recording? recording;

  // New mode: viewing recording being transcribed
  final String? timestamp;
  final String? audioPath;
  final String? initialTranscript;
  final Duration? duration;
  final bool isTranscribing;

  // Constructor for viewing saved recording
  const RecordingDetailScreen({super.key, required this.recording})
    : timestamp = null,
      audioPath = null,
      initialTranscript = null,
      duration = null,
      isTranscribing = false;

  // Constructor for viewing recording being transcribed
  const RecordingDetailScreen.transcribing({
    super.key,
    required this.timestamp,
    required this.audioPath,
    required this.initialTranscript,
    required this.duration,
    this.isTranscribing = true,
  }) : recording = null;

  @override
  ConsumerState<RecordingDetailScreen> createState() =>
      _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen> {
  Recording? _recording; // Nullable now - might not exist yet if transcribing
  Timer? _refreshTimer;
  StreamSubscription? _transcriptionSubscription;
  BackgroundTranscriptionService?
  _backgroundServiceRef; // Store reference for cleanup

  // Controllers for inline editing
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _transcriptController = TextEditingController();
  final TextEditingController _contextController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Edit mode states
  bool _isTitleEditing = false;
  bool _isTranscriptEditing = false;
  bool _isContextEditing = false;

  // Processing states

  bool _isTranscribing = false;
  bool _isGeneratingTitle = false;
  double _transcriptionProgress = 0.0;
  String _transcriptionStatus = '';

  // Voice input for context
  bool _isRecordingContext = false;
  bool _isTranscribingContext = false;

  // Auto-retry flag
  bool _shouldAutoRetry = false;

  @override
  void initState() {
    super.initState();

    // Set up auto-retry for incomplete transcriptions
    _setupAutoRetry();

    if (widget.recording != null) {
      // Mode 1: Viewing saved recording
      _recording = widget.recording;
      _titleController.text = _recording!.title;
      _transcriptController.text = _recording!.transcript;
      _contextController.text = _recording!.context;

      // Check if background transcription is active for this recording
      final backgroundService = ref.read(backgroundTranscriptionProvider);
      _backgroundServiceRef = backgroundService;

      final recordingTimestamp = _recording!.id; // ID is the timestamp
      if (backgroundService.isMonitoring &&
          backgroundService.currentTimestamp == recordingTimestamp) {
        debugPrint(
          '[RecordingDetail] Background transcription active for this recording',
        );
        _isTranscribing = true;

        // Attach listeners to get updates
        backgroundService.addSegmentListener(_handleSegmentUpdate);
        backgroundService.addCompletionListener(_handleTranscriptionComplete);
      }

      _startPeriodicRefresh();
    } else {
      // Mode 2: Viewing recording being transcribed
      _isTranscribing = widget.isTranscribing;
      _titleController.text = 'Untitled Recording'; // Default title
      _transcriptController.text = widget.initialTranscript ?? '';
      _contextController.text = '';

      // Listen for transcription updates from provider
      _listenToTranscriptionUpdates();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _transcriptionSubscription?.cancel();

    // Remove listeners from background service using stored reference
    // IMPORTANT: Don't use ref.read() during dispose - causes "ref after dispose" error
    if (_backgroundServiceRef != null) {
      try {
        _backgroundServiceRef!.removeSegmentListener(_handleSegmentUpdate);
        _backgroundServiceRef!.removeCompletionListener(
          _handleTranscriptionComplete,
        );
        debugPrint(
          '[RecordingDetail] Removed listeners from background service',
        );
      } catch (e) {
        debugPrint('[RecordingDetail] Error removing listeners: $e');
      }
    }

    // Clear auto-retry callback
    try {
      final downloadNotifier = ref.read(modelDownloadProvider.notifier);
      downloadNotifier.onModelsReady = null;
    } catch (e) {
      debugPrint('[RecordingDetail] Error clearing auto-retry callback: $e');
    }

    _titleController.dispose();
    _transcriptController.dispose();
    _contextController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Set up auto-retry for incomplete transcriptions when models finish downloading
  void _setupAutoRetry() {
    // Check if this recording needs transcription
    final isIncomplete = _recording?.isTranscriptionIncomplete ?? false;
    final isProcessing =
        _recording?.transcriptionStatus == ProcessingStatus.processing;

    if (isIncomplete && !isProcessing) {
      debugPrint(
        '[RecordingDetail] Setting up auto-retry for incomplete transcription',
      );
      _shouldAutoRetry = true;

      // Register callback for when models are ready
      final downloadNotifier = ref.read(modelDownloadProvider.notifier);
      downloadNotifier.onModelsReady = _handleModelsReady;
    }
  }

  /// Called when models finish downloading - auto-retry transcription
  void _handleModelsReady() {
    if (!mounted || !_shouldAutoRetry) return;

    debugPrint(
      '[RecordingDetail] Models ready! Auto-retrying transcription...',
    );

    // Immediately start transcription
    if (_recording != null) {
      _transcribeRecording();
    }

    // Clear flag after starting
    setState(() {
      _shouldAutoRetry = false;
    });
  }

  /// Listen to transcription updates from the background service
  void _listenToTranscriptionUpdates() {
    final backgroundService = ref.read(backgroundTranscriptionProvider);

    // Store reference for cleanup in dispose()
    _backgroundServiceRef = backgroundService;

    // Check if background service is already monitoring this recording
    if (backgroundService.isMonitoring &&
        backgroundService.currentTimestamp == widget.timestamp) {
      debugPrint(
        '[RecordingDetail] Listening to background transcription updates',
      );

      // Add listeners to the background service
      backgroundService.addSegmentListener(_handleSegmentUpdate);
      backgroundService.addCompletionListener(_handleTranscriptionComplete);

      return;
    }

    // Fallback: Listen to active recording provider (for immediate transitions)
    final activeRecording = ref.read(activeRecordingProvider);
    final service = activeRecording.service;

    if (service == null) {
      debugPrint('[RecordingDetail] No active transcription service');
      return;
    }

    debugPrint(
      '[RecordingDetail] Listening to active service transcription updates',
    );

    // Listen to segment updates from active service
    _transcriptionSubscription = service.segmentStream.listen((segment) {
      if (!mounted) return;
      _handleSegmentUpdate(segment);
    });
  }

  void _handleSegmentUpdate(TranscriptionSegment segment) {
    if (!mounted) return;

    debugPrint(
      '[RecordingDetail] Segment update: ${segment.index} - ${segment.status}',
    );

    // Get segments from background service if available, otherwise from active service
    // Wrap in try-catch to handle disposal edge cases
    final List<TranscriptionSegment> allSegments;
    try {
      final backgroundService = ref.read(backgroundTranscriptionProvider);
      if (backgroundService.isMonitoring &&
          backgroundService.currentTimestamp == widget.timestamp) {
        allSegments = backgroundService.segments;
      } else {
        final activeRecording = ref.read(activeRecordingProvider);
        allSegments = activeRecording.service?.segments ?? [];
      }
    } catch (e) {
      debugPrint('[RecordingDetail] Error reading segments after dispose: $e');
      return;
    }

    // Update transcript with all completed segments
    final completedText = allSegments
        .where((s) => s.status == TranscriptionSegmentStatus.completed)
        .map((s) => s.text)
        .join('\n\n');

    if (!_isTranscriptEditing && mounted) {
      setState(() {
        _transcriptController.text = completedText;
      });
    }

    // Check if transcription is complete
    final hasIncomplete = allSegments.any(
      (s) =>
          s.status == TranscriptionSegmentStatus.pending ||
          s.status == TranscriptionSegmentStatus.processing,
    );

    if (!hasIncomplete && _isTranscribing && allSegments.isNotEmpty) {
      debugPrint('[RecordingDetail] Transcription complete in UI!');
      setState(() {
        _isTranscribing = false;
      });

      // Save the markdown file now that transcription is complete
      _saveCompletedRecording();
    }
  }

  void _handleTranscriptionComplete(bool success) {
    if (!mounted) return;

    debugPrint(
      '[RecordingDetail] Background transcription completed: $success',
    );

    if (success) {
      setState(() {
        _isTranscribing = false;
      });

      // Refresh the recording to show updated content
      _refreshRecording();
    }
  }

  Future<void> _refreshRecording() async {
    if (_recording == null) return;

    final updated = await ref
        .read(storageServiceProvider)
        .getRecording(_recording!.id);
    if (updated != null && mounted) {
      setState(() {
        _recording = updated;
        if (!_isTitleEditing) _titleController.text = _recording!.title;
        if (!_isTranscriptEditing)
          _transcriptController.text = _recording!.transcript;
        if (!_isContextEditing) _contextController.text = _recording!.context;
      });
    }
  }

  /// Save the completed recording (called when transcription finishes)
  /// Updates the existing placeholder .md file with complete transcription
  Future<void> _saveCompletedRecording() async {
    try {
      debugPrint(
        '[RecordingDetail] Updating recording with complete transcription...',
      );

      final fileSystemService = ref.read(fileSystemServiceProvider);
      final timestamp = widget.timestamp!;
      final capturesPath = await fileSystemService.getCapturesPath();
      final markdownPath = path.join(capturesPath, '$timestamp.md');

      // Read existing file to preserve created timestamp if it exists
      DateTime createdTime = DateTime.now();
      if (await File(markdownPath).exists()) {
        try {
          final existingContent = await File(markdownPath).readAsString();
          final lines = existingContent.split('\n');
          for (final line in lines) {
            if (line.startsWith('created:')) {
              final timeStr = line.substring('created:'.length).trim();
              createdTime = DateTime.tryParse(timeStr) ?? DateTime.now();
              break;
            }
          }
        } catch (e) {
          debugPrint(
            '[RecordingDetail] Could not read existing created time: $e',
          );
        }
      }

      // Create updated metadata
      final metadata = StringBuffer();
      metadata.writeln('---');
      metadata.writeln(
        'title: ${_titleController.text.trim().isNotEmpty ? _titleController.text.trim() : "Untitled Recording"}',
      );
      metadata.writeln('created: ${createdTime.toIso8601String()}');
      metadata.writeln('duration: ${widget.duration?.inSeconds ?? 0}');
      metadata.writeln(
        'words: ${_transcriptController.text.trim().isEmpty ? 0 : _transcriptController.text.trim().split(RegExp(r'\\s+')).length}',
      );
      metadata.writeln('source: live_recording');
      metadata.writeln('transcription_status: completed');
      metadata.writeln('---');
      metadata.writeln();

      // Add title
      metadata.writeln(
        '# ${_titleController.text.trim().isNotEmpty ? _titleController.text.trim() : "Untitled Recording"}',
      );
      metadata.writeln();

      // Add context if provided
      if (_contextController.text.trim().isNotEmpty) {
        metadata.writeln('## Context');
        metadata.writeln();
        metadata.writeln(_contextController.text.trim());
        metadata.writeln();
      }

      // Add transcription
      if (_transcriptController.text.trim().isNotEmpty) {
        metadata.writeln('## Transcription');
        metadata.writeln();
        metadata.writeln(_transcriptController.text.trim());
      }

      // Update markdown file (overwrites placeholder)
      await File(markdownPath).writeAsString(metadata.toString());

      debugPrint(
        '[RecordingDetail] ✅ Markdown updated with complete transcription: $markdownPath',
      );

      // Stop background monitoring since we've saved the transcription
      final backgroundService = ref.read(backgroundTranscriptionProvider);
      if (backgroundService.currentTimestamp == timestamp) {
        backgroundService.stopMonitoring();
        debugPrint(
          '[RecordingDetail] Stopped background monitoring after save',
        );
      }

      // Clean up the provider session
      ref.read(activeRecordingProvider.notifier).clearSession();

      // Trigger recordings list refresh
      ref.read(recordingsRefreshTriggerProvider.notifier).state++;
    } catch (e) {
      debugPrint('[RecordingDetail] ❌ Error saving recording: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _startPeriodicRefresh() {
    if (_recording == null) return; // Only for saved recordings

    // Only refresh while processing is happening
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_recording == null) return;

      final isProcessing =
          _recording!.transcriptionStatus == ProcessingStatus.pending ||
          _recording!.transcriptionStatus == ProcessingStatus.processing ||
          _recording!.titleGenerationStatus == ProcessingStatus.pending ||
          _recording!.titleGenerationStatus == ProcessingStatus.processing;

      if (!isProcessing) {
        _refreshTimer?.cancel();
        return;
      }

      // Fetch updated recording from storage
      final updated = await ref
          .read(storageServiceProvider)
          .getRecording(_recording!.id);
      if (updated != null && mounted) {
        setState(() {
          _recording = updated;
          // Update controllers if not currently editing
          if (!_isTitleEditing) _titleController.text = _recording!.title;
          if (!_isTranscriptEditing) {
            _transcriptController.text = _recording!.transcript;
          }
          if (!_isContextEditing) _contextController.text = _recording!.context;
        });
      }
    });
  }

  Future<void> _saveChanges() async {
    // For transcribing mode, save context to temporary state (will be included in final save)
    if (_recording == null) {
      setState(() {
        _isContextEditing = false;
        _isTitleEditing = false;
        _isTranscriptEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Context saved (will be included when recording finishes)',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // For saved recordings, update the file
    final updatedRecording = _recording!.copyWith(
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Untitled Recording',
      transcript: _transcriptController.text.trim(),
      context: _contextController.text.trim(),
      // Mark transcription as completed if transcript has content
      liveTranscriptionStatus: _transcriptController.text.trim().isNotEmpty
          ? 'completed'
          : _recording!.liveTranscriptionStatus,
    );

    final success = await ref
        .read(storageServiceProvider)
        .updateRecording(updatedRecording);

    if (success && mounted) {
      setState(() {
        _recording = updatedRecording;
        _isTitleEditing = false;
        _isTranscriptEditing = false;
        _isContextEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes saved'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// Reset a stuck transcription and retry
  Future<void> _resetAndRetryTranscription() async {
    if (_recording == null) return;

    // Reset the transcription status to pending
    final updatedRecording = _recording!.copyWith(
      transcriptionStatus: ProcessingStatus.pending,
      liveTranscriptionStatus: null,
    );

    // Save the updated status
    final storageService = ref.read(storageServiceProvider);
    final success = await storageService.updateRecording(updatedRecording);

    if (success && mounted) {
      setState(() {
        _recording = updatedRecording;
      });

      // Now start transcription
      await _transcribeRecording();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reset transcription status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _transcribeRecording() async {
    if (_isTranscribing || _recording == null) return;

    setState(() {
      _isTranscribing = true;
      _transcriptionProgress = 0.0;
      _transcriptionStatus = 'Starting...';
    });

    try {
      // Use Parakeet transcription
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );
      final transcriptResult = await transcriptionService.transcribeAudio(
        _recording!.filePath,
        language: 'auto',
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _transcriptionProgress = progress.progress;
              _transcriptionStatus = progress.status;
            });
          }
        },
      );

      if (mounted) {
        _transcriptController.text = transcriptResult.text;
        setState(() {
          _transcriptionProgress = 1.0;
          _transcriptionStatus = 'Complete!';
        });

        // Auto-generate title from transcript
        await _generateTitleFromTranscript(transcriptResult.text);

        // Auto-save after transcription
        await _saveChanges();

        // Reload recording from disk to get updated metadata (duration, etc.)
        await _refreshRecording();

        // Trigger home screen refresh to update recording list
        ref.read(recordingsRefreshTriggerProvider.notifier).state++;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _transcriptionProgress = 0.0;
          _transcriptionStatus = '';
        });
      }
    }
  }

  Future<void> _generateTitleFromTranscript(String transcript) async {
    if (transcript.isEmpty) return;

    setState(() {
      _isGeneratingTitle = true;
    });

    try {
      final titleService = ref.read(titleGenerationServiceProvider);
      final generatedTitle = await titleService.generateTitle(transcript);

      if (generatedTitle != null && generatedTitle.isNotEmpty && mounted) {
        setState(() {
          _titleController.text = generatedTitle;
        });
      }
    } catch (e) {
      debugPrint('[RecordingDetail] Title generation failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingTitle = false;
        });
      }
    }
  }

  void _linkToSpaces() async {
    if (_recording == null) return;

    String cleanNotePath = _recording!.filePath;
    if (cleanNotePath.startsWith('/api/')) {
      cleanNotePath = cleanNotePath.substring(5);
    }
    if (cleanNotePath.endsWith('.wav')) {
      cleanNotePath = cleanNotePath.replaceAll('.wav', '.md');
    }
    if (!cleanNotePath.startsWith('captures/')) {
      cleanNotePath = 'captures/$cleanNotePath';
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => LinkCaptureToSpaceScreen(
          captureId: _recording!.id,
          filename: _recording!.title,
          notePath: cleanNotePath,
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully linked to spaces')),
      );
    }
  }

  /// Re-transcribe the recording
  Future<void> _retranscribe() async {
    if (_recording == null) return;

    // Parakeet requires WAV files for transcription
    // Check if WAV file exists, if not check for Opus
    final wavPath = _recording!.filePath.replaceAll('.opus', '.wav');
    final wavFile = File(wavPath);
    final opusFile = File(_recording!.filePath);

    String audioPathToTranscribe;

    if (await wavFile.exists()) {
      // Use existing WAV file
      audioPathToTranscribe = wavPath;
      debugPrint('[RecordingDetail] Using WAV file for re-transcription');
    } else if (await opusFile.exists() &&
        _recording!.filePath.endsWith('.opus')) {
      // Opus file exists but no WAV - decode Opus to temporary WAV
      debugPrint(
        '[RecordingDetail] WAV not found, decoding Opus to temporary WAV',
      );

      try {
        audioPathToTranscribe = await _decodeOpusToWav(_recording!.filePath);
        debugPrint(
          '[RecordingDetail] Created temporary WAV at: $audioPathToTranscribe',
        );
      } catch (e) {
        debugPrint('[RecordingDetail] Failed to decode Opus to WAV: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to decode Opus file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } else {
      // Neither file exists
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio file not found. Cannot re-transcribe.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Start transcription
    setState(() {
      _isTranscribing = true;
      _transcriptionStatus = 'Re-transcribing...';
      _transcriptionProgress = 0.0;
    });

    try {
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );
      final result = await transcriptionService.transcribeAudio(
        audioPathToTranscribe,
      );

      if (mounted && result.text.isNotEmpty) {
        setState(() {
          _recording = _recording!.copyWith(
            transcript: result.text,
            transcriptionStatus: ProcessingStatus.completed,
          );
          _transcriptController.text = result.text;
          _isTranscribing = false;
          _transcriptionStatus = 'Re-transcription complete';
        });

        // Save updated recording
        await _saveChanges();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Re-transcription complete!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Transcription returned empty text');
      }
    } catch (e) {
      debugPrint('[RecordingDetail] Re-transcription error: $e');
      if (mounted) {
        setState(() {
          _isTranscribing = false;
          _transcriptionStatus = 'Re-transcription failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Re-transcription failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Clean up temporary WAV file if it was created from Opus
      if (audioPathToTranscribe.endsWith('.temp.wav')) {
        try {
          final tempFile = File(audioPathToTranscribe);
          if (await tempFile.exists()) {
            await tempFile.delete();
            debugPrint('[RecordingDetail] Deleted temporary WAV file');
          }
        } catch (e) {
          debugPrint('[RecordingDetail] Failed to delete temporary WAV: $e');
        }
      }
    }
  }

  /// Decode Opus file to temporary WAV file for transcription
  Future<String> _decodeOpusToWav(String opusPath) async {
    debugPrint('[RecordingDetail] Decoding Opus to WAV: $opusPath');

    try {
      // Use AudioCompressionServiceDart to decode Opus to WAV
      final compressionService = AudioCompressionServiceDart();
      final wavPath = await compressionService.decompressToWav(
        opusPath: opusPath,
      );

      debugPrint('[RecordingDetail] Created temporary WAV: $wavPath');
      return wavPath;
    } catch (e, stackTrace) {
      debugPrint('[RecordingDetail] Opus decode error: $e');
      debugPrint('[RecordingDetail] Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _confirmDelete() async {
    if (_recording == null) return;

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Recording'),
          content: const Text(
            'Are you sure you want to delete this recording? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true && mounted) {
      final success = await ref
          .read(storageServiceProvider)
          .deleteRecording(_recording!.id);
      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording deleted')));
      }
    }
  }

  /// Start recording voice input for context field
  Future<void> _startContextVoiceInput() async {
    final audioService = ref.read(audioServiceProvider);

    // Request permissions first
    final hasPermission = await audioService.requestPermissions();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isRecordingContext = true);

    // Start recording
    final success = await audioService.startRecording();
    if (!success && mounted) {
      setState(() => _isRecordingContext = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to start recording'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Stop recording and transcribe voice input for context
  Future<void> _stopContextVoiceInput() async {
    final audioService = ref.read(audioServiceProvider);

    setState(() => _isRecordingContext = false);

    // Stop recording and get the file path
    final recordingPath = await audioService.stopRecording();
    if (recordingPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save recording'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Transcribe the audio
    setState(() => _isTranscribingContext = true);

    try {
      // Use the transcription adapter which handles Parakeet/Whisper automatically
      final transcriptionService = ref.read(
        transcriptionServiceAdapterProvider,
      );

      final transcriptResult = await transcriptionService.transcribeAudio(
        recordingPath,
        language: 'auto',
      );

      // Append to context field (with a space if context already has content)
      if (mounted) {
        final currentContext = _contextController.text.trim();
        final newContext = currentContext.isEmpty
            ? transcriptResult.text
            : '$currentContext ${transcriptResult.text}';

        setState(() {
          _contextController.text = newContext;
        });
      }

      // Delete the temporary audio file
      try {
        await File(recordingPath).delete();
      } catch (e) {
        debugPrint('[RecordingDetail] Error deleting temp audio: $e');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTranscribingContext = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Model download banner (shows when downloading)
          const ModelDownloadBanner(),

          // Main content
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: _isTitleEditing
          ? TextField(
              controller: _titleController,
              autofocus: true,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter title...',
              ),
              onSubmitted: (_) => _saveChanges(),
            )
          : Text(_recording?.title ?? _titleController.text),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      actions: [
        if (_isTitleEditing || _isTranscriptEditing || _isContextEditing)
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveChanges,
            tooltip: 'Save',
          )
        else ...[
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => setState(() => _isTitleEditing = true),
            tooltip: 'Edit title',
          ),
          IconButton(
            icon: const Icon(Icons.link),
            onPressed: _linkToSpaces,
            tooltip: 'Link to Spaces',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 're-transcribe',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Re-transcribe'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 're-transcribe') _retranscribe();
              if (value == 'delete') _confirmDelete();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Playback section
          _buildPlaybackSection(),

          const SizedBox(height: 16),

          // Metadata
          _buildMetadataSection(),

          const SizedBox(height: 12),

          // Linked spaces indicator
          if (_recording != null) _buildLinkedSpacesIndicator(),

          const SizedBox(height: 24),

          // Main content container (like LiveRecordingScreen)
          _buildMainContentContainer(),

          const SizedBox(height: 24),

          // Context section
          _buildContextSection(),
        ],
      ),
    );
  }

  Widget _buildPlaybackSection() {
    final audioPath = widget.audioPath ?? _recording?.filePath;
    final duration = widget.duration ?? _recording?.duration ?? Duration.zero;

    if (audioPath == null || audioPath.isEmpty) {
      return const SizedBox.shrink();
    }

    return PlaybackControls(
      key: ValueKey(audioPath), // Each recording gets its own playback state
      filePath: audioPath,
      duration: duration,
    );
  }

  Widget _buildMetadataSection() {
    return Row(
      children: [
        Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          _recording?.timeAgo ?? 'Just now',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        const SizedBox(width: 16),
        Icon(Icons.folder, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          _recording?.source == RecordingSource.omiDevice ? 'Omi' : 'Phone',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildLinkedSpacesIndicator() {
    if (_recording == null) return const SizedBox.shrink();

    final spacesAsync = ref.watch(spaceListProvider);

    return spacesAsync.when(
      data: (allSpaces) {
        return FutureBuilder<List<Space>>(
          future: _getLinkedSpaces(allSpaces),
          builder: (context, snapshot) {
            final linkedSpaces = snapshot.data ?? [];

            if (linkedSpaces.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: linkedSpaces.map((space) {
                        return InkWell(
                          onTap: () {
                            // Navigate to space detail (optional)
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (space.icon?.isNotEmpty ?? false)
                                  Text(
                                    space.icon!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (space.icon?.isNotEmpty ?? false)
                                  const SizedBox(width: 4),
                                Text(
                                  space.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<List<Space>> _getLinkedSpaces(List<Space> allSpaces) async {
    if (_recording == null) return [];

    try {
      final fileSystemService = FileSystemService();
      final spacesPath = await fileSystemService.getSpacesPath();
      final knowledgeService = ref.read(spaceKnowledgeServiceProvider);

      final linkedSpaces = <Space>[];

      for (final space in allSpaces) {
        final spacePath = '$spacesPath/${space.path}';
        final isLinked = await knowledgeService.isCaptureLinked(
          spacePath: spacePath,
          captureId: _recording!.id,
        );

        if (isLinked) {
          linkedSpaces.add(space);
        }
      }

      return linkedSpaces;
    } catch (e) {
      debugPrint('[RecordingDetail] Error getting linked spaces: $e');
      return [];
    }
  }

  Widget _buildMainContentContainer() {
    // Check if transcription is incomplete or in progress
    final isIncomplete = _recording?.isTranscriptionIncomplete ?? false;
    final isProcessing =
        _recording?.transcriptionStatus == ProcessingStatus.processing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: _isTranscriptEditing
            ? Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
                width: 2,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Transcript',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  if ((_recording?.transcript.isNotEmpty ?? false) &&
                      !_isTranscriptEditing)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _recording?.transcript ?? ''),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transcript copied to clipboard'),
                          ),
                        );
                      },
                      tooltip: 'Copy',
                    ),
                  if ((_recording?.transcript.isEmpty ?? true) &&
                      !_isTranscribing &&
                      _recording != null)
                    ElevatedButton.icon(
                      onPressed: _transcribeRecording,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Transcribe'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  // Show retry button for failed transcriptions
                  if ((_recording?.transcriptionStatus ==
                          ProcessingStatus.failed) &&
                      !_isTranscribing &&
                      _recording != null)
                    ElevatedButton.icon(
                      onPressed: _transcribeRecording,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry Transcription'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  // Show "Complete Transcription" button only for interrupted (not processing)
                  if (isIncomplete && !isProcessing && !_isTranscribing)
                    ElevatedButton.icon(
                      onPressed: _transcribeRecording,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Complete Transcription'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Show warning for stuck processing state (not actually transcribing)
          if (isProcessing && !_isTranscribing)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.shade700.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Transcription appears stuck. The background process may have been interrupted.',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _resetAndRetryTranscription,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset & Retry Transcription'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

          // Warning for incomplete transcriptions (interrupted, not processing)
          if (isIncomplete && !isProcessing && !_isTranscribing)
            Consumer(
              builder: (context, ref, child) {
                final downloadState = ref.watch(modelDownloadProvider);
                final isDownloadingModels = downloadState.isDownloading;
                final isAutoRetrying = _shouldAutoRetry;

                // Don't show "interrupted" message if auto-retry is pending or models are downloading
                if (isDownloadingModels || isAutoRetrying) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                        Icon(
                          Icons.download,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Downloading transcription models... Transcription will start automatically when ready.',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Show interrupted message with manual retry button
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                        Icons.warning_amber,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Transcription was interrupted. Tap "Complete Transcription" to finish.',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Inline status indicators (like LiveRecordingScreen)
          if (_isGeneratingTitle) _buildTitleGeneratingIndicator(),
          if (_isTranscribing) _buildTranscribingIndicator(),

          // Content
          if ((_recording?.transcript.isEmpty ??
                  _transcriptController.text.isEmpty) &&
              !_isTranscribing)
            Text(
              'No transcript yet. Tap "Transcribe" to generate.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (_isTranscriptEditing)
            TextField(
              controller: _transcriptController,
              maxLines: null,
              autofocus: true,
              style: const TextStyle(fontSize: 16, height: 1.5),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Enter transcript...',
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _isTranscriptEditing = true),
              child: Text(
                _transcriptController.text.isNotEmpty
                    ? _transcriptController.text
                    : 'Tap to add transcript',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: _transcriptController.text.isEmpty
                      ? Colors.grey.shade600
                      : null,
                  fontStyle: _transcriptController.text.isEmpty
                      ? FontStyle.italic
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTitleGeneratingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Generating title',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscribingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Icon(Icons.sync, color: Colors.orange.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transcribing audio',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _transcriptionStatus.isEmpty
                      ? 'Please wait...'
                      : '$_transcriptionStatus ${(_transcriptionProgress * 100).toStringAsFixed(0)}%',
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

  Widget _buildContextSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Context',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            // Voice input button
            if (!_isRecordingContext && !_isTranscribingContext)
              IconButton(
                icon: Icon(
                  Icons.mic,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _startContextVoiceInput,
                tooltip: 'Add context by voice',
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Show recording/transcribing indicator
        if (_isRecordingContext) _buildRecordingContextIndicator(),
        if (_isTranscribingContext) _buildTranscribingContextIndicator(),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: _isContextEditing
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    width: 2,
                  )
                : null,
          ),
          child: _isContextEditing
              ? TextField(
                  controller: _contextController,
                  maxLines: 3,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Add context, notes, or tags...',
                  ),
                )
              : GestureDetector(
                  onTap: () => setState(() => _isContextEditing = true),
                  child: Text(
                    _contextController.text.isNotEmpty
                        ? _contextController.text
                        : 'Tap to add context, notes, or tags...',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: _contextController.text.isEmpty
                          ? Colors.grey.shade600
                          : null,
                      fontStyle: _contextController.text.isEmpty
                          ? FontStyle.italic
                          : null,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRecordingContextIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
          Icon(Icons.mic, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Recording context...',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _stopContextVoiceInput,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscribingContextIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.orange.shade700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Transcribing voice input...',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    // Show save button if editing
    if (_isTitleEditing || _isTranscriptEditing || _isContextEditing) {
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
          child: ElevatedButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.check),
            label: const Text('Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
