import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/recorder/services/omi/models.dart';
import 'package:app/features/recorder/services/omi/omi_bluetooth_service.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/features/recorder/services/transcription_service_adapter.dart';
import 'package:app/features/recorder/utils/audio/wav_bytes_util.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';
import 'package:app/core/services/file_system_service.dart';

/// Service for capturing audio recordings from Omi device
///
/// Handles:
/// - Button event listening
/// - Audio stream capture
/// - WAV file generation
/// - Recording persistence
/// - Background recording support
class OmiCaptureService {
  final OmiBluetoothService bluetoothService;
  final StorageService storageService;
  final TranscriptionServiceAdapter transcriptionService;

  WavBytesUtil? _wavBytesUtil;
  StreamSubscription? _audioSubscription;
  StreamSubscription? _buttonSubscription;

  bool _isRecording = false;
  DateTime? _recordingStartTime;
  int? _currentButtonTapCount;
  Timer? _legacyButtonTimer;

  // Callbacks for UI updates
  Function(bool isRecording)? onRecordingStateChanged;
  Function(String message)? onStatusMessage;
  Function(Recording recording)? onRecordingSaved;

  OmiCaptureService({
    required this.bluetoothService,
    required this.storageService,
    required this.transcriptionService,
  });

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get current recording duration
  Duration? get recordingDuration {
    if (_recordingStartTime == null) return null;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Start listening for button events from device
  Future<void> startListening() async {
    debugPrint('[OmiCaptureService] Starting button listener');

    final connection = bluetoothService.activeConnection;
    if (connection == null) {
      debugPrint('[OmiCaptureService] No active connection');
      return;
    }

    try {
      _buttonSubscription = await connection.getBleButtonListener(
        onButtonReceived: _onButtonEvent,
      );

      if (_buttonSubscription != null) {
        debugPrint('[OmiCaptureService] Button listener started');
      } else {
        debugPrint('[OmiCaptureService] Failed to start button listener');
      }
    } catch (e) {
      debugPrint('[OmiCaptureService] Error starting button listener: $e');
    }
  }

  /// Stop listening for button events
  Future<void> stopListening() async {
    debugPrint('[OmiCaptureService] Stopping button listener');

    await _buttonSubscription?.cancel();
    _buttonSubscription = null;

    // If recording, stop it
    if (_isRecording) {
      await stopRecording();
    }
  }

  /// Handle button event from device
  void _onButtonEvent(List<int> data) {
    if (data.isEmpty) return;

    final buttonCode = data[0];
    final buttonEvent = ButtonEvent.fromCode(buttonCode);

    // Log button press prominently
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🔘 OMI BUTTON EVENT!');
    debugPrint('   Type: $buttonEvent');
    debugPrint('   Code: $buttonCode');
    debugPrint('   Recording: ${_isRecording ? "ACTIVE" : "INACTIVE"}');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');

    if (buttonEvent == ButtonEvent.unknown) {
      debugPrint('[OmiCaptureService] ⚠️  Unknown button event: $buttonCode');
      return;
    }

    // Handle button press/release events (codes 4-5)
    //
    // NEW FIRMWARE: Sends press (4) -> release (5) -> tap count (1/2/3)
    //   - We wait for tap count event
    //
    // OLD FIRMWARE: Only sends press (4) -> release (5), no tap count
    //   - We use release event to toggle recording (backward compatibility)

    if (buttonEvent == ButtonEvent.buttonPressed) {
      debugPrint(
        '[OmiCaptureService] 👆 Button pressed (waiting for release or tap count)',
      );
      return;
    }

    if (buttonEvent == ButtonEvent.buttonReleased) {
      debugPrint('[OmiCaptureService] 👆 Button released');

      // Backward compatibility: If firmware doesn't send tap count events,
      // treat button release as a toggle for start/stop recording
      // Start a 700ms timer - if we don't get a tap count event, toggle recording
      _legacyButtonTimer?.cancel();
      _legacyButtonTimer = Timer(const Duration(milliseconds: 700), () {
        debugPrint(
          '[OmiCaptureService] ⚠️  No tap count received - using legacy mode (toggle on release)',
        );

        if (_isRecording) {
          debugPrint(
            '[OmiCaptureService] ⏹️  Stopping recording (legacy button release)',
          );
          _stopRecordingWithTapCount(1); // Default to single tap
        } else {
          debugPrint(
            '[OmiCaptureService] ⏺️  Starting recording (legacy button release)',
          );
          _startRecordingWithTapCount(1); // Default to single tap
        }
      });
      return;
    }

    // Handle tap count events (1-3) - these are the actual triggers
    // Tap events come AFTER press/release sequence completes

    // Cancel legacy timer since we got a proper tap count event (new firmware)
    _legacyButtonTimer?.cancel();
    _legacyButtonTimer = null;

    if (_isRecording) {
      // Stop recording with tap count
      debugPrint(
        '[OmiCaptureService] ⏹️  Stopping recording (button event: $buttonEvent)',
      );
      _stopRecordingWithTapCount(buttonEvent.toCode());
    } else {
      // Start recording
      debugPrint(
        '[OmiCaptureService] ⏺️  Starting recording (button event: $buttonEvent)',
      );
      _startRecordingWithTapCount(buttonEvent.toCode());
    }
  }

  /// Start recording from device
  Future<void> _startRecordingWithTapCount(int tapCount) async {
    if (_isRecording) {
      debugPrint('[OmiCaptureService] Already recording');
      return;
    }

    debugPrint('[OmiCaptureService] Starting recording (tap count: $tapCount)');
    _currentButtonTapCount = tapCount;

    final connection = bluetoothService.activeConnection;
    if (connection == null) {
      debugPrint('[OmiCaptureService] No active connection');
      onStatusMessage?.call('Device not connected');
      return;
    }

    try {
      // Get audio codec from device
      final codec = await connection.getAudioCodec();
      debugPrint('[OmiCaptureService] Audio codec: $codec');

      // Initialize WAV builder and reset state for new recording
      _wavBytesUtil = WavBytesUtil(codec: codec);

      // CRITICAL: Clear any previous state to accept new packet sequence
      _wavBytesUtil!.clear();

      // Start audio stream
      _audioSubscription = await connection.getBleAudioBytesListener(
        onAudioBytesReceived: _onAudioData,
      );

      if (_audioSubscription == null) {
        debugPrint('[OmiCaptureService] Failed to start audio stream');
        onStatusMessage?.call('Failed to start audio stream');
        _wavBytesUtil = null;
        return;
      }

      _isRecording = true;
      _recordingStartTime = DateTime.now();

      onRecordingStateChanged?.call(true);
      onStatusMessage?.call('Recording started');

      debugPrint('[OmiCaptureService] Recording started successfully');
    } catch (e) {
      debugPrint('[OmiCaptureService] Error starting recording: $e');
      onStatusMessage?.call('Error starting recording: $e');
      _cleanup();
    }
  }

  /// Receive audio data from device
  void _onAudioData(List<int> data) {
    if (!_isRecording || _wavBytesUtil == null) return;

    // Store audio packet
    _wavBytesUtil!.storeFramePacket(data);
  }

  /// Stop recording and save
  Future<void> _stopRecordingWithTapCount(int tapCount) async {
    if (!_isRecording) {
      debugPrint('[OmiCaptureService] Not recording');
      return;
    }

    debugPrint('[OmiCaptureService] Stopping recording (tap count: $tapCount)');

    try {
      // Stop audio stream
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      // Build WAV file
      if (_wavBytesUtil == null || !_wavBytesUtil!.hasFrames) {
        debugPrint('[OmiCaptureService] No audio data captured');
        onStatusMessage?.call('No audio data captured');
        _cleanup();
        return;
      }

      final wavBytes = _wavBytesUtil!.buildWavFile();
      final duration = _wavBytesUtil!.duration;

      debugPrint(
        '[OmiCaptureService] Built WAV file: ${wavBytes.length} bytes, duration: $duration',
      );

      // Create recording ID FIRST - use same ID for both WAV file and metadata
      final now = DateTime.now();
      final recordingId = now.millisecondsSinceEpoch.toString();

      // Save to file with the recording ID
      final filePath = await _saveWavFile(wavBytes, recordingId);

      if (filePath == null) {
        debugPrint('[OmiCaptureService] Failed to save WAV file');
        onStatusMessage?.call('Failed to save recording');
        _cleanup();
        return;
      }

      // Create recording metadata using SAME recording ID
      final device = bluetoothService.connectedDevice;

      final recording = Recording(
        id: recordingId,
        title: 'Omi Recording',
        filePath: filePath,
        timestamp: _recordingStartTime ?? DateTime.now(),
        duration: duration,
        tags: [],
        transcript: '',
        fileSizeKB: wavBytes.length / 1024,
        source: RecordingSource.omiDevice,
        deviceId: device?.id,
        buttonTapCount: _currentButtonTapCount ?? tapCount,
      );

      // Save recording metadata
      await storageService.saveRecording(recording);

      debugPrint('[OmiCaptureService] Recording saved: ${recording.id}');
      debugPrint('[OmiCaptureService] WAV file path: $filePath');
      onStatusMessage?.call('Recording saved');

      // Notify UI that recording was saved (for list refresh)
      onRecordingSaved?.call(recording);

      // Clean up first before auto-transcribe to avoid ref disposal errors
      _cleanup();

      // Check if auto-transcribe is enabled (run after cleanup to avoid widget disposal errors)
      // This happens asynchronously and won't block the UI
      _autoTranscribeIfEnabled(recording).catchError((e) {
        debugPrint('[OmiCaptureService] Auto-transcribe error (non-fatal): $e');
      });
    } catch (e) {
      debugPrint('[OmiCaptureService] Error stopping recording: $e');
      onStatusMessage?.call('Error saving recording: $e');
      _cleanup();
    }
  }

  /// Manually start recording (for testing or UI control)
  Future<void> startRecording() async {
    await _startRecordingWithTapCount(1); // Default to single tap
  }

  /// Manually stop recording (for testing or UI control)
  Future<void> stopRecording() async {
    await _stopRecordingWithTapCount(_currentButtonTapCount ?? 1);
  }

  /// Save WAV file to temp recordings folder (will be compressed to Opus after transcription)
  /// Uses the recordings subfolder which has 7-day retention for crash recovery
  Future<String?> _saveWavFile(Uint8List wavBytes, String recordingId) async {
    try {
      // Save to temp recordings folder - protected from aggressive cleanup
      // Will be converted to Opus and moved to captures after transcription
      final fileSystem = FileSystemService();
      final wavFilePath = await fileSystem.getRecordingTempPath();

      final wavFile = File(wavFilePath);
      await wavFile.writeAsBytes(wavBytes);

      debugPrint('[OmiCaptureService] Saved WAV file to temp recordings: $wavFilePath');
      return wavFilePath;
    } catch (e) {
      debugPrint('[OmiCaptureService] Error saving WAV file: $e');
      return null;
    }
  }

  /// Format date for filename
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Clean up resources
  void _cleanup() {
    _isRecording = false;
    _recordingStartTime = null;
    _currentButtonTapCount = null;
    _wavBytesUtil = null;

    onRecordingStateChanged?.call(false);
  }

  /// Auto-transcribe recording if enabled in settings
  Future<void> _autoTranscribeIfEnabled(Recording recording) async {
    try {
      // Check if auto-transcribe is enabled
      final autoTranscribe = await storageService.getAutoTranscribe();
      if (!autoTranscribe) {
        debugPrint(
          '[OmiCaptureService] Auto-transcribe disabled, skipping transcription',
        );
        // Still need to compress and move from temp to captures folder
        await _compressAndSaveRecording(recording, null);
        return;
      }

      debugPrint('[OmiCaptureService] Auto-transcribe enabled, starting...');
      onStatusMessage?.call('Transcribing...');

      // Use Parakeet transcription service
      final transcriptResult = await transcriptionService.transcribeAudio(
        recording.filePath,
        language: 'auto',
        onProgress: (progress) {
          onStatusMessage?.call('Transcribing: ${progress.status}');
        },
      );

      debugPrint(
        '[OmiCaptureService] Transcription complete: ${transcriptResult.text.length} chars',
      );
      onStatusMessage?.call('Transcription complete!');

      // Compress and save with transcript
      await _compressAndSaveRecording(recording, transcriptResult.text);
    } catch (e) {
      debugPrint('[OmiCaptureService] Auto-transcription failed: $e');
      onStatusMessage?.call('Transcription failed');
      // Still try to save the recording without transcript
      await _compressAndSaveRecording(recording, null);
    }
  }

  /// Compress WAV to Opus and save to captures folder
  Future<void> _compressAndSaveRecording(Recording recording, String? transcript) async {
    try {
      // Get the destination path in captures folder
      final syncFolder = await storageService.getSyncFolderPath();
      final now = recording.timestamp;
      final dateStr = _formatDate(now);
      final opusFileName = '$dateStr-${recording.id}.opus';
      final opusDestPath = '$syncFolder/$opusFileName';

      // Compress WAV to Opus
      debugPrint('[OmiCaptureService] Compressing to Opus...');
      final compressionService = AudioCompressionServiceDart();

      // First compress (this creates .opus next to the .wav in temp)
      final tempOpusPath = await compressionService.compressToOpus(
        wavPath: recording.filePath,
        deleteOriginal: true, // Delete the temp WAV file
      );
      debugPrint('[OmiCaptureService] Compression complete: $tempOpusPath');

      // Move the Opus file from temp to captures folder
      final tempOpusFile = File(tempOpusPath);
      await tempOpusFile.copy(opusDestPath);
      await tempOpusFile.delete();
      debugPrint('[OmiCaptureService] Moved Opus to captures: $opusDestPath');

      // Update recording with transcript and new Opus file path
      final updatedRecording = Recording(
        id: recording.id,
        title: recording.title,
        filePath: opusDestPath,
        timestamp: recording.timestamp,
        duration: recording.duration,
        tags: recording.tags,
        transcript: transcript ?? '',
        fileSizeKB: await File(opusDestPath).length() / 1024,
        source: recording.source,
        deviceId: recording.deviceId,
        buttonTapCount: recording.buttonTapCount,
      );
      await storageService.saveRecording(updatedRecording);

      // Notify UI again with updated recording
      onRecordingSaved?.call(updatedRecording);
    } catch (e) {
      debugPrint('[OmiCaptureService] Error compressing/saving recording: $e');
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    await stopListening();
    _cleanup();
  }
}
