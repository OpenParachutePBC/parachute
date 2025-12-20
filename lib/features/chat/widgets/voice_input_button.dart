import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/providers/service_providers.dart';

/// Voice input button for chat - records audio and transcribes to text.
///
/// When tapped, starts recording. When released or tapped again, stops
/// recording and transcribes the audio, then calls [onTranscription] with
/// the result.
class VoiceInputButton extends ConsumerStatefulWidget {
  /// Called when transcription is complete
  final void Function(String text) onTranscription;

  /// Called when recording starts
  final VoidCallback? onRecordingStart;

  /// Called when recording stops (before transcription)
  final VoidCallback? onRecordingStop;

  /// Whether the button is enabled
  final bool enabled;

  const VoiceInputButton({
    super.key,
    required this.onTranscription,
    this.onRecordingStart,
    this.onRecordingStop,
    this.enabled = true,
  });

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton> {
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void dispose() {
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isTranscribing) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.ensureInitialized();

      // AudioService.startRecording() generates its own path
      final started = await audioService.startRecording();
      if (!started) {
        throw Exception('Failed to start recording');
      }

      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });

      widget.onRecordingStart?.call();

      // Start timer to show recording duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        }
      });
    } catch (e) {
      debugPrint('[VoiceInputButton] Error starting recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();

    try {
      final audioService = ref.read(audioServiceProvider);
      // stopRecording() returns the path to the recorded file
      final audioPath = await audioService.stopRecording();

      setState(() {
        _isRecording = false;
      });

      widget.onRecordingStop?.call();

      // Now transcribe if we have a valid path
      if (audioPath != null) {
        await _transcribeRecording(audioPath);
      }
    } catch (e) {
      debugPrint('[VoiceInputButton] Error stopping recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _transcribeRecording(String audioPath) async {
    setState(() {
      _isTranscribing = true;
    });

    try {
      final transcriptionService = ref.read(transcriptionServiceAdapterProvider);

      // Verify the audio file exists
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found');
      }

      // Transcribe using the adapter (it handles lazy initialization)
      final result = await transcriptionService.transcribeAudio(audioPath);

      if (result.text.isNotEmpty) {
        widget.onTranscription(result.text);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No speech detected'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // Clean up temp file (for chat voice input, we don't need to keep it)
      try {
        await audioFile.delete();
      } catch (_) {}
    } catch (e) {
      debugPrint('[VoiceInputButton] Transcription error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transcription failed: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTranscribing = false;
        });
      }
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine button state and appearance
    Color backgroundColor;
    Color iconColor;
    IconData icon;

    if (_isTranscribing) {
      backgroundColor = isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone;
      iconColor = isDark
          ? BrandColors.nightTextSecondary
          : BrandColors.driftwood;
      icon = Icons.hourglass_empty_rounded;
    } else if (_isRecording) {
      backgroundColor = BrandColors.error;
      iconColor = Colors.white;
      icon = Icons.stop_rounded;
    } else {
      backgroundColor = isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone;
      iconColor = widget.enabled
          ? (isDark ? BrandColors.nightText : BrandColors.charcoal)
          : (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood);
      icon = Icons.mic_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Recording duration indicator
        if (_isRecording)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.xs),
            child: Text(
              _formatDuration(_recordingDuration),
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                fontWeight: FontWeight.w600,
                color: BrandColors.error,
              ),
            ),
          ),

        // The button
        IconButton(
          onPressed: widget.enabled && !_isTranscribing
              ? _toggleRecording
              : null,
          style: IconButton.styleFrom(
            backgroundColor: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: Radii.button,
            ),
          ),
          icon: _isTranscribing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                  ),
                )
              : Icon(icon, size: 20, color: iconColor),
        ),
      ],
    );
  }
}
