import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

/// Flutter service for Parakeet ASR via sherpa-onnx (Android/cross-platform)
///
/// Uses Parakeet v3 INT8 ONNX models for fast, offline transcription.
/// Supports 25 European languages with automatic language detection.
class SherpaOnnxService {
  sherpa.OfflineRecognizer? _recognizer;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String _modelPath = '';

  bool get isInitialized => _isInitialized;
  bool get isSupported =>
      true; // sherpa-onnx supports all platforms (Android, iOS, macOS, etc.)

  /// Initialize Parakeet v3 models
  ///
  /// Downloads models from app assets to local storage if needed.
  /// First run may take time to copy assets (~640MB).
  ///
  /// [onProgress] - Optional callback for download/extraction progress (0.0-1.0)
  /// [onStatus] - Optional callback for status messages
  Future<void> initialize({
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    if (_isInitialized) {
      debugPrint('[SherpaOnnxService] Already initialized');
      onProgress?.call(1.0);
      onStatus?.call('Ready');
      return;
    }

    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      debugPrint(
        '[SherpaOnnxService] Initialization already in progress, waiting...',
      );
      onStatus?.call('Initialization in progress...');
      // Wait for the ongoing initialization to complete
      while (_isInitializing && !_isInitialized) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (_isInitialized) {
        onProgress?.call(1.0);
        onStatus?.call('Ready');
        return;
      }
      // If still not initialized after waiting, throw error
      throw StateError('Initialization failed');
    }

    _isInitializing = true;
    try {
      debugPrint('[SherpaOnnxService] Initializing Parakeet v3 INT8...');
      onStatus?.call('Initializing Parakeet v3...');

      // Copy models from assets to local storage (one-time operation)
      final modelDir = await _ensureModelsInLocalStorage(
        onProgress: onProgress,
        onStatus: onStatus,
      );
      _modelPath = modelDir;

      onStatus?.call('Configuring model...');
      onProgress?.call(0.9);

      // Configure Parakeet TDT model (Transducer)
      final modelConfig = sherpa.OfflineTransducerModelConfig(
        encoder: path.join(modelDir, 'encoder.int8.onnx'),
        decoder: path.join(modelDir, 'decoder.int8.onnx'),
        joiner: path.join(modelDir, 'joiner.int8.onnx'),
      );

      // Optimize thread count based on device capabilities
      // Most modern Android devices have 6-8 cores, use more threads for faster transcription
      final numThreads = Platform.numberOfProcessors;
      final optimalThreads = (numThreads * 0.75).ceil().clamp(4, 8);

      debugPrint(
        '[SherpaOnnxService] Device has $numThreads cores, using $optimalThreads threads',
      );

      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          transducer: modelConfig,
          tokens: path.join(modelDir, 'tokens.txt'),
          numThreads: optimalThreads,
          debug: kDebugMode,
          modelType:
              'nemo_transducer', // Use NeMo-specific type for Parakeet models
        ),
      );

      // Initialize sherpa-onnx native library (first time only)
      debugPrint('[SherpaOnnxService] Initializing native bindings...');
      onStatus?.call('Initializing native bindings...');
      sherpa.initBindings();

      debugPrint('[SherpaOnnxService] Creating recognizer...');
      onStatus?.call('Creating recognizer...');
      _recognizer = sherpa.OfflineRecognizer(config);

      _isInitialized = true;
      onProgress?.call(1.0);
      onStatus?.call('Ready');
      debugPrint('[SherpaOnnxService] ✅ Initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('[SherpaOnnxService] ❌ Initialization failed: $e');
      debugPrint('[SherpaOnnxService] Stack trace: $stackTrace');
      onStatus?.call('Initialization failed: $e');
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Download and extract model archive from GitHub if not already cached
  ///
  /// Returns the directory path where models are stored.
  Future<String> _ensureModelsInLocalStorage({
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = path.join(appDir.path, 'models', 'parakeet-v3');
    final modelDirFile = Directory(modelDir);

    // Check if models already exist and are valid
    final encoderFile = File(path.join(modelDir, 'encoder.int8.onnx'));
    final tokensFile = File(path.join(modelDir, 'tokens.txt'));

    if (await encoderFile.exists() && await tokensFile.exists()) {
      // Verify the files are not empty
      final encoderSize = await encoderFile.length();
      final tokensSize = await tokensFile.length();

      if (encoderSize > 100 * 1024 * 1024 && tokensSize > 1000) {
        debugPrint('[SherpaOnnxService] Valid models found');
        return modelDir;
      }

      // Models are corrupted, delete and re-download
      debugPrint(
        '[SherpaOnnxService] Corrupted models detected, cleaning up...',
      );
      if (await modelDirFile.exists()) {
        await modelDirFile.delete(recursive: true);
      }
    }

    debugPrint(
      '[SherpaOnnxService] Downloading Parakeet v3 archive (~465 MB)...',
    );
    onStatus?.call('Downloading Parakeet v3 models...');
    await modelDirFile.create(recursive: true);

    // Download tar.bz2 archive from GitHub
    const archiveUrl =
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2';
    final archivePath = path.join(
      appDir.path,
      'models',
      'parakeet-v3-int8.tar.bz2',
    );

    try {
      debugPrint('[SherpaOnnxService] Downloading from GitHub...');

      // Stream download with progress tracking
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(archiveUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      final totalBytes = response.contentLength ?? 465 * 1024 * 1024; // ~465MB
      int receivedBytes = 0;

      final archiveFile = File(archivePath);
      final sink = archiveFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        // Report download progress (0.0 - 0.7 of total)
        final downloadProgress = receivedBytes / totalBytes * 0.7;
        onProgress?.call(downloadProgress);

        // Update status every 50MB to reduce log spam
        if (receivedBytes % (50 * 1024 * 1024) < chunk.length) {
          final receivedMB = (receivedBytes / (1024 * 1024)).toStringAsFixed(0);
          final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(0);
          final percent = ((receivedBytes / totalBytes) * 100).toStringAsFixed(
            0,
          );
          onStatus?.call(
            'Downloading models: $percent% ($receivedMB/$totalMB MB)',
          );
        }
      }

      await sink.flush(); // Ensure all data is written
      await sink.close();
      client.close();

      // Validate download size
      final downloadedFile = File(archivePath);
      final actualSize = await downloadedFile.length();
      final sizeMB = (actualSize / (1024 * 1024)).toStringAsFixed(1);

      debugPrint('[SherpaOnnxService] ✅ Downloaded ($sizeMB MB)');

      // Verify we got all the data
      if (actualSize != receivedBytes) {
        throw Exception(
          'Download incomplete: expected $receivedBytes bytes, got $actualSize bytes',
        );
      }

      // Basic validation - file should be at least 400MB
      if (actualSize < 400 * 1024 * 1024) {
        throw Exception(
          'Downloaded file too small: $sizeMB MB (expected ~465 MB)',
        );
      }

      // Extract tar.bz2 archive in compute isolate to avoid UI freeze
      debugPrint('[SherpaOnnxService] Extracting archive...');
      onStatus?.call('Extracting models (this may take 1-2 minutes)...');
      onProgress?.call(0.75);

      await compute(_extractArchive, {
        'archivePath': archivePath,
        'modelDir': modelDir,
      });

      // Extraction complete
      debugPrint('[SherpaOnnxService] ✅ Extraction complete');
      onStatus?.call('Finalizing models...');
      onProgress?.call(0.85);

      // Clean up archive file
      await File(archivePath).delete();
      debugPrint('[SherpaOnnxService] ✅ Models ready');
      onStatus?.call('Models ready');

      return modelDir;
    } catch (e) {
      debugPrint('[SherpaOnnxService] ❌ Download/extract failed: $e');
      onStatus?.call('Download failed: $e');
      // Clean up on failure
      if (await File(archivePath).exists()) {
        await File(archivePath).delete();
      }
      rethrow;
    }
  }

  /// Extract tar.bz2 archive in separate isolate to avoid UI freeze
  static Future<void> _extractArchive(Map<String, String> params) async {
    final archivePath = params['archivePath']!;
    final modelDir = params['modelDir']!;

    // Read archive file
    debugPrint('[SherpaOnnxService] Reading archive...');
    final archiveBytes = await File(archivePath).readAsBytes();

    // Decompress bz2 (this takes most of the time)
    debugPrint('[SherpaOnnxService] Decompressing BZip2...');
    final decompressed = BZip2Decoder().decodeBytes(archiveBytes);

    // Extract tar
    debugPrint('[SherpaOnnxService] Extracting TAR archive...');
    final archive = TarDecoder().decodeBytes(decompressed);

    int extractedCount = 0;
    const targetFiles = [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
    ];

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        // Extract files from sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/ directory
        final basename = path.basename(filename);
        if (targetFiles.contains(basename)) {
          final outputPath = path.join(modelDir, basename);
          final outputFile = File(outputPath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          final sizeMB = (file.content.length / (1024 * 1024)).toStringAsFixed(
            1,
          );
          extractedCount++;
          debugPrint(
            '[SherpaOnnxService] ✅ Extracted $basename ($sizeMB MB) [$extractedCount/${targetFiles.length}]',
          );
        }
      }
    }

    debugPrint('[SherpaOnnxService] ✅ Extraction complete: $extractedCount files');
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
      final tokens = result.tokens;
      final timestamps = result.timestamps;

      // Free stream
      stream.free();

      final duration = DateTime.now().difference(startTime);

      debugPrint(
        '[SherpaOnnxService] ✅ Transcribed in ${duration.inMilliseconds}ms: "$text"',
      );
      debugPrint(
        '[SherpaOnnxService] Tokens: ${tokens.length}, Timestamps: ${timestamps.length}',
      );

      return TranscriptionResult(
        text: text,
        language: 'auto', // Parakeet auto-detects language
        duration: duration,
        tokens: tokens.isNotEmpty ? tokens : null,
        timestamps: timestamps.isNotEmpty ? timestamps : null,
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
  final List<String>? tokens;
  final List<double>? timestamps;

  TranscriptionResult({
    required this.text,
    required this.language,
    required this.duration,
    this.tokens,
    this.timestamps,
  });

  @override
  String toString() =>
      'TranscriptionResult(text: "$text", language: $language, duration: ${duration.inMilliseconds}ms, tokens: ${tokens?.length ?? 0}, timestamps: ${timestamps?.length ?? 0})';
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
