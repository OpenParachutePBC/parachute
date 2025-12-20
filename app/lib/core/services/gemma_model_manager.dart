import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:app/core/models/title_generation_models.dart';

/// Manages Gemma model downloads and lifecycle
///
/// Handles downloading, installing, and managing local Gemma models
/// for on-device title generation.
class GemmaModelManager {
  GemmaModelManager();

  /// Download and install a Gemma model
  ///
  /// Downloads from Parachute CDN (no authentication required).
  /// Returns a stream of progress updates (0.0 to 1.0)
  Stream<double> downloadModel(GemmaModelType modelType) async* {
    try {
      debugPrint(
        '[GemmaModelManager] Starting download for ${modelType.modelName}',
      );
      debugPrint('[GemmaModelManager] Download URL: ${modelType.downloadUrl}');

      // Check if already installed
      final isAlreadyInstalled = await isModelDownloaded(modelType);
      if (isAlreadyInstalled) {
        debugPrint(
          '[GemmaModelManager] ✅ Model ${modelType.modelName} already installed',
        );
        yield 1.0;
        return;
      }

      // Create a stream controller for progress updates
      final progressController = StreamController<double>();

      // Start the download in a separate async operation
      final downloadFuture =
          FlutterGemma.installModel(modelType: ModelType.gemmaIt)
              .fromNetwork(modelType.downloadUrl) // No token needed!
              .withProgress((progress) {
                // progress is an int from 0-100
                final progressValue = progress / 100.0;
                debugPrint('[GemmaModelManager] Download progress: $progress%');
                progressController.add(progressValue);
              })
              .install();

      // Yield progress updates as they come in
      await for (final progress in progressController.stream) {
        yield progress;

        // Check if download is complete
        if (progress >= 1.0) {
          break;
        }
      }

      // Wait for download to complete
      await downloadFuture;

      // Close the controller
      await progressController.close();

      yield 1.0; // Ensure we end at 100%
      debugPrint(
        '[GemmaModelManager] ✅ Model ${modelType.modelName} downloaded successfully',
      );
    } catch (e) {
      debugPrint('[GemmaModelManager] ❌ Download failed: $e');
      rethrow;
    }
  }

  /// Check if a model is downloaded
  Future<bool> isModelDownloaded(GemmaModelType modelType) async {
    try {
      // Extract the model filename from the download URL
      // e.g., "https://.../.../gemma3-270m-it-q8.task" -> "gemma3-270m-it-q8.task"
      final uri = Uri.parse(modelType.downloadUrl);
      final filename = uri.pathSegments.last;

      // Use flutter_gemma's API to check if model is installed
      final isInstalled = await FlutterGemma.isModelInstalled(filename);

      debugPrint(
        '[GemmaModelManager] Model ${modelType.modelName} ($filename) installed: $isInstalled',
      );
      return isInstalled;
    } catch (e) {
      debugPrint('[GemmaModelManager] Error checking model: $e');
      return false;
    }
  }

  /// Delete a downloaded model
  ///
  /// Note: flutter_gemma doesn't currently provide an API to delete specific models.
  /// This method throws an exception to inform the user.
  Future<void> deleteModel(GemmaModelType modelType) async {
    // TODO: flutter_gemma doesn't provide deleteModel(filename) API yet
    // Users must manually clear app data or reinstall to remove models
    throw UnimplementedError(
      'Model deletion is not currently supported. '
      'To free up space, please clear app data or reinstall the app. '
      'Model deletion API coming in future flutter_gemma updates.',
    );
  }

  /// Get total storage used by all models
  Future<String> getStorageInfo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/models');

      if (!await modelsDir.exists()) {
        return '0 MB used';
      }

      int totalBytes = 0;
      await for (final entity in modelsDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalBytes += stat.size;
        }
      }

      final totalMB = totalBytes / (1024 * 1024);
      if (totalMB < 1000) {
        return '${totalMB.toStringAsFixed(1)} MB used';
      } else {
        final totalGB = totalMB / 1000;
        return '${totalGB.toStringAsFixed(2)} GB used';
      }
    } catch (e) {
      debugPrint('[GemmaModelManager] Error calculating storage: $e');
      return '0 MB used';
    }
  }

  /// Get model instance for inference
  ///
  /// Creates a FlutterGemma model configured for title generation.
  /// Note: maxTokens is the TOTAL token budget (input + output combined).
  ///
  /// Automatically loads the preferred model if no model is currently active.
  Future<InferenceModel> getModel({
    int maxTokens = 128,
    GemmaModelType? modelType,
  }) async {
    try {
      debugPrint(
        '[GemmaModelManager] Creating model instance (maxTokens: $maxTokens)',
      );

      try {
        // Try to get the currently active model
        final model = await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: PreferredBackend.gpu,
        );
        debugPrint('[GemmaModelManager] ✅ Using active model');
        return model;
      } catch (e) {
        // No active model - need to load one
        debugPrint(
          '[GemmaModelManager] No active model, loading preferred model...',
        );

        if (modelType == null) {
          throw Exception(
            'No active model set and no modelType provided. '
            'Please download and select a model in Settings.',
          );
        }

        // Check if model is already installed
        final isInstalled = await isModelDownloaded(modelType);

        if (isInstalled) {
          // Model is installed but not active - activate it using setModelPath
          debugPrint(
            '[GemmaModelManager] Model ${modelType.modelName} is installed, activating it...',
          );

          // Re-install to activate (will skip download since already installed)
          await FlutterGemma.installModel(
            modelType: ModelType.gemmaIt,
          ).fromNetwork(modelType.downloadUrl).install();

          // Now get the active model
          final model = await FlutterGemma.getActiveModel(
            maxTokens: maxTokens,
            preferredBackend: PreferredBackend.gpu,
          );

          debugPrint('[GemmaModelManager] ✅ Model re-activated successfully');
          return model;
        }

        // Model not installed - install it
        debugPrint('[GemmaModelManager] Installing ${modelType.modelName}...');

        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(modelType.downloadUrl).install();

        debugPrint('[GemmaModelManager] Model installed, activating it...');

        // After installation, get the active model
        final model = await FlutterGemma.getActiveModel(
          maxTokens: maxTokens,
          preferredBackend: PreferredBackend.gpu,
        );

        debugPrint('[GemmaModelManager] ✅ Model installed and activated');
        return model;
      }
    } catch (e) {
      // Check for platform channel errors (common after first install)
      if (e.toString().contains('channel-error') ||
          e.toString().contains('Unable to establish connection')) {
        debugPrint(
          '[GemmaModelManager] ⚠️ Platform channel error - app restart required',
        );
        throw Exception(
          'Model activation requires an app restart.\n\n'
          'Please close and reopen the app, then try again.\n\n'
          'This is a one-time requirement after downloading a model.',
        );
      }

      // Check for corrupted model file (zip archive errors)
      if (e.toString().contains('Unable to open zip archive') ||
          e.toString().contains('zip_utils.cc')) {
        debugPrint('[GemmaModelManager] ⚠️ Model file appears to be corrupted');
        throw Exception(
          'Model file is corrupted. Please:\n'
          '1. Clear app data (Settings → Apps → Parachute → Clear Data)\n'
          '2. Reopen the app and re-download the model\n\n'
          'This can happen after app updates.',
        );
      }

      debugPrint('[GemmaModelManager] ❌ Failed to create model: $e');
      rethrow;
    }
  }

  /// Generate a single text completion (title)
  ///
  /// This is optimized for title generation: short, single-turn responses.
  /// Uses streaming API to properly decode tokens.
  Future<String> generateTitle({
    required InferenceModel model,
    required String prompt,
  }) async {
    try {
      debugPrint(
        '[GemmaModelManager] Generating title for prompt: "${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}..."',
      );

      // Create a chat session with temperature for creativity
      final chat = await model.createChat(
        temperature: 0.3,
        topK: 40,
        randomSeed: 1,
      );

      // Add the user's query
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      // Use streaming API to properly decode tokens
      // The sync API (generateChatResponse) seems to return raw token IDs
      final responseBuffer = StringBuffer();

      debugPrint('[GemmaModelManager] Starting streaming response...');
      await for (final response in chat.generateChatResponseAsync()) {
        if (response is TextResponse) {
          final token = response.token;
          debugPrint('[GemmaModelManager] Received token: "$token"');
          responseBuffer.write(token);
        }
      }

      final responseText = responseBuffer.toString().trim();
      debugPrint('[GemmaModelManager] ✅ Generated title: "$responseText"');

      // Note: InferenceChat doesn't have a close() method in flutter_gemma 0.11.8
      // Memory is automatically managed

      return responseText;
    } catch (e) {
      debugPrint('[GemmaModelManager] ❌ Title generation failed: $e');
      rethrow;
    }
  }
}
