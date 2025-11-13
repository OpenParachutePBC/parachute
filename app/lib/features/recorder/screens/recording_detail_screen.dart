import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/services/whisper_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/services/live_transcription_service_v3.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/core/services/file_system_service.dart';
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
  bool _isPlaying = false;
  bool _isTranscribing = false;
  bool _isGeneratingTitle = false;
  double _transcriptionProgress = 0.0;
  String _transcriptionStatus = '';

  // Voice input for context
  bool _isRecordingContext = false;
  bool _isTranscribingContext = false;

  @override
  void initState() {
    super.initState();

    if (widget.recording != null) {
      // Mode 1: Viewing saved recording
      _recording = widget.recording;
      _titleController.text = _recording!.title;
      _transcriptController.text = _recording!.transcript;
      _contextController.text = _recording!.context;
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

    // Remove listeners from background service
    final backgroundService = ref.read(backgroundTranscriptionProvider);
    backgroundService.removeSegmentListener(_handleSegmentUpdate);
    backgroundService.removeCompletionListener(_handleTranscriptionComplete);

    _titleController.dispose();
    _transcriptController.dispose();
    _contextController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Listen to transcription updates from the background service
  void _listenToTranscriptionUpdates() {
    final backgroundService = ref.read(backgroundTranscriptionProvider);

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
    final backgroundService = ref.read(backgroundTranscriptionProvider);
    final List<TranscriptionSegment> allSegments;

    if (backgroundService.isMonitoring &&
        backgroundService.currentTimestamp == widget.timestamp) {
      allSegments = backgroundService.segments;
    } else {
      final activeRecording = ref.read(activeRecordingProvider);
      allSegments = activeRecording.service?.segments ?? [];
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

  Future<void> _togglePlayback() async {
    // Use audioPath for transcribing mode, filePath for saved recording
    final audioPath = widget.audioPath ?? _recording?.filePath;
    final duration = widget.duration ?? _recording?.duration ?? Duration.zero;

    if (audioPath == null) return;

    if (_isPlaying) {
      await ref.read(audioServiceProvider).stopPlayback();
      setState(() => _isPlaying = false);
    } else {
      final success = await ref
          .read(audioServiceProvider)
          .playRecording(audioPath);
      if (success) {
        setState(() => _isPlaying = true);
        Future.delayed(duration, () {
          if (mounted && _isPlaying) {
            setState(() => _isPlaying = false);
          }
        });
      }
    }
  }

  Future<void> _transcribeRecording() async {
    if (_isTranscribing || _recording == null) return;

    final storageService = ref.read(storageServiceProvider);
    final modeString = await storageService.getTranscriptionMode();
    final mode =
        TranscriptionMode.fromString(modeString) ?? TranscriptionMode.api;

    setState(() {
      _isTranscribing = true;
      _transcriptionProgress = 0.0;
      _transcriptionStatus = 'Starting...';
    });

    try {
      String transcript;

      if (mode == TranscriptionMode.local) {
        transcript = await _transcribeWithLocal();
      } else {
        transcript = await _transcribeWithAPI();
      }

      if (mounted) {
        _transcriptController.text = transcript;
        setState(() {
          _transcriptionProgress = 1.0;
          _transcriptionStatus = 'Complete!';
        });

        // Auto-generate title from transcript
        await _generateTitleFromTranscript(transcript);

        // Auto-save after transcription
        await _saveChanges();
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

  Future<String> _transcribeWithLocal() async {
    final localService = ref.read(whisperLocalServiceProvider);

    final isReady = await localService.isReady();
    if (!isReady) {
      if (!mounted) throw WhisperLocalException('Not mounted');

      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Model Required'),
          content: const Text(
            'To use local transcription, you need to download a Whisper model in Settings.\n\n'
            'Would you like to go to Settings now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      );

      if (goToSettings == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      }
      throw WhisperLocalException('Model not downloaded');
    }

    return await localService.transcribeAudio(
      _recording!.filePath,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _transcriptionProgress = progress.progress;
            _transcriptionStatus = progress.status;
          });
        }
      },
    );
  }

  Future<String> _transcribeWithAPI() async {
    final isConfigured = await ref.read(whisperServiceProvider).isConfigured();
    if (!isConfigured) {
      if (!mounted) throw WhisperException('Not mounted');

      final goToSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('API Key Required'),
          content: const Text(
            'To use transcription, you need to configure your OpenAI API key in Settings.\n\n'
            'Would you like to go to Settings now?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      );

      if (goToSettings == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      }
      throw WhisperException('API key not configured');
    }

    setState(() => _transcriptionStatus = 'Uploading to OpenAI...');

    return await ref
        .read(whisperServiceProvider)
        .transcribeAudio(_recording!.filePath);
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
      final storageService = ref.read(storageServiceProvider);
      final modeString = await storageService.getTranscriptionMode();
      final mode =
          TranscriptionMode.fromString(modeString) ?? TranscriptionMode.api;

      String transcript;

      if (mode == TranscriptionMode.local) {
        final localService = ref.read(whisperLocalServiceProvider);
        final isReady = await localService.isReady();

        if (!isReady) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please download a Whisper model in Settings first',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _isTranscribingContext = false);
          return;
        }

        transcript = await localService.transcribeAudio(recordingPath);
      } else {
        final whisperService = ref.read(whisperServiceProvider);
        final isConfigured = await whisperService.isConfigured();

        if (!isConfigured) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please configure OpenAI API key in Settings'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _isTranscribingContext = false);
          return;
        }

        transcript = await whisperService.transcribeAudio(recordingPath);
      }

      // Append to context field (with a space if context already has content)
      if (mounted) {
        final currentContext = _contextController.text.trim();
        final newContext = currentContext.isEmpty
            ? transcript
            : '$currentContext ${transcript}';

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
      body: _buildBody(),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlayback,
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 32,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recording?.durationString ??
                      _formatDuration(widget.duration ?? Duration.zero),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _recording?.formattedSize ?? 'Processing...',
                  style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_isPlaying)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
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
    // Check if transcription is incomplete
    final isIncomplete = _recording?.isTranscriptionIncomplete ?? false;

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
                  // Show "Complete Transcription" button for incomplete transcriptions
                  if (isIncomplete && !_isTranscribing)
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

          // Warning for incomplete transcriptions
          if (isIncomplete && !_isTranscribing)
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
