import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';

/// Desktop embedding service using Ollama
///
/// This service uses Ollama's REST API to generate embeddings locally
/// on desktop platforms (macOS, Linux, Windows).
///
/// Requires:
/// - Ollama installed: brew install ollama (macOS) or https://ollama.com (Linux/Windows)
/// - Ollama server running: ollama serve
/// - Embedding model downloaded: ollama pull nomic-embed-text
///
/// Supported models:
/// - nomic-embed-text: 768 dims, fast, good quality (default)
/// - mxbai-embed-large: 1024 dims, higher quality but slower
///
/// All embeddings are truncated to 256 dimensions for consistency with mobile.
class DesktopEmbeddingService implements EmbeddingService {
  final OllamaClient _client;
  OllamaEmbeddingModelType _modelType;

  static const int _targetDimensions = 256;

  DesktopEmbeddingService({
    OllamaClient? client,
    OllamaEmbeddingModelType modelType = OllamaEmbeddingModelType.nomicEmbedText,
  })  : _client = client ?? OllamaClient(),
        _modelType = modelType;

  @override
  int get dimensions => _targetDimensions;

  /// Check if Ollama is running and the model is available
  @override
  Future<bool> isReady() async {
    try {
      // Check if Ollama server is running
      final modelsResponse = await _client.listModels();

      // Check if our embedding model is available
      final availableModels = modelsResponse.models
              ?.map((model) => model.model ?? '')
              .where((name) => name.isNotEmpty)
              .toList() ??
          [];

      final isModelAvailable = availableModels.contains(_modelType.modelName);

      if (isModelAvailable) {
        debugPrint('[DesktopEmbedding] ✅ Model ${_modelType.modelName} is ready');
      } else {
        debugPrint('[DesktopEmbedding] ⚠️ Model ${_modelType.modelName} not found. Available: ${availableModels.join(", ")}');
      }

      return isModelAvailable;
    } catch (e) {
      debugPrint('[DesktopEmbedding] ❌ Ollama not available: $e');
      return false;
    }
  }

  /// Check if the model needs to be downloaded
  @override
  Future<bool> needsDownload() async {
    try {
      final isModelReady = await isReady();
      return !isModelReady;
    } catch (e) {
      debugPrint('[DesktopEmbedding] Error checking if download needed: $e');
      return true;
    }
  }

  /// Download the embedding model using Ollama
  ///
  /// Note: Ollama's pull operation doesn't provide streaming progress via the API,
  /// so we yield progress at start (0.0) and end (1.0) only.
  ///
  /// For actual progress tracking, users should run `ollama pull <model>` in terminal.
  @override
  Stream<double> downloadModel() async* {
    try {
      debugPrint('[DesktopEmbedding] Starting download of ${_modelType.modelName}...');

      // Check if Ollama is running
      try {
        await _client.listModels();
      } catch (e) {
        throw Exception(
          'Ollama is not running.\n\n'
          'Please install Ollama:\n'
          '  macOS: brew install ollama\n'
          '  Linux/Windows: https://ollama.com/download\n\n'
          'Then start the server:\n'
          '  ollama serve',
        );
      }

      yield 0.0;

      // Pull the model
      // Note: ollama_dart's pullModel doesn't provide progress streaming
      // Users can monitor progress by running: ollama pull <model> in terminal
      await _client.pullModel(
        request: PullModelRequest(
          model: _modelType.modelName,
          stream: false,
        ),
      );

      debugPrint('[DesktopEmbedding] ✅ Model ${_modelType.modelName} downloaded');
      yield 1.0;
    } catch (e) {
      debugPrint('[DesktopEmbedding] ❌ Download failed: $e');
      throw Exception('Failed to download model: $e');
    }
  }

  /// Embed a single text string
  ///
  /// Returns a normalized embedding vector truncated to 256 dimensions.
  @override
  Future<List<double>> embed(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Text cannot be empty');
    }

    try {
      // Check if ready before embedding
      if (!await isReady()) {
        throw Exception(
          'Model ${_modelType.modelName} is not ready.\n\n'
          'Please download it first:\n'
          '  ollama pull ${_modelType.modelName}',
        );
      }

      debugPrint('[DesktopEmbedding] Generating embedding for text: ${text.substring(0, text.length > 50 ? 50 : text.length)}...');

      // Generate embedding using Ollama
      final response = await _client.generateEmbedding(
        request: GenerateEmbeddingRequest(
          model: _modelType.modelName,
          prompt: text,
        ),
      );

      if (response.embedding == null || response.embedding!.isEmpty) {
        throw Exception('Ollama returned empty embedding');
      }

      final fullEmbedding = response.embedding!;
      debugPrint('[DesktopEmbedding] Received embedding with ${fullEmbedding.length} dimensions');

      // Truncate to target dimensions and renormalize
      final truncatedEmbedding = EmbeddingDimensionHelper.truncate(
        fullEmbedding,
        _targetDimensions,
        renormalize: true,
      );

      debugPrint('[DesktopEmbedding] ✅ Truncated to $_targetDimensions dimensions');
      return truncatedEmbedding;
    } catch (e) {
      debugPrint('[DesktopEmbedding] ❌ Embedding failed: $e');
      rethrow;
    }
  }

  /// Embed multiple texts in a batch
  ///
  /// Note: Ollama doesn't have native batch embedding support,
  /// so we process texts sequentially. For better performance with large batches,
  /// consider using isolates for parallel processing in the future.
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) {
      return [];
    }

    // Validate all texts are non-empty
    for (int i = 0; i < texts.length; i++) {
      if (texts[i].trim().isEmpty) {
        throw ArgumentError('Text at index $i is empty');
      }
    }

    debugPrint('[DesktopEmbedding] Embedding batch of ${texts.length} texts...');

    try {
      // Process sequentially
      final embeddings = <List<double>>[];
      for (int i = 0; i < texts.length; i++) {
        debugPrint('[DesktopEmbedding] Processing text ${i + 1}/${texts.length}');
        final embedding = await embed(texts[i]);
        embeddings.add(embedding);
      }

      debugPrint('[DesktopEmbedding] ✅ Batch embedding complete');
      return embeddings;
    } catch (e) {
      debugPrint('[DesktopEmbedding] ❌ Batch embedding failed: $e');
      rethrow;
    }
  }

  /// Change the embedding model
  ///
  /// This allows switching between different Ollama embedding models.
  /// The new model must be downloaded before use.
  void setModel(OllamaEmbeddingModelType modelType) {
    debugPrint('[DesktopEmbedding] Switching to model: ${modelType.modelName}');
    _modelType = modelType;
  }

  /// Get the current model type
  OllamaEmbeddingModelType get modelType => _modelType;

  /// Check if Ollama server is running (utility method)
  Future<bool> isOllamaAvailable() async {
    try {
      await _client.listModels();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get list of available Ollama models (utility method)
  Future<List<String>> getAvailableModels() async {
    try {
      final response = await _client.listModels();
      return response.models
              ?.map((model) => model.model ?? '')
              .where((name) => name.isNotEmpty)
              .toList() ??
          [];
    } catch (e) {
      debugPrint('[DesktopEmbedding] Failed to list models: $e');
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    debugPrint('[DesktopEmbedding] Disposing service');
    _client.endSession();
  }
}
