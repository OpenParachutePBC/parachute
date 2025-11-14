import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Flutter service for Parakeet ASR via sherpa-onnx (Android/cross-platform)
///
/// Uses Parakeet v3 INT8 ONNX models for fast, offline transcription.
/// Supports 25 European languages with automatic language detection.
class SherpaOnnxService {
  sherpa.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  String _modelPath = '';

  bool get isInitialized => _isInitialized;
  bool get isSupported => true; // sherpa-onnx supports all platforms

  /// Initialize Parakeet v3 models
  ///
  /// Downloads models from app assets to local storage if needed.
  /// First run may take time to copy assets (~640MB).
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('[SherpaOnnxService] Already initialized');
      return;
    }

    try {
      debugPrint('[SherpaOnnxService] Initializing Parakeet v3 INT8...');

      // Copy models from assets to local storage (one-time operation)
      final modelDir = await _ensureModelsInLocalStorage();
      _modelPath = modelDir;

      // Configure Parakeet TDT model (Transducer)
      final modelConfig = sherpa.OfflineTransducerModelConfig(
        encoder: path.join(modelDir, 'encoder.int8.onnx'),
        decoder: path.join(modelDir, 'decoder.int8.onnx'),
        joiner: path.join(modelDir, 'joiner.int8.onnx'),
      );

      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          transducer: modelConfig,
          tokens: path.join(modelDir, 'tokens.txt'),
          numThreads: 4, // Adjust based on device
          debug: kDebugMode,
          modelType: 'transducer',
        ),
      );

      // Initialize sherpa-onnx native library (first time only)
      debugPrint('[SherpaOnnxService] Initializing native bindings...');
      sherpa.initBindings();

      debugPrint('[SherpaOnnxService] Creating recognizer...');
      _recognizer = sherpa.OfflineRecognizer(config);

      _isInitialized = true;
      debugPrint('[SherpaOnnxService] ✅ Initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[SherpaOnnxService] ❌ Initialization failed: $e');
      debugPrint('[SherpaOnnxService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Copy model files from assets to local storage
  ///
  /// Returns the directory path where models are stored.
  Future<String> _ensureModelsInLocalStorage() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = path.join(appDir.path, 'models', 'parakeet-v3');
    final modelDirFile = Directory(modelDir);

    // Check if models already exist
    final encoderFile = File(path.join(modelDir, 'encoder.int8.onnx'));
    if (await encoderFile.exists()) {
      debugPrint('[SherpaOnnxService] Models already in local storage');
      return modelDir;
    }

    debugPrint('[SherpaOnnxService] Copying models from assets...');
    await modelDirFile.create(recursive: true);

    // List of files to copy
    final files = [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
    ];

    for (final fileName in files) {
      debugPrint('[SherpaOnnxService] Copying $fileName...');
      final assetPath = 'assets/models/parakeet-v3/$fileName';
      final destPath = path.join(modelDir, fileName);

      try {
        final data = await rootBundle.load(assetPath);
        final buffer = data.buffer;
        await File(destPath).writeAsBytes(
          buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        debugPrint('[SherpaOnnxService] ✅ Copied $fileName');
      } catch (e) {
        debugPrint('[SherpaOnnxService] ❌ Failed to copy $fileName: $e');
        rethrow;
      }
    }

    debugPrint('[SherpaOnnxService] All models copied successfully');
    return modelDir;
  }

  /// Transcribe audio file
  ///
  /// [audioPath] - Absolute path to WAV file (16kHz mono PCM16)
  ///
  /// Returns transcribed text with automatic language detection.
  Future<TranscriptionResult> transcribeAudio(String audioPath) async {
    if (!_isInitialized) {
      throw StateError('SherpaOnnx not initialized. Call initialize() first.');
    }

    if (_recognizer == null) {
      throw StateError('Recognizer is null after initialization');
    }

    // Validate file exists
    final file = File(audioPath);
    if (!await file.exists()) {
      throw ArgumentError('Audio file not found: $audioPath');
    }

    try {
      debugPrint('[SherpaOnnxService] Transcribing: $audioPath');
      final startTime = DateTime.now();

      // Create stream for this audio file
      final stream = _recognizer!.createStream();

      // Load audio file
      // Note: sherpa-onnx expects audio samples as Float32List
      // We need to read the WAV file and convert to samples
      final samples = await _loadWavFile(audioPath);

      // Accept waveform (16kHz sample rate)
      stream.acceptWaveform(samples: samples, sampleRate: 16000);

      // Decode (single call for offline recognition)
      _recognizer!.decode(stream);

      // Get result
      final result = _recognizer!.getResult(stream);
      final text = result.text;

      // Free stream
      stream.free();

      final duration = DateTime.now().difference(startTime);

      debugPrint(
        '[SherpaOnnxService] ✅ Transcribed in ${duration.inMilliseconds}ms: "$text"',
      );

      return TranscriptionResult(
        text: text,
        language: 'auto', // Parakeet auto-detects language
        duration: duration,
      );
    } catch (e, stackTrace) {
      debugPrint('[SherpaOnnxService] ❌ Transcription failed: $e');
      debugPrint('[SherpaOnnxService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Load WAV file and convert to Float32List samples
  ///
  /// Assumes 16kHz mono PCM16 WAV format (same as used by Whisper)
  Future<Float32List> _loadWavFile(String audioPath) async {
    final file = File(audioPath);
    final bytes = await file.readAsBytes();

    // WAV file format:
    // - First 44 bytes: WAV header
    // - Remaining bytes: PCM16 audio data (2 bytes per sample)

    if (bytes.length < 44) {
      throw ArgumentError('Invalid WAV file: too short');
    }

    // Skip 44-byte header, read PCM16 samples
    final numSamples = (bytes.length - 44) ~/ 2;
    final samples = Float32List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final byteIndex = 44 + (i * 2);
      // Read 16-bit signed integer (little-endian)
      final sample = (bytes[byteIndex + 1] << 8) | bytes[byteIndex];
      // Convert to signed int16
      final signedSample = sample > 32767 ? sample - 65536 : sample;
      // Normalize to [-1.0, 1.0]
      samples[i] = signedSample / 32768.0;
    }

    debugPrint('[SherpaOnnxService] Loaded ${samples.length} samples from WAV');
    return samples;
  }

  /// Check if SherpaOnnx is ready
  Future<bool> isReady() async {
    return _isInitialized && _recognizer != null;
  }

  /// Get model information
  Future<ModelInfo?> getModelInfo() async {
    if (!_isInitialized) return null;

    return ModelInfo(
      version: 'v3-int8',
      languageCount: 25,
      isInitialized: true,
      modelPath: _modelPath,
    );
  }

  /// Clean up resources
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
    debugPrint('[SherpaOnnxService] Disposed');
  }
}

/// Transcription result from Sherpa-ONNX
class TranscriptionResult {
  final String text;
  final String language;
  final Duration duration;

  TranscriptionResult({
    required this.text,
    required this.language,
    required this.duration,
  });

  @override
  String toString() =>
      'TranscriptionResult(text: "$text", language: $language, duration: ${duration.inMilliseconds}ms)';
}

/// Model information
class ModelInfo {
  final String version;
  final int languageCount;
  final bool isInitialized;
  final String modelPath;

  ModelInfo({
    required this.version,
    required this.languageCount,
    required this.isInitialized,
    required this.modelPath,
  });

  @override
  String toString() =>
      'ModelInfo(version: $version, languages: $languageCount, initialized: $isInitialized, path: $modelPath)';
}
