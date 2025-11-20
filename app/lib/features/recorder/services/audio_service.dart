import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:app/features/recorder/services/storage_service.dart';
import 'package:app/core/services/audio_compression_service_dart.dart';

enum RecordingState { stopped, recording, paused }

class AudioService {
  final StorageService _storageService;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  AudioService(this._storageService);

  RecordingState _recordingState = RecordingState.stopped;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartTime;
  Timer? _durationTimer;
  bool _isInitialized = false;

  RecordingState get recordingState => _recordingState;
  Duration get recordingDuration => _recordingDuration;
  bool get isPlaying => _player.playing;

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('AudioService already initialized');
      return;
    }

    try {
      debugPrint('Initializing AudioService...');

      // Check if recording is supported
      if (await _recorder.hasPermission()) {
        debugPrint('Recording permissions granted');
      } else {
        debugPrint('Recording permissions not granted');
      }

      _isInitialized = true;
      debugPrint('AudioService initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('Error initializing AudioService: $e');
      debugPrint('Stack trace: $stackTrace');
      _isInitialized = false;
      rethrow;
    }
  }

  Future<void> dispose() async {
    _durationTimer?.cancel();

    // Ensure wakelock is disabled on disposal
    try {
      if (await WakelockPlus.enabled) {
        await WakelockPlus.disable();
        debugPrint('Wakelock disabled on dispose');
      }
    } catch (e) {
      debugPrint('Error checking/disabling wakelock on dispose: $e');
    }

    await _recorder.dispose();
    await _player.dispose();
    _isInitialized = false;
    debugPrint('AudioService disposed');
  }

  Future<bool> requestPermissions() async {
    try {
      // Use the record package's built-in permission handling
      // which works across all platforms including macOS
      final hasPermission = await _recorder.hasPermission();
      debugPrint('Recording permission check: $hasPermission');

      if (!hasPermission) {
        debugPrint('Microphone permission denied');

        // On Android, try to open settings if permission is denied
        if (Platform.isAndroid) {
          try {
            final micPermission = await Permission.microphone.status;
            if (micPermission.isPermanentlyDenied) {
              debugPrint('Opening app settings for permission...');
              await openAppSettings();
            }
          } catch (e) {
            debugPrint('Could not open settings: $e');
          }
        }

        return false;
      }

      // For Android 13+, also check notification permission for background recording
      if (Platform.isAndroid) {
        try {
          if (await Permission.notification.isDenied) {
            final notificationPermission = await Permission.notification
                .request();
            debugPrint(
              'Android Notification permission: $notificationPermission',
            );
          }
        } catch (e) {
          debugPrint('Could not request notification permission: $e');
          // Not critical, continue anyway
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      // If there's an error but the recorder says it has permission, trust it
      try {
        return await _recorder.hasPermission();
      } catch (e2) {
        debugPrint('Fallback permission check failed: $e2');
        return false;
      }
    }
  }

  Future<String> _getRecordingPath(String recordingId) async {
    try {
      final syncFolder = await _storageService.getSyncFolderPath();

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Use WAV format for Parakeet compatibility (16kHz mono)
      final path = '$syncFolder/$dateStr-$recordingId.wav';
      debugPrint('Generated recording path: $path');
      return path;
    } catch (e) {
      debugPrint('Error getting recording path: $e');
      rethrow;
    }
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingState == RecordingState.recording &&
          _recordingStartTime != null) {
        _recordingDuration =
            DateTime.now().difference(_recordingStartTime!) - _pausedDuration;
      }
    });
  }

  Future<bool> startRecording() async {
    debugPrint('startRecording called, current state: $_recordingState');
    if (_recordingState != RecordingState.stopped) {
      debugPrint('Cannot start recording: state is $_recordingState');
      return false;
    }

    // Check and request permissions
    final hasPermission = await requestPermissions();
    debugPrint('Permission check result: $hasPermission');
    if (!hasPermission) {
      debugPrint('Permission denied, cannot start recording');
      return false;
    }

    try {
      // Ensure recorder is properly initialized
      if (!_isInitialized) {
        debugPrint('Recorder not initialized, initializing now...');
        await initialize();
      }

      // Check if already recording
      if (await _recorder.isRecording()) {
        debugPrint('Recorder is already recording');
        return false;
      }

      // Generate recording ID and path
      debugPrint('Generating recording ID...');
      final recordingId = DateTime.now().millisecondsSinceEpoch.toString();
      debugPrint('Recording ID: $recordingId');

      debugPrint('Getting recording path...');
      _currentRecordingPath = await _getRecordingPath(recordingId);
      debugPrint('Will record to: $_currentRecordingPath');

      // Enable wakelock to prevent device sleep during recording
      debugPrint('Enabling wakelock...');
      await WakelockPlus.enable();
      debugPrint('Wakelock enabled');

      // Start recording with WAV format (compatible with Parakeet)
      debugPrint('Starting recorder...');
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000, // 16kHz for Parakeet/Whisper
          numChannels: 1, // Mono
        ),
        path: _currentRecordingPath!,
      );
      debugPrint('Recorder.start() completed');

      _recordingStartTime = DateTime.now();
      _recordingState = RecordingState.recording;
      _recordingDuration = Duration.zero;
      _pausedDuration = Duration.zero;
      _startDurationTimer();

      debugPrint('Recording started successfully');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error starting recording: $e');
      debugPrint('Stack trace: $stackTrace');
      _recordingState = RecordingState.stopped;
      _currentRecordingPath = null;
      return false;
    }
  }

  Future<bool> pauseRecording() async {
    if (_recordingState != RecordingState.recording) return false;

    try {
      await _recorder.pause();
      _recordingState = RecordingState.paused;
      _pauseStartTime = DateTime.now();
      _durationTimer?.cancel();
      debugPrint('Recording paused');
      return true;
    } catch (e) {
      debugPrint('Error pausing recording: $e');
      return false;
    }
  }

  Future<bool> resumeRecording() async {
    if (_recordingState != RecordingState.paused) return false;

    try {
      await _recorder.resume();
      _recordingState = RecordingState.recording;

      // Add the paused duration to total paused time
      if (_pauseStartTime != null) {
        _pausedDuration += DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }

      _startDurationTimer();
      debugPrint('Recording resumed');
      return true;
    } catch (e) {
      debugPrint('Error resuming recording: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    if (_recordingState == RecordingState.stopped) return null;

    try {
      _durationTimer?.cancel();

      // Disable wakelock when recording stops
      debugPrint('Disabling wakelock...');
      await WakelockPlus.disable();
      debugPrint('Wakelock disabled');

      final path = await _recorder.stop();
      _recordingState = RecordingState.stopped;
      _currentRecordingPath = null;
      _recordingStartTime = null;
      _pauseStartTime = null;
      _pausedDuration = Duration.zero;

      // Verify file exists
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final size = await file.length();
          debugPrint(
            'Recording stopped and saved: $path (size: ${size / 1024}KB)',
          );
          return path;
        } else {
          debugPrint('Recording file not found at: $path');
        }
      }

      debugPrint('Recording stopped but file not found');
      return null;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _recordingState = RecordingState.stopped;
      _durationTimer?.cancel();
      // Ensure wakelock is disabled even on error
      try {
        await WakelockPlus.disable();
      } catch (wakelockError) {
        debugPrint('Error disabling wakelock: $wakelockError');
      }
      return null;
    }
  }

  Future<bool> playRecording(String filePath) async {
    try {
      if (filePath.isEmpty) {
        debugPrint('Cannot play: empty file path');
        return false;
      }

      String playbackPath = filePath;

      // If it's an Opus file, check if WAV exists or convert it
      if (filePath.endsWith('.opus')) {
        final wavPath = filePath.replaceAll('.opus', '.wav');
        final wavFile = File(wavPath);

        if (!await wavFile.exists()) {
          debugPrint('WAV not found for Opus file, converting...');

          // Convert Opus to WAV for playback
          final service = AudioCompressionServiceDart();

          try {
            playbackPath = await service.decompressToWav(
              opusPath: filePath,
              outputPath: wavPath,
            );
            debugPrint('Converted Opus to WAV for playback: $playbackPath');
          } catch (e) {
            debugPrint('Failed to convert Opus to WAV: $e');
            return false;
          }
        } else {
          debugPrint('Using existing WAV file for playback');
          playbackPath = wavPath;
        }
      }

      final file = File(playbackPath);
      if (!await file.exists()) {
        debugPrint('File not found: $playbackPath');
        return false;
      }

      await _player.setFilePath(playbackPath);
      await _player.play();

      debugPrint('Playing recording: $playbackPath');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Error playing recording: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<bool> stopPlayback() async {
    try {
      await _player.stop();
      debugPrint('Playback stopped');
      return true;
    } catch (e) {
      debugPrint('Error stopping playback: $e');
      return false;
    }
  }

  Future<bool> pausePlayback() async {
    try {
      await _player.pause();
      return true;
    } catch (e) {
      debugPrint('Error pausing playback: $e');
      return false;
    }
  }

  Future<bool> resumePlayback() async {
    try {
      await _player.play();
      return true;
    } catch (e) {
      debugPrint('Error resuming playback: $e');
      return false;
    }
  }

  Future<bool> seekTo(Duration position) async {
    try {
      await _player.seek(position);
      return true;
    } catch (e) {
      debugPrint('Error seeking playback: $e');
      return false;
    }
  }

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get playingStream => _player.playingStream;

  Future<Duration?> getRecordingDuration(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      await _player.setFilePath(filePath);
      return _player.duration;
    } catch (e) {
      debugPrint('Error getting recording duration: $e');
      return null;
    }
  }

  Future<double> getFileSizeKB(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final size = await file.length();
        return size / 1024;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting file size: $e');
      return 0;
    }
  }

  Future<bool> deleteRecordingFile(String filePath) async {
    try {
      if (filePath.isEmpty) {
        debugPrint('Cannot delete: empty file path');
        return false;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted recording file: $filePath');
        return true;
      }

      debugPrint('File not found for deletion: $filePath');
      return false;
    } catch (e) {
      debugPrint('Error deleting recording file: $e');
      return false;
    }
  }
}
