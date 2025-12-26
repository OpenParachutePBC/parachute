import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  ///
  /// Set [force] to true to re-download even if already installed.
  Stream<double> downloadModel(GemmaModelType modelType, {bool force = false}) async* {
    try {
      debugPrint(
        '[GemmaModelManager] Starting download for ${modelType.modelName} (force: $force)',
      );
      debugPrint('[GemmaModelManager] Download URL: ${modelType.downloadUrl}');

      // Check if already installed (skip check if forcing)
      if (!force) {
        final isAlreadyInstalled = await isModelDownloaded(modelType);
        if (isAlreadyInstalled) {
          debugPrint(
            '[GemmaModelManager] ✅ Model ${modelType.modelName} already installed',
          );
          yield 1.0;
          return;
        }
      } else {
        debugPrint('[GemmaModelManager] Force download - skipping installed check');
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

  /// Force reinstall a model (re-download even if already installed)
  ///
  /// Useful when the model file is corrupted or engine fails to initialize.
  /// Attempts to delete existing model files before re-downloading.
  Stream<double> reinstallModel(GemmaModelType modelType) async* {
    try {
      debugPrint(
        '[GemmaModelManager] Force reinstalling ${modelType.modelName}...',
      );

      // Try to delete existing model files to force a clean download
      await _deleteModelFiles(modelType);

      // Force download - this will re-download
      yield* downloadModel(modelType, force: true);

      debugPrint('[GemmaModelManager] ✅ Model reinstalled successfully');
    } catch (e) {
      debugPrint('[GemmaModelManager] ❌ Reinstall failed: $e');
      rethrow;
    }
  }

  /// Attempt to delete model files and clear flutter_gemma's metadata
  Future<void> _deleteModelFiles(GemmaModelType modelType) async {
    try {
      final uri = Uri.parse(modelType.downloadUrl);
      final filename = uri.pathSegments.last;

      debugPrint('[GemmaModelManager] Attempting to delete model via flutter_gemma API: $filename');

      // Use flutter_gemma's official uninstallModel API
      // This properly removes both metadata from repository AND files from disk
      try {
        await FlutterGemma.uninstallModel(filename);
        debugPrint('[GemmaModelManager] ✓ FlutterGemma.uninstallModel($filename) succeeded');
      } catch (e) {
        debugPrint('[GemmaModelManager] FlutterGemma.uninstallModel failed: $e');
        // Fall back to manual clearing if official API fails
      }

      // Also manually clear SharedPreferences metadata as backup
      // in case the official API didn't fully clear everything
      await _clearFlutterGemmaMetadata(filename);

      // Manual file cleanup as additional safety
      final dir = await getApplicationDocumentsDirectory();
      await _deleteInDirectory(dir.path, filename);

      // Check app support directory (iOS/macOS)
      try {
        final supportDir = await getApplicationSupportDirectory();
        await _deleteInDirectory(supportDir.path, filename);
      } catch (_) {}

      // Check cache directory
      try {
        final cacheDir = await getTemporaryDirectory();
        await _deleteInDirectory(cacheDir.path, filename);
      } catch (_) {}

      // Also try to find any .task or .litertlm files in the app directories
      await _deleteByExtension(dir.path, ['.task', '.litertlm']);

      debugPrint('[GemmaModelManager] ✅ Model deletion complete for: $filename');
    } catch (e) {
      debugPrint('[GemmaModelManager] Error during file deletion: $e');
      // Continue anyway - the download might still work
    }
  }

  /// Clear flutter_gemma's SharedPreferences metadata for a model
  ///
  /// Flutter_gemma's SharedPreferencesModelRepository tracks installed models:
  /// - 'model_{id}': JSON metadata for each model
  /// - 'model_index': JSON array of all installed model IDs
  ///
  /// Note: flutter_gemma may use either filename or baseName as ID depending on version,
  /// so we clear both variants to be safe.
  Future<void> _clearFlutterGemmaMetadata(String filename) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Force reload from disk first to ensure we have latest state
      await prefs.reload();

      // Get baseName by removing known extensions
      String baseName = filename;
      const extensions = ['.task', '.bin', '.tflite', '.json', '.model', '.litertlm'];
      for (final ext in extensions) {
        baseName = baseName.replaceAll(ext, '');
      }

      debugPrint('[GemmaModelManager] === CLEARING METADATA ===');
      debugPrint('[GemmaModelManager] filename: $filename');
      debugPrint('[GemmaModelManager] baseName: $baseName');

      // List ALL model-related keys in SharedPreferences for debugging
      final allKeys = prefs.getKeys();
      final modelKeys = allKeys.where((k) => k.startsWith('model_') || k.contains('gemma')).toList();
      debugPrint('[GemmaModelManager] Found ${modelKeys.length} model-related keys: $modelKeys');

      // Clear ALL keys that might be related to this model
      // flutter_gemma might use filename OR baseName as the key
      final keysToRemove = [
        'model_$filename',           // model_gemma3-1b-it-int4.task
        'model_$baseName',           // model_gemma3-1b-it-int4
        filename,                     // gemma3-1b-it-int4.task
        baseName,                     // gemma3-1b-it-int4
      ];

      for (final key in keysToRemove) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          debugPrint('[GemmaModelManager] ✓ Removed key: $key');
        }
      }

      // Also remove any key containing the baseName (nuclear option)
      for (final key in modelKeys) {
        if (key.contains(baseName)) {
          await prefs.remove(key);
          debugPrint('[GemmaModelManager] ✓ Removed matching key: $key');
        }
      }

      // Clear model_index - remove both filename and baseName variants
      final indexJson = prefs.getString('model_index');
      if (indexJson != null) {
        debugPrint('[GemmaModelManager] model_index before: $indexJson');
        try {
          final index = (jsonDecode(indexJson) as List<dynamic>).cast<String>();
          final originalLength = index.length;
          index.removeWhere((id) => id == filename || id == baseName || id.contains(baseName));
          if (index.length != originalLength) {
            await prefs.setString('model_index', jsonEncode(index));
            debugPrint('[GemmaModelManager] ✓ Updated model_index: ${jsonEncode(index)}');
          }
        } catch (e) {
          await prefs.remove('model_index');
          debugPrint('[GemmaModelManager] ✓ Cleared corrupted model_index');
        }
      }

      // Clear legacy keys
      for (final legacyKey in ['protected_files', 'external_paths']) {
        final json = prefs.getString(legacyKey);
        if (json != null) {
          debugPrint('[GemmaModelManager] $legacyKey: $json');
          await prefs.remove(legacyKey);
          debugPrint('[GemmaModelManager] ✓ Cleared $legacyKey entirely');
        }
      }

      // Force reload AGAIN after clearing to ensure flutter_gemma sees the changes
      await prefs.reload();

      // Verify clearing worked
      final remainingKeys = prefs.getKeys().where((k) => k.startsWith('model_') || k.contains('gemma')).toList();
      debugPrint('[GemmaModelManager] Remaining model keys after clear: $remainingKeys');

      // Double-check the specific key that flutter_gemma will check
      final keyToCheck = 'model_$filename';
      final stillExists = prefs.containsKey(keyToCheck);
      debugPrint('[GemmaModelManager] Key "$keyToCheck" still exists: $stillExists');

      debugPrint('[GemmaModelManager] === METADATA CLEAR COMPLETE ===');
    } catch (e) {
      debugPrint('[GemmaModelManager] Error clearing metadata: $e');
    }
  }

  /// Delete model file from a directory and its subdirectories
  Future<void> _deleteInDirectory(String basePath, String filename) async {
    final possiblePaths = [
      '$basePath/$filename',
      '$basePath/models/$filename',
      '$basePath/flutter_gemma/$filename',
      '$basePath/gemma/$filename',
      '$basePath/litert/$filename',
    ];

    for (final path in possiblePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          debugPrint('[GemmaModelManager] Deleting: $path');
          await file.delete();
        }
      } catch (e) {
        debugPrint('[GemmaModelManager] Could not delete $path: $e');
      }
    }

    // Also check for the directory and delete all files in it
    for (final subdir in ['models', 'flutter_gemma', 'gemma', 'litert']) {
      try {
        final dir = Directory('$basePath/$subdir');
        if (await dir.exists()) {
          debugPrint('[GemmaModelManager] Checking directory: ${dir.path}');
          await for (final entity in dir.list()) {
            if (entity is File && entity.path.contains(filename.split('.').first)) {
              debugPrint('[GemmaModelManager] Deleting: ${entity.path}');
              await entity.delete();
            }
          }
        }
      } catch (e) {
        debugPrint('[GemmaModelManager] Error scanning $subdir: $e');
      }
    }
  }

  /// Delete all files with given extensions in a directory tree
  Future<void> _deleteByExtension(String basePath, List<String> extensions) async {
    try {
      final dir = Directory(basePath);
      if (!await dir.exists()) return;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final path = entity.path.toLowerCase();
          for (final ext in extensions) {
            if (path.endsWith(ext)) {
              debugPrint('[GemmaModelManager] Deleting by extension: ${entity.path}');
              await entity.delete();
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[GemmaModelManager] Error in _deleteByExtension: $e');
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
        return await _getActiveModelWithFallback(maxTokens);
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

          // Now get the active model (try GPU first, then CPU)
          return await _getActiveModelWithFallback(maxTokens);
        }

        // Model not installed - install it
        debugPrint('[GemmaModelManager] Installing ${modelType.modelName}...');

        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromNetwork(modelType.downloadUrl).install();

        debugPrint('[GemmaModelManager] Model installed, activating it...');

        // After installation, get the active model (try GPU first, then CPU)
        return await _getActiveModelWithFallback(maxTokens);
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

      // Check for engine initialization failure (MediaPipe LLM Inference)
      if (e.toString().contains('Failed to initialize') ||
          e.toString().contains('failed to initialize') ||
          e.toString().contains('java.lang.RuntimeException') ||
          e.toString().contains('RuntimeException')) {
        debugPrint('[GemmaModelManager] ⚠️ Engine initialization failed');
        throw Exception(
          'Failed to initialize AI engine.\n\n'
          'This may be a device compatibility issue. Try:\n'
          '1. Restart the app\n'
          '2. Clear app data and re-download the model\n'
          '3. Check if your device supports GPU acceleration',
        );
      }

      debugPrint('[GemmaModelManager] ❌ Failed to create model: $e');
      rethrow;
    }
  }

  /// Helper to get active model with fallback chain: Auto -> GPU -> CPU
  Future<InferenceModel> _getActiveModelWithFallback(int maxTokens) async {
    // First, try without specifying backend - let MediaPipe auto-select
    // This is the most compatible option for unusual devices
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        // No preferredBackend - let MediaPipe choose
      );
      debugPrint('[GemmaModelManager] ✅ Using model (auto-selected backend)');
      return model;
    } catch (autoError) {
      debugPrint('[GemmaModelManager] Auto-select failed ($autoError), trying GPU...');
    }

    // Second, try GPU explicitly
    Object? gpuError;
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.gpu,
      );
      debugPrint('[GemmaModelManager] ✅ Using model (GPU)');
      return model;
    } catch (e) {
      gpuError = e;
      debugPrint('[GemmaModelManager] GPU failed ($e), trying CPU...');
    }

    // Third, try CPU explicitly
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: PreferredBackend.cpu,
      );
      debugPrint('[GemmaModelManager] ✅ Using model (CPU fallback)');
      return model;
    } catch (cpuError) {
      debugPrint('[GemmaModelManager] CPU also failed: $cpuError');
      // Throw the auto error as it's the first attempt
      throw Exception(
        'Failed to initialize AI model on all backends.\n\n'
        'Auto-select error: $gpuError\n'
        'CPU error: $cpuError\n\n'
        'This device may not support MediaPipe LLM Inference.',
      );
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
