import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../../recorder/providers/service_providers.dart';
import '../../settings/screens/settings_screen.dart';

/// Input bar for adding entries to the journal
///
/// Supports text input and voice recording with transcription.
/// Uses streaming pattern: creates entry immediately, transcribes in background.
class JournalInputBar extends ConsumerStatefulWidget {
  final Future<void> Function(String text) onTextSubmitted;
  final Future<void> Function(String transcript, String audioPath, int duration)?
      onVoiceRecorded;
  /// Called when background transcription completes - allows updating the entry
  final Future<void> Function(String transcript)? onTranscriptReady;

  const JournalInputBar({
    super.key,
    required this.onTextSubmitted,
    this.onVoiceRecorded,
    this.onTranscriptReady,
  });

  @override
  ConsumerState<JournalInputBar> createState() => _JournalInputBarState();
}

class _JournalInputBarState extends ConsumerState<JournalInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isSubmitting = false;
  bool _isProcessing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  Future<void> _submitText() async {
    if (!_hasText || _isSubmitting) return;

    final text = _controller.text.trim();
    setState(() => _isSubmitting = true);

    try {
      await widget.onTextSubmitted(text);
      _controller.clear();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || widget.onVoiceRecorded == null) return;

    final audioService = ref.read(audioServiceProvider);

    try {
      await audioService.ensureInitialized();
      final started = await audioService.startRecording();

      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start recording. Check microphone permissions.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording && !_isPaused) {
          setState(() {
            _recordingDuration = _recordingDuration + const Duration(seconds: 1);
          });
        }
      });

      debugPrint('[JournalInputBar] Recording started');
    } catch (e) {
      debugPrint('[JournalInputBar] Failed to start recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.pauseRecording();
      setState(() {
        _isPaused = true;
      });
      debugPrint('[JournalInputBar] Recording paused');
    } catch (e) {
      debugPrint('[JournalInputBar] Failed to pause recording: $e');
    }
  }

  Future<void> _resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    final audioService = ref.read(audioServiceProvider);
    try {
      await audioService.resumeRecording();
      setState(() {
        _isPaused = false;
      });
      debugPrint('[JournalInputBar] Recording resumed');
    } catch (e) {
      debugPrint('[JournalInputBar] Failed to resume recording: $e');
    }
  }

  Future<void> _discardRecording() async {
    if (!_isRecording) return;

    _durationTimer?.cancel();
    _durationTimer = null;

    final audioService = ref.read(audioServiceProvider);
    await audioService.stopRecording();

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _recordingDuration = Duration.zero;
    });

    debugPrint('[JournalInputBar] Recording discarded');
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _durationTimer?.cancel();
    _durationTimer = null;

    final audioService = ref.read(audioServiceProvider);
    final durationSeconds = _recordingDuration.inSeconds;

    setState(() {
      _isRecording = false;
      _isPaused = false;
      _isProcessing = true;
    });

    try {
      final audioPath = await audioService.stopRecording();

      if (audioPath == null) {
        throw Exception('No audio file saved');
      }

      debugPrint('[JournalInputBar] Recording stopped, creating entry immediately...');

      // Create entry immediately with placeholder (streaming approach)
      // This gives instant feedback while transcription runs in background
      if (widget.onVoiceRecorded != null) {
        // Create with empty transcript - UI will show "Transcribing..."
        await widget.onVoiceRecorded!('', audioPath, durationSeconds);
      }

      // Now transcribe in background and update
      debugPrint('[JournalInputBar] Starting background transcription...');
      _transcribeInBackground(audioPath, durationSeconds);

    } catch (e) {
      debugPrint('[JournalInputBar] Failed to process recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save recording: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  /// Transcribe audio in background and update the entry
  Future<void> _transcribeInBackground(String audioPath, int durationSeconds) async {
    try {
      final postProcessingService = ref.read(recordingPostProcessingProvider);
      final result = await postProcessingService.process(audioPath: audioPath);
      final transcript = result.transcript;

      debugPrint('[JournalInputBar] Background transcription complete: ${transcript.length} chars');

      // Clean up temp file now that transcription is done
      try {
        final tempFile = File(audioPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
          debugPrint('[JournalInputBar] Deleted temp audio file');
        }
      } catch (e) {
        debugPrint('[JournalInputBar] Could not delete temp file: $e');
      }

      if (transcript.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No speech detected in recording.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Update the entry with the transcript
      if (widget.onTranscriptReady != null) {
        await widget.onTranscriptReady!(transcript);
      }
    } catch (e) {
      debugPrint('[JournalInputBar] Background transcription failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _toggleRecording() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          top: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _isRecording
            ? _buildRecordingMode(isDark, theme)
            : _buildInputMode(isDark, theme),
      ),
    );
  }

  /// Build the recording mode UI with timer and controls
  Widget _buildRecordingMode(bool isDark, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recording status and timer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: _isPaused
                ? BrandColors.warning.withValues(alpha: 0.1)
                : BrandColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // Status indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isPaused)
                    Icon(Icons.pause, color: BrandColors.warning, size: 20)
                  else
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: BrandColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _isPaused ? 'Paused' : 'Recording',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _isPaused ? BrandColors.warning : BrandColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Timer
              Text(
                _formatDuration(_recordingDuration),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  color: isDark ? BrandColors.softWhite : BrandColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Control buttons
        Row(
          children: [
            // Discard button
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _discardRecording,
                  icon: Icon(Icons.close, size: 20, color: BrandColors.driftwood),
                  label: Text(
                    'Discard',
                    style: TextStyle(color: BrandColors.driftwood),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: BrandColors.driftwood.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Pause/Resume button
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                onPressed: _isPaused ? _resumeRecording : _pauseRecording,
                style: IconButton.styleFrom(
                  backgroundColor: _isPaused
                      ? BrandColors.forest.withValues(alpha: 0.1)
                      : BrandColors.warning.withValues(alpha: 0.1),
                  shape: const CircleBorder(),
                ),
                icon: Icon(
                  _isPaused ? Icons.play_arrow : Icons.pause,
                  color: _isPaused ? BrandColors.forest : BrandColors.warning,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Save button
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.check, size: 20),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BrandColors.forest,
                    foregroundColor: BrandColors.softWhite,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build the normal input mode UI
  Widget _buildInputMode(bool isDark, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Processing indicator
        if (_isProcessing) ...[
          _buildRecordingIndicator(isDark),
          const SizedBox(height: 8),
        ],

        // Input row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Voice record button
            _buildVoiceButton(isDark),
            const SizedBox(width: 8),

            // Text input field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.cream,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? BrandColors.forest
                        : (isDark ? BrandColors.charcoal : BrandColors.stone),
                    width: _focusNode.hasFocus ? 1.5 : 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  enabled: !_isProcessing,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? BrandColors.softWhite : BrandColors.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: _isProcessing ? 'Transcribing...' : 'Capture a thought...',
                    hintStyle: TextStyle(
                      color: BrandColors.driftwood,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitText(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Send button
            _buildSendButton(isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordingIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isProcessing
            ? BrandColors.turquoise.withValues(alpha: 0.1)
            : BrandColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isProcessing) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(BrandColors.turquoise),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Transcribing...',
              style: TextStyle(
                color: BrandColors.turquoise,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: BrandColors.error,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                color: BrandColors.error,
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceButton(bool isDark) {
    final isDisabled = _isProcessing;
    final isActive = _isRecording;

    return GestureDetector(
      onLongPress: isDisabled || isActive ? null : _showRecordingOptions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? BrandColors.error
              : (isDisabled
                  ? (isDark ? BrandColors.charcoal : BrandColors.stone)
                  : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.forestMist)),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: isDisabled ? null : _toggleRecording,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? BrandColors.driftwood : BrandColors.charcoal,
                    ),
                  ),
                )
              : Icon(
                  isActive ? Icons.stop : Icons.mic,
                  color: isActive
                      ? BrandColors.softWhite
                      : (isDisabled ? BrandColors.driftwood : BrandColors.forest),
                  size: 22,
                ),
        ),
      ),
    );
  }

  /// Show recording options bottom sheet (long press on mic)
  void _showRecordingOptions() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? BrandColors.charcoal : BrandColors.stone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Recording Options',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? BrandColors.softWhite : BrandColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Settings option
            ListTile(
              leading: Icon(Icons.settings, color: BrandColors.driftwood),
              title: const Text('Recording Settings'),
              subtitle: const Text('Transcription, Omi device, and more'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSendButton(bool isDark) {
    final canSend = _hasText && !_isSubmitting && !_isRecording && !_isProcessing;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: canSend
            ? BrandColors.forest
            : (isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: canSend ? _submitText : null,
        icon: _isSubmitting
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    BrandColors.softWhite,
                  ),
                ),
              )
            : Icon(
                Icons.arrow_upward,
                color: canSend
                    ? BrandColors.softWhite
                    : BrandColors.driftwood,
                size: 22,
              ),
      ),
    );
  }
}
