import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Service for compressing audio files to Opus format using ffmpeg
///
/// Converts WAV files to Opus for efficient storage and Git sync
/// Uses system ffmpeg for reliable compression
class AudioCompressionService {
  static const int _bitrate = 64000; // 64kbps (good quality for voice)

  /// Compress a WAV file to Opus format using ffmpeg
  ///
  /// Returns the path to the compressed Opus file
  /// Deletes the original WAV file after successful compression
  Future<String> compressToOpus({
    required String wavPath,
    bool deleteOriginal = true,
  }) async {
    try {
      debugPrint('[AudioCompression] Compressing: $wavPath');

      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('WAV file not found: $wavPath');
      }

      // Get original file size
      final originalSize = await wavFile.length();

      // Generate output path
      final opusPath = wavPath.replaceAll('.wav', '.opus');

      // Run ffmpeg command
      // -i: input file
      // -c:a libopus: use Opus audio codec
      // -b:a: audio bitrate
      // -vbr on: enable variable bitrate for better quality
      // -compression_level 10: max compression (0-10)
      // -frame_duration 60: frame duration in ms (20, 40, or 60)
      // -application voip: optimize for voice
      // -y: overwrite output file without asking
      final result = await Process.run('ffmpeg', [
        '-i',
        wavPath,
        '-c:a',
        'libopus',
        '-b:a',
        '${_bitrate}',
        '-vbr',
        'on',
        '-compression_level',
        '10',
        '-frame_duration',
        '60',
        '-application',
        'voip',
        '-y',
        opusPath,
      ]);

      if (result.exitCode != 0) {
        throw Exception('ffmpeg failed: ${result.stderr}');
      }

      // Get compressed file size
      final compressedSize = await File(opusPath).length();

      // Calculate compression ratio
      final originalMB = originalSize / 1024 / 1024;
      final compressedMB = compressedSize / 1024 / 1024;
      final compressionRatio = (1 - compressedSize / originalSize) * 100;

      debugPrint(
        '[AudioCompression] ✅ Compressed: ${originalMB.toStringAsFixed(2)}MB → ${compressedMB.toStringAsFixed(2)}MB (${compressionRatio.toStringAsFixed(1)}% reduction)',
      );

      // Delete original WAV file if requested
      if (deleteOriginal) {
        await wavFile.delete();
        debugPrint('[AudioCompression] Deleted original WAV file');
      }

      return opusPath;
    } catch (e, stackTrace) {
      debugPrint('[AudioCompression] ❌ Error compressing audio: $e');
      debugPrint('[AudioCompression] Stack trace: $stackTrace');
      rethrow;
    }
  }
}
