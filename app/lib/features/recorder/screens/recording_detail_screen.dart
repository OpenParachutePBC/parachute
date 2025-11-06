import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/providers/service_providers.dart';
import 'package:app/features/recorder/services/whisper_service.dart';
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/models/whisper_models.dart';
import 'package:app/core/providers/title_generation_provider.dart';
import 'package:app/features/settings/screens/settings_screen.dart';
import 'package:app/features/space_notes/screens/link_capture_to_space_screen.dart';

/// Unified recording detail screen with inline editing
/// Inspired by LiveRecordingScreen design - clean, focused, contextual status
class RecordingDetailScreen extends ConsumerStatefulWidget {
  final Recording recording;

  const RecordingDetailScreen({super.key, required this.recording});

  @override
  ConsumerState<RecordingDetailScreen> createState() =>
      _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends ConsumerState<RecordingDetailScreen> {
  late Recording _recording;
  Timer? _refreshTimer;

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

  @override
  void initState() {
    super.initState();
    _recording = widget.recording;
    _titleController.text = _recording.title;
    _transcriptController.text = _recording.transcript;
    _contextController.text = _recording.context;
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _titleController.dispose();
    _transcriptController.dispose();
    _contextController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    // Only refresh while processing is happening
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final isProcessing =
          _recording.transcriptionStatus == ProcessingStatus.pending ||
          _recording.transcriptionStatus == ProcessingStatus.processing ||
          _recording.titleGenerationStatus == ProcessingStatus.pending ||
          _recording.titleGenerationStatus == ProcessingStatus.processing;

      if (!isProcessing) {
        _refreshTimer?.cancel();
        return;
      }

      // Fetch updated recording from storage
      final updated = await ref
          .read(storageServiceProvider)
          .getRecording(_recording.id);
      if (updated != null && mounted) {
        setState(() {
          _recording = updated;
          // Update controllers if not currently editing
          if (!_isTitleEditing) _titleController.text = _recording.title;
          if (!_isTranscriptEditing) {
            _transcriptController.text = _recording.transcript;
          }
          if (!_isContextEditing) _contextController.text = _recording.context;
        });
      }
    });
  }

  Future<void> _saveChanges() async {
    final updatedRecording = _recording.copyWith(
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Untitled Recording',
      transcript: _transcriptController.text.trim(),
      context: _contextController.text.trim(),
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
    if (_isPlaying) {
      await ref.read(audioServiceProvider).stopPlayback();
      setState(() => _isPlaying = false);
    } else {
      final success = await ref
          .read(audioServiceProvider)
          .playRecording(_recording.filePath);
      if (success) {
        setState(() => _isPlaying = true);
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

  void _linkToSpaces() async {
    String cleanNotePath = _recording.filePath;
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
          captureId: _recording.id,
          filename: _recording.title,
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
          .deleteRecording(_recording.id);
      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Recording deleted')));
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
          : Text(_recording.title),
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
                  _recording.durationString,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _recording.formattedSize,
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
          _recording.timeAgo,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        const SizedBox(width: 16),
        Icon(Icons.folder, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          _recording.source == RecordingSource.omiDevice ? 'Omi' : 'Phone',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildMainContentContainer() {
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
                  if (_recording.transcript.isNotEmpty && !_isTranscriptEditing)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _recording.transcript),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Transcript copied to clipboard'),
                          ),
                        );
                      },
                      tooltip: 'Copy',
                    ),
                  if (_recording.transcript.isEmpty && !_isTranscribing)
                    ElevatedButton.icon(
                      onPressed: _transcribeRecording,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Transcribe'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Inline status indicators (like LiveRecordingScreen)
          if (_isGeneratingTitle) _buildTitleGeneratingIndicator(),
          if (_isTranscribing) _buildTranscribingIndicator(),

          // Content
          if (_recording.transcript.isEmpty && !_isTranscribing)
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
        Text(
          'Context',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
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
