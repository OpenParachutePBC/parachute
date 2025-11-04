import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/recorder/services/whisper_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/features/recorder/widgets/processing_status_indicator.dart';

class RecordingEditScreen extends ConsumerStatefulWidget {
  final Recording recording;

  const RecordingEditScreen({super.key, required this.recording});

  @override
  ConsumerState<RecordingEditScreen> createState() =>
      _RecordingEditScreenState();
}

class _RecordingEditScreenState extends ConsumerState<RecordingEditScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _transcriptController = TextEditingController();

  late Recording _recording;
  Timer? _refreshTimer;

  bool _isPlaying = false;
  bool _isSaving = false;
  bool _isTranscribing = false;
  double _transcriptionProgress = 0.0;
  String _transcriptionStatus = '';
  bool _isGeneratingTitle = false;

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
    _titleController.text = _recording.title;
    _transcriptController.text = _recording.transcript;
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _transcriptController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    // Refresh every 2 seconds to update processing status
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final updated = await ref
          .read(storageServiceProvider)
          .getRecording(_recording.id);
      if (updated != null && mounted) {
        setState(() {
          _recording = updated;
          // Update transcript if it changed and user hasn't modified it
          if (_recording.transcript.isNotEmpty &&
              _transcriptController.text.isEmpty) {
            _transcriptController.text = _recording.transcript;
          }
          // Update title if it changed and user hasn't modified it
          if (_recording.title != widget.recording.title &&
              _titleController.text == widget.recording.title) {
            _titleController.text = _recording.title;
          }
        });
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await ref.read(audioServiceProvider).stopPlayback();
      setState(() => _isPlaying = false);
    } else {
      final success = await ref
          .read(audioServiceProvider)
          .playRecording(_recording.filePath);
      if (success) {
        setState(() => _isPlaying = true);
        // Auto-stop after duration
        Future.delayed(_recording.duration, () {
          if (mounted && _isPlaying) {
            setState(() => _isPlaying = false);
          }
        });
      }
    }
  }

  Future<void> _transcribeRecording() async {
    if (_isTranscribing) return;

    // Get transcription mode
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
        _generateTitleFromTranscript(transcript);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transcription completed!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            duration: const Duration(seconds: 4),
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
      debugPrint('[RecordingEdit] ❌ Title generation failed: $e');
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
      _recording.filePath,
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
        .transcribeAudio(_recording.filePath);
  }

  Future<void> _saveRecording() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final updatedRecording = _recording.copyWith(
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : 'Untitled Recording',
        transcript: _transcriptController.text.trim(),
      );

      final success = await ref
          .read(storageServiceProvider)
          .updateRecording(updatedRecording);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording updated successfully')),
        );

        await Future.delayed(const Duration(milliseconds: 100));

        if (mounted) {
          Navigator.of(context).pop(updatedRecording);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update recording')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating recording: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Recording'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playback controls
            _buildPlaybackSection(),

            const SizedBox(height: 16),

            // Processing status
            ProcessingStatusBar(recording: _recording),

            const SizedBox(height: 24),

            // Title input
            _buildTitleSection(),

            const SizedBox(height: 24),

            // Transcript section
            _buildTranscriptSection(),

            const SizedBox(height: 32),

            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            IconButton(
              onPressed: _togglePlayback,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              iconSize: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleController.text,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _recording.durationString,
                    style: TextStyle(color: Colors.grey.withValues(alpha: 0.7)),
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
      ),
    );
  }

  Widget _buildTitleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Title',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (_isGeneratingTitle)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Generating...',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            hintText: 'Enter recording title',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildTranscriptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Transcript',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ElevatedButton.icon(
              onPressed: _isTranscribing ? null : _transcribeRecording,
              icon: _isTranscribing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_isTranscribing ? 'Transcribing...' : 'Transcribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Progress indicator
        if (_isTranscribing) ...[
          LinearProgressIndicator(value: _transcriptionProgress),
          const SizedBox(height: 4),
          Text(
            _transcriptionStatus.isEmpty
                ? 'Processing...'
                : '$_transcriptionStatus ${(_transcriptionProgress * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
        ],

        SizedBox(
          height: 200,
          child: TextField(
            controller: _transcriptController,
            maxLines: null,
            expands: true,
            decoration: const InputDecoration(
              hintText: 'Add notes or transcript here (optional)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            textAlignVertical: TextAlignVertical.top,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveRecording,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save'),
          ),
        ),
      ],
    );
  }
}
