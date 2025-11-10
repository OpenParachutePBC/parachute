import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as path;
import 'package:app/features/recorder/services/whisper_local_service.dart';
import 'package:app/features/recorder/services/vad/smart_chunker.dart';
import 'package:app/features/recorder/services/audio_processing/simple_noise_filter.dart';

/// Audio debug metrics for visualization
class AudioDebugMetrics {
  final double rawEnergy;
  final double cleanEnergy;
  final double filterReduction; // Percentage
  final double vadThreshold;
  final bool isSpeech;
  final DateTime timestamp;

  AudioDebugMetrics({
    required this.rawEnergy,
    required this.cleanEnergy,
    required this.filterReduction,
    required this.vadThreshold,
    required this.isSpeech,
    required this.timestamp,
  });
}

/// Represents a transcribed segment (auto-detected via VAD)
class TranscriptionSegment {
  final int index; // Segment number (1, 2, 3, ...)
  final String text;
  final TranscriptionSegmentStatus status;
  final DateTime timestamp;
  final Duration duration; // Audio duration of this segment

  TranscriptionSegment({
    required this.index,
    required this.text,
    required this.status,
    required this.timestamp,
    required this.duration,
  });

  TranscriptionSegment copyWith({
    int? index,
    String? text,
    TranscriptionSegmentStatus? status,
    DateTime? timestamp,
    Duration? duration,
  }) {
    return TranscriptionSegment(
      index: index ?? this.index,
      text: text ?? this.text,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
    );
  }
}

enum TranscriptionSegmentStatus {
  pending, // Waiting to be transcribed
  processing, // Currently being transcribed
  completed, // Transcription done
  failed, // Transcription error
}

/// Auto-pause transcription service using VAD-based chunking
///
/// Flow (Phase 1 - Simple noise filtering):
/// 1. User starts recording → Continuous audio capture
/// 2. Audio → High-pass filter (removes low-freq noise) → SmartChunker (VAD) → Auto-detects silence
/// 3. On 1s silence → Auto-chunks → Transcribes
/// 4. User stops → Transcribes final segment
///
/// Future (Phase 2 - Full RNNoise):
/// Audio → RNNoise (full noise suppression) → SmartChunker → Transcription
class AutoPauseTranscriptionService {
  final WhisperLocalService _whisperService;

  // Recording state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  // Noise filtering & VAD
  SimpleNoiseFilter? _noiseFilter;
  SmartChunker? _chunker;
  final List<List<int>> _allAudioSamples = []; // Complete recording

  // File management
  String? _audioFilePath;
  String? _tempDirectory;

  // Segments (auto-detected paragraphs)
  final List<TranscriptionSegment> _segments = [];
  int _nextSegmentIndex = 1;

  // Processing queue
  final List<_QueuedSegment> _processingQueue = [];
  bool _isProcessingQueue = false;

  // Progress streaming
  final _segmentStreamController =
      StreamController<TranscriptionSegment>.broadcast();
  final _processingStreamController = StreamController<bool>.broadcast();
  final _vadActivityController = StreamController<bool>.broadcast();
  final _debugMetricsController =
      StreamController<AudioDebugMetrics>.broadcast();

  Stream<TranscriptionSegment> get segmentStream =>
      _segmentStreamController.stream;
  Stream<bool> get isProcessingStream => _processingStreamController.stream;
  Stream<bool> get vadActivityStream =>
      _vadActivityController.stream; // true = speech, false = silence
  Stream<AudioDebugMetrics> get debugMetricsStream =>
      _debugMetricsController.stream;

  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessingQueue;
  List<TranscriptionSegment> get segments => List.unmodifiable(_segments);

  AutoPauseTranscriptionService(this._whisperService);

  /// Initialize service and create temp directory
  Future<void> initialize() async {
    if (_tempDirectory != null) return;

    final tempDir = Directory.systemTemp;
    _tempDirectory = path.join(tempDir.path, 'parachute_transcription');
    await Directory(_tempDirectory!).create(recursive: true);

    debugPrint('[AutoPauseTranscription] Initialized: $_tempDirectory');
  }

  /// Start auto-pause recording
  Future<bool> startRecording({
    double vadEnergyThreshold =
        200.0, // With noise filtering, can use lower threshold
    Duration silenceThreshold = const Duration(seconds: 1),
    Duration minChunkDuration = const Duration(milliseconds: 500),
    Duration maxChunkDuration = const Duration(seconds: 30),
  }) async {
    if (_isRecording) {
      debugPrint('[AutoPauseTranscription] Already recording');
      return false;
    }

    try {
      // Check permissions
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[AutoPauseTranscription] No recording permission');
        return false;
      }

      // Ensure temp directory exists
      if (_tempDirectory == null) {
        await initialize();
      }

      // Initialize noise filter (removes low-frequency background noise)
      _noiseFilter = SimpleNoiseFilter(
        cutoffFreq:
            80.0, // Remove frequencies below 80Hz (fans, AC hum, rumble)
        sampleRate: 16000,
      );

      // Initialize SmartChunker
      _chunker = SmartChunker(
        config: SmartChunkerConfig(
          sampleRate: 16000,
          silenceThreshold: silenceThreshold,
          minChunkDuration: minChunkDuration,
          maxChunkDuration: maxChunkDuration,
          vadEnergyThreshold: vadEnergyThreshold,
          onChunkReady: _handleChunk,
        ),
      );

      // Set final audio file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioFilePath = path.join(_tempDirectory!, 'recording_$timestamp.wav');

      // Start recording with stream (with OS-level noise suppression)
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          // Enable hardware/OS noise suppression
          echoCancel: true,
          autoGain: true,
          noiseSuppress: true,
        ),
      );

      _isRecording = true;
      _segments.clear();
      _nextSegmentIndex = 1;
      _allAudioSamples.clear();
      _processingQueue.clear();

      // Process audio stream through VAD chunker
      stream.listen(
        _processAudioChunk,
        onError: (error) {
          debugPrint('[AutoPauseTranscription] Stream error: $error');
        },
        onDone: () {
          debugPrint('[AutoPauseTranscription] Stream completed');
        },
      );

      debugPrint('[AutoPauseTranscription] Recording started with VAD');
      return true;
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Failed to start: $e');
      return false;
    }
  }

  /// Process incoming audio chunk from stream
  void _processAudioChunk(Uint8List audioBytes) {
    if (!_isRecording || _chunker == null || _noiseFilter == null) return;

    // Convert bytes to int16 samples
    final rawSamples = _bytesToInt16(audioBytes);

    // Apply noise filter BEFORE VAD (removes low-frequency background noise)
    final cleanSamples = _noiseFilter!.process(rawSamples);

    // Emit debug metrics for visualization (every 10ms frame)
    final rawEnergy = _calculateRMS(rawSamples);
    final cleanEnergy = _calculateRMS(cleanSamples);
    final reduction = rawEnergy > 0
        ? ((1 - cleanEnergy / rawEnergy) * 100)
        : 0.0;

    if (!_debugMetricsController.isClosed) {
      _debugMetricsController.add(
        AudioDebugMetrics(
          rawEnergy: rawEnergy,
          cleanEnergy: cleanEnergy,
          filterReduction: reduction,
          vadThreshold: _chunker!.stats.vadStats.isSpeaking ? cleanEnergy : 0,
          isSpeech: cleanEnergy > 200.0, // Using current threshold
          timestamp: DateTime.now(),
        ),
      );
    }

    // Save clean audio to complete recording
    _allAudioSamples.add(cleanSamples);

    // Process clean audio through SmartChunker (VAD + auto-chunking)
    _chunker!.processSamples(cleanSamples);

    // Debug: Show VAD stats periodically
    if (_allAudioSamples.length % 100 == 0) {
      // Every ~1 second (100 chunks)
      final stats = _chunker!.stats;
      debugPrint(
        '[AutoPauseTranscription] VAD Stats: '
        'Speech: ${stats.vadStats.speechDuration.inMilliseconds}ms, '
        'Silence: ${stats.vadStats.silenceDuration.inMilliseconds}ms, '
        'Buffer: ${stats.bufferDuration.inSeconds}s',
      );
    }
  }

  /// Handle chunk ready from SmartChunker
  void _handleChunk(List<int> samples) {
    final duration = Duration(
      milliseconds: (samples.length / 16).round(),
    ); // 16 samples/ms at 16kHz

    debugPrint(
      '[AutoPauseTranscription] 🎤 Auto-chunk detected! '
      'Duration: ${duration.inSeconds}s (${samples.length} samples)',
    );

    // Queue for transcription
    _queueSegmentForProcessing(samples);
  }

  /// Stop recording and transcribe final segment
  /// Pause recording (manual pause in addition to auto-pause)
  Future<void> pauseRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.pause();
      debugPrint('[AutoPauseTranscription] Recording paused');
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Failed to pause: $e');
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.resume();
      debugPrint('[AutoPauseTranscription] Recording resumed');
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Failed to resume: $e');
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      // Stop recorder
      await _recorder.stop();
      _isRecording = false;

      // Flush final chunk from SmartChunker
      if (_chunker != null) {
        _chunker!.flush();
        _chunker = null;
      }

      // Reset noise filter for next recording
      if (_noiseFilter != null) {
        _noiseFilter!.reset();
        _noiseFilter = null;
      }

      // Wait for all queued segments to finish processing
      while (_isProcessingQueue || _processingQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Merge all audio into final WAV file
      if (_allAudioSamples.isNotEmpty && _audioFilePath != null) {
        await _saveCompleteRecording();
      }

      debugPrint('[AutoPauseTranscription] Recording stopped: $_audioFilePath');
      return _audioFilePath;
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Failed to stop: $e');
      return null;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      // Stop recorder
      await _recorder.stop();
      _isRecording = false;

      // Clear chunker
      if (_chunker != null) {
        _chunker = null;
      }

      // Clear all data
      _segments.clear();
      _allAudioSamples.clear();
      _processingQueue.clear();

      debugPrint('[AutoPauseTranscription] Recording cancelled');
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Failed to cancel: $e');
    }
  }

  /// Queue a segment for transcription (non-blocking)
  void _queueSegmentForProcessing(List<int> samples) {
    final segment = _QueuedSegment(
      index: _nextSegmentIndex++,
      samples: samples,
    );

    _processingQueue.add(segment);

    // Add pending segment to UI
    _segments.add(
      TranscriptionSegment(
        index: segment.index,
        text: '',
        status: TranscriptionSegmentStatus.pending,
        timestamp: DateTime.now(),
        duration: Duration(milliseconds: (samples.length / 16).round()),
      ),
    );
    if (!_segmentStreamController.isClosed) {
      _segmentStreamController.add(_segments.last);
    }

    // Start processing if not already running
    if (!_isProcessingQueue) {
      _processQueue();
    }
  }

  /// Process queued segments sequentially
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    if (!_processingStreamController.isClosed) {
      _processingStreamController.add(true);
    }

    while (_processingQueue.isNotEmpty) {
      final segment = _processingQueue.removeAt(0);
      await _transcribeSegment(segment);
    }

    _isProcessingQueue = false;
    if (!_processingStreamController.isClosed) {
      _processingStreamController.add(false);
    }
  }

  /// Transcribe a single segment
  Future<void> _transcribeSegment(_QueuedSegment segment) async {
    debugPrint(
      '[AutoPauseTranscription] Transcribing segment ${segment.index}',
    );

    // Update segment status to processing
    final segmentIndex = _segments.indexWhere((s) => s.index == segment.index);
    if (segmentIndex == -1) return;

    _segments[segmentIndex] = _segments[segmentIndex].copyWith(
      status: TranscriptionSegmentStatus.processing,
    );
    if (!_segmentStreamController.isClosed) {
      _segmentStreamController.add(_segments[segmentIndex]);
    }

    try {
      // Validate segment has audio data
      if (segment.samples.isEmpty) {
        throw Exception('Segment has no audio data');
      }

      // Save samples to temp WAV file for Whisper
      final tempWavPath = path.join(
        _tempDirectory!,
        'temp_segment_${segment.index}.wav',
      );

      debugPrint(
        '[AutoPauseTranscription] Saving temp WAV: $tempWavPath (${segment.samples.length} samples)',
      );
      await _saveSamplesToWav(segment.samples, tempWavPath);

      // Verify file was created
      final file = File(tempWavPath);
      if (!await file.exists()) {
        throw Exception('Failed to create temp WAV file: $tempWavPath');
      }
      debugPrint(
        '[AutoPauseTranscription] ✅ Temp WAV created: ${await file.length()} bytes',
      );

      // Transcribe
      final text = await _whisperService.transcribeAudio(tempWavPath);

      // Clean up temp WAV file after successful transcription
      try {
        await file.delete();
        debugPrint(
          '[AutoPauseTranscription] Cleaned up temp WAV: $tempWavPath',
        );
      } catch (e) {
        debugPrint('[AutoPauseTranscription] Failed to delete temp WAV: $e');
      }

      // Check if text is empty (Whisper sometimes returns empty for noise)
      if (text.trim().isEmpty) {
        throw Exception('Transcription returned empty text');
      }

      // Update with result
      _segments[segmentIndex] = _segments[segmentIndex].copyWith(
        text: text.trim(),
        status: TranscriptionSegmentStatus.completed,
      );
      if (!_segmentStreamController.isClosed) {
        _segmentStreamController.add(_segments[segmentIndex]);
      }

      debugPrint(
        '[AutoPauseTranscription] Segment ${segment.index} done: "$text"',
      );
    } catch (e) {
      debugPrint('[AutoPauseTranscription] Transcription failed: $e');

      // Clean up temp WAV file on error too
      try {
        final errorFile = File(
          path.join(_tempDirectory!, 'temp_segment_${segment.index}.wav'),
        );
        if (await errorFile.exists()) {
          await errorFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }

      _segments[segmentIndex] = _segments[segmentIndex].copyWith(
        text: '[Transcription failed]',
        status: TranscriptionSegmentStatus.failed,
      );
      if (!_segmentStreamController.isClosed) {
        _segmentStreamController.add(_segments[segmentIndex]);
      }
    }
  }

  /// Save complete recording as WAV file
  Future<void> _saveCompleteRecording() async {
    if (_audioFilePath == null || _allAudioSamples.isEmpty) return;

    // Flatten all samples
    final allSamples = <int>[];
    for (final chunk in _allAudioSamples) {
      allSamples.addAll(chunk);
    }

    // Save to WAV file
    await _saveSamplesToWav(allSamples, _audioFilePath!);

    debugPrint(
      '[AutoPauseTranscription] Saved complete recording: '
      '${allSamples.length} samples',
    );
  }

  /// Save int16 samples to WAV file
  Future<void> _saveSamplesToWav(List<int> samples, String filePath) async {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;

    final dataSize = samples.length * 2; // 2 bytes per sample
    final fileSize = 36 + dataSize;

    final bytes = BytesBuilder();

    // RIFF header
    bytes.add('RIFF'.codeUnits);
    bytes.add(_int32ToBytes(fileSize));
    bytes.add('WAVE'.codeUnits);

    // fmt chunk
    bytes.add('fmt '.codeUnits);
    bytes.add(_int32ToBytes(16)); // fmt chunk size
    bytes.add(_int16ToBytes(1)); // PCM format
    bytes.add(_int16ToBytes(numChannels));
    bytes.add(_int32ToBytes(sampleRate));
    bytes.add(
      _int32ToBytes(sampleRate * numChannels * bitsPerSample ~/ 8),
    ); // byte rate
    bytes.add(_int16ToBytes(numChannels * bitsPerSample ~/ 8)); // block align
    bytes.add(_int16ToBytes(bitsPerSample));

    // data chunk
    bytes.add('data'.codeUnits);
    bytes.add(_int32ToBytes(dataSize));

    // Sample data (int16 little-endian)
    for (final sample in samples) {
      bytes.add(_int16ToBytes(sample));
    }

    // Write to file
    final file = File(filePath);
    await file.writeAsBytes(bytes.toBytes());
  }

  /// Convert int32 to little-endian bytes
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = value & 0xFF
      ..[1] = (value >> 8) & 0xFF
      ..[2] = (value >> 16) & 0xFF
      ..[3] = (value >> 24) & 0xFF;
  }

  /// Convert int16 to little-endian bytes
  Uint8List _int16ToBytes(int value) {
    // Ensure value is in int16 range
    final clamped = value.clamp(-32768, 32767);
    final unsigned = clamped < 0 ? clamped + 65536 : clamped;
    return Uint8List(2)
      ..[0] = unsigned & 0xFF
      ..[1] = (unsigned >> 8) & 0xFF;
  }

  /// Get complete transcript (all segments combined)
  String getCompleteTranscript() {
    return _segments
        .where((s) => s.status.toString().contains('completed'))
        .map((s) => s.text)
        .join('\n\n');
  }

  /// Alias for V2 compatibility
  String getCombinedText() => getCompleteTranscript();

  /// Convert byte array to int16 samples
  List<int> _bytesToInt16(Uint8List bytes) {
    final samples = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      if (i + 1 < bytes.length) {
        // Little-endian int16
        final sample = bytes[i] | (bytes[i + 1] << 8);
        // Convert to signed int16
        final signed = sample > 32767 ? sample - 65536 : sample;
        samples.add(signed);
      }
    }
    return samples;
  }

  /// Calculate RMS (Root Mean Square) energy for debugging
  double _calculateRMS(List<int> samples) {
    if (samples.isEmpty) return 0.0;
    double sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    return sqrt(sumSquares / samples.length);
  }

  /// Cleanup
  Future<void> dispose() async {
    await _recorder.dispose();
    await _segmentStreamController.close();
    await _processingStreamController.close();
    await _vadActivityController.close();
    await _debugMetricsController.close();

    // Clean up temp directory
    if (_tempDirectory != null) {
      try {
        final dir = Directory(_tempDirectory!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[AutoPauseTranscription] Cleanup failed: $e');
      }
    }
  }
}

/// Internal: Queued segment for processing
class _QueuedSegment {
  final int index;
  final List<int> samples;

  _QueuedSegment({required this.index, required this.samples});
}
