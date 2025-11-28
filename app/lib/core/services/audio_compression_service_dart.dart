import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:opus_dart/opus_dart.dart' as opus_dart;

/// Pure Dart audio compression service using opus_dart
///
/// Converts WAV files to Opus format without relying on ffmpeg
/// This avoids sandboxing issues on macOS and other platforms
class AudioCompressionServiceDart {
  /// Check if Opus library has been initialized
  /// Must call opus_dart.initOpus() in main.dart before using this service
  static bool get isOpusInitialized {
    try {
      // Try to get version - this will throw if not initialized
      opus_dart.getOpusVersion();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Ensure Opus is initialized before operations
  void _ensureOpusInitialized() {
    if (!isOpusInitialized) {
      throw Exception(
        'Opus library not initialized. '
        'Ensure opus_dart.initOpus() is called in main.dart before using audio compression. '
        'On macOS, this requires libopus.dylib to be bundled with the app.',
      );
    }
  }

  /// Compress a WAV file to Opus format using pure Dart
  ///
  /// Returns the path to the compressed Opus file
  /// Note: WAV files are deleted by default; they're recreated on-demand for playback
  Future<String> compressToOpus({
    required String wavPath,
    bool deleteOriginal = true,
  }) async {
    try {
      // Verify Opus is initialized before attempting compression
      _ensureOpusInitialized();

      debugPrint('[AudioCompressionDart] Compressing: $wavPath');

      final wavFile = File(wavPath);
      if (!await wavFile.exists()) {
        throw Exception('WAV file not found: $wavPath');
      }

      // Get original file size
      final originalSize = await wavFile.length();

      // Read WAV file
      final wavBytes = await wavFile.readAsBytes();

      // Parse WAV header and extract PCM data
      final pcmData = _extractPcmFromWav(wavBytes);
      final wavHeader = _parseWavHeader(wavBytes);

      debugPrint(
        '[AudioCompressionDart] WAV header: ${wavHeader['sampleRate']}Hz, ${wavHeader['channels']} channels, ${wavHeader['bitsPerSample']} bits',
      );

      // Encode PCM to Opus
      final opusData = await _encodePcmToOpus(
        pcmData: pcmData,
        sampleRate: wavHeader['sampleRate'] as int,
        channels: wavHeader['channels'] as int,
      );

      // Generate output path
      final opusPath = wavPath.replaceAll('.wav', '.opus');

      // Write Opus file
      await File(opusPath).writeAsBytes(opusData);

      // Get compressed file size
      final compressedSize = await File(opusPath).length();

      // Calculate compression ratio
      final originalMB = originalSize / 1024 / 1024;
      final compressedMB = compressedSize / 1024 / 1024;
      final compressionRatio = (1 - compressedSize / originalSize) * 100;

      debugPrint(
        '[AudioCompressionDart] ✅ Compressed: ${originalMB.toStringAsFixed(2)}MB → ${compressedMB.toStringAsFixed(2)}MB (${compressionRatio.toStringAsFixed(1)}% reduction)',
      );

      // Delete original WAV file if requested
      if (deleteOriginal) {
        await wavFile.delete();
        debugPrint('[AudioCompressionDart] Deleted original WAV file');
      }

      return opusPath;
    } catch (e, stackTrace) {
      debugPrint('[AudioCompressionDart] ❌ Error compressing audio: $e');
      debugPrint('[AudioCompressionDart] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Parse WAV header to extract audio format information
  Map<String, dynamic> _parseWavHeader(Uint8List wavBytes) {
    if (wavBytes.length < 44) {
      throw Exception('Invalid WAV file: too short');
    }

    final byteData = ByteData.sublistView(wavBytes);

    // Check RIFF header
    final riff = String.fromCharCodes(wavBytes.sublist(0, 4));
    if (riff != 'RIFF') {
      throw Exception('Invalid WAV file: missing RIFF header');
    }

    // Check WAVE format
    final wave = String.fromCharCodes(wavBytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw Exception('Invalid WAV file: missing WAVE format');
    }

    // Find fmt chunk (it may not be at offset 12 due to JUNK or other chunks)
    int fmtOffset = 12;
    int? fmtChunkSize;
    while (fmtOffset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(
        wavBytes.sublist(fmtOffset, fmtOffset + 4),
      );
      final chunkSize = byteData.getUint32(fmtOffset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        fmtChunkSize = chunkSize;
        break;
      }

      // Skip this chunk and move to next
      fmtOffset += 8 + chunkSize;
    }

    if (fmtChunkSize == null) {
      throw Exception('Invalid WAV file: missing fmt chunk');
    }

    // Extract audio format from fmt chunk
    final audioFormat = byteData.getUint16(fmtOffset + 8, Endian.little);

    // Note: audioFormat 0xFFFE is WAVE_FORMAT_EXTENSIBLE
    // For our purposes, we'll accept both 1 (PCM) and 0xFFFE (extensible PCM)
    if (audioFormat != 1 && audioFormat != 0xFFFE) {
      throw Exception(
        'Unsupported WAV format: 0x${audioFormat.toRadixString(16)} (only PCM is supported)',
      );
    }

    // Extract format details (relative to fmt chunk start)
    final channels = byteData.getUint16(fmtOffset + 10, Endian.little);
    final sampleRate = byteData.getUint32(fmtOffset + 12, Endian.little);
    final bitsPerSample = byteData.getUint16(fmtOffset + 22, Endian.little);

    // Find data chunk (start search after fmt chunk)
    int dataOffset = fmtOffset + 8 + fmtChunkSize;
    while (dataOffset < wavBytes.length - 8) {
      final chunkId = String.fromCharCodes(
        wavBytes.sublist(dataOffset, dataOffset + 4),
      );
      final chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);

      if (chunkId == 'data') {
        return {
          'channels': channels,
          'sampleRate': sampleRate,
          'bitsPerSample': bitsPerSample,
          'dataOffset': dataOffset + 8,
          'dataSize': chunkSize,
        };
      }

      dataOffset += 8 + chunkSize;
    }

    throw Exception('Invalid WAV file: missing data chunk');
  }

  /// Extract PCM data from WAV file
  Uint8List _extractPcmFromWav(Uint8List wavBytes) {
    final header = _parseWavHeader(wavBytes);
    final dataOffset = header['dataOffset'] as int;
    final dataSize = header['dataSize'] as int;

    if (dataOffset + dataSize > wavBytes.length) {
      throw Exception('Invalid WAV file: data chunk exceeds file size');
    }

    return wavBytes.sublist(dataOffset, dataOffset + dataSize);
  }

  /// Encode PCM data to Opus format
  Future<Uint8List> _encodePcmToOpus({
    required Uint8List pcmData,
    required int sampleRate,
    required int channels,
  }) async {
    debugPrint(
      '[AudioCompressionDart] Encoding PCM to Opus: $sampleRate Hz, $channels channels',
    );

    try {
      // Create Opus encoder
      // For voice, we use Application.voip optimized for voice
      final encoder = opus_dart.SimpleOpusEncoder(
        sampleRate: sampleRate,
        channels: channels,
        application: opus_dart.Application.voip,
      );

      // Convert PCM bytes to Int16List samples
      final samples = _pcmBytesToInt16List(pcmData);

      debugPrint('[AudioCompressionDart] PCM samples: ${samples.length}');

      // Calculate frame size in samples (not bytes)
      // For 60ms frames at 16kHz: 16000 * 0.06 = 960 samples per channel
      final frameSizePerChannel = (sampleRate * 0.06).round();
      final frameSizeTotal = frameSizePerChannel * channels;

      debugPrint(
        '[AudioCompressionDart] Frame size: $frameSizeTotal samples ($frameSizePerChannel per channel)',
      );

      // Encode in chunks
      final encodedChunks = <Uint8List>[];
      int offset = 0;

      while (offset < samples.length) {
        final remaining = samples.length - offset;
        final chunkSize = remaining < frameSizeTotal
            ? remaining
            : frameSizeTotal;

        // Get chunk of samples as Int16List
        final chunk = Int16List.sublistView(
          samples,
          offset,
          offset + chunkSize,
        );

        // Pad last frame if needed
        final frame = chunkSize < frameSizeTotal
            ? _padFrameInt16(chunk, frameSizeTotal)
            : chunk;

        // Encode frame
        final encoded = encoder.encode(input: frame);
        encodedChunks.add(encoded);

        offset += chunkSize;
      }

      debugPrint(
        '[AudioCompressionDart] Encoded ${encodedChunks.length} Opus frames',
      );

      // Destroy encoder to free resources
      encoder.destroy();

      // Combine all encoded chunks with length prefixes (4 bytes per frame)
      // Format: [length1(4bytes)][frame1][length2(4bytes)][frame2]...
      final totalSize = encodedChunks.fold<int>(
        0,
        (sum, chunk) => sum + chunk.length + 4, // +4 for length prefix
      );
      final result = Uint8List(totalSize);
      final byteData = ByteData.sublistView(result);
      int writeOffset = 0;

      for (final chunk in encodedChunks) {
        // Write frame length (4 bytes, little-endian)
        byteData.setUint32(writeOffset, chunk.length, Endian.little);
        writeOffset += 4;

        // Write frame data
        result.setRange(writeOffset, writeOffset + chunk.length, chunk);
        writeOffset += chunk.length;
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint('[AudioCompressionDart] ❌ Opus encoding error: $e');
      debugPrint('[AudioCompressionDart] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Convert PCM bytes (little-endian Int16) to Int16List samples
  Int16List _pcmBytesToInt16List(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    final samples = Int16List(sampleCount);
    final byteData = ByteData.sublistView(pcmBytes);

    for (int i = 0; i < sampleCount; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little);
    }

    return samples;
  }

  /// Pad Int16List frame with zeros to reach target size
  Int16List _padFrameInt16(Int16List frame, int targetSize) {
    if (frame.length >= targetSize) return frame;

    final padded = Int16List(targetSize);
    padded.setRange(0, frame.length, frame);
    return padded;
  }

  /// Decompress an Opus file to WAV format
  ///
  /// Returns the path to the decompressed WAV file
  Future<String> decompressToWav({
    required String opusPath,
    String? outputPath,
  }) async {
    try {
      // Verify Opus is initialized before attempting decompression
      _ensureOpusInitialized();

      debugPrint('[AudioCompressionDart] Decompressing: $opusPath');

      final opusFile = File(opusPath);
      if (!await opusFile.exists()) {
        throw Exception('Opus file not found: $opusPath');
      }

      // Read Opus file
      final opusBytes = await opusFile.readAsBytes();
      debugPrint(
        '[AudioCompressionDart] Opus file size: ${opusBytes.length} bytes',
      );

      // Decode Opus frames to PCM
      final pcmData = await _decodeOpusToPcm(opusBytes);

      // For Parakeet transcription, use 16kHz mono
      const sampleRate = 16000;
      const channels = 1;

      // Build WAV file
      final wavBytes = _buildWavFile(
        pcmData: pcmData,
        sampleRate: sampleRate,
        channels: channels,
      );

      // Generate output path
      final wavPath = outputPath ?? opusPath.replaceAll('.opus', '.temp.wav');

      // Write WAV file
      await File(wavPath).writeAsBytes(wavBytes);

      debugPrint(
        '[AudioCompressionDart] ✅ Decompressed: ${wavBytes.length} bytes -> $wavPath',
      );

      return wavPath;
    } catch (e, stackTrace) {
      debugPrint('[AudioCompressionDart] ❌ Error decompressing audio: $e');
      debugPrint('[AudioCompressionDart] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Decode length-prefixed Opus frames to PCM samples
  ///
  /// Supports both new format (with length prefixes) and old format (without).
  /// Old format files are detected and an error is thrown with guidance.
  Future<Int16List> _decodeOpusToPcm(Uint8List opusBytes) async {
    // For Parakeet, use 16kHz mono
    const sampleRate = 16000;
    const channels = 1;

    final decoder = opus_dart.SimpleOpusDecoder(
      sampleRate: sampleRate,
      channels: channels,
    );

    final pcmSamples = <int>[];
    final byteData = ByteData.sublistView(opusBytes);
    int readOffset = 0;

    try {
      // Check if this is the old format (no length prefixes)
      // New format: first 4 bytes are frame length (typically 100-2000)
      // Old format: first bytes are Opus header (various values)
      final firstLength = byteData.getUint32(0, Endian.little);

      // Heuristic: if first "length" is unreasonably large (> 10KB) or
      // would exceed file size, it's probably old format
      if (firstLength > 10000 || firstLength + 4 > opusBytes.length) {
        throw Exception(
          'This Opus file uses old format without frame boundaries. '
          'Re-record or use a device with updated encoder to transcribe.',
        );
      }

      // Read frames with length prefixes
      // Format: [length1(4bytes)][frame1][length2(4bytes)][frame2]...
      while (readOffset < opusBytes.length - 4) {
        // Read frame length (4 bytes, little-endian)
        final frameLength = byteData.getUint32(readOffset, Endian.little);
        readOffset += 4;

        // Sanity check frame length
        if (frameLength > 10000 || frameLength == 0) {
          debugPrint(
            '[AudioCompressionDart] Invalid frame length: $frameLength at offset $readOffset',
          );
          break;
        }

        if (readOffset + frameLength > opusBytes.length) {
          debugPrint(
            '[AudioCompressionDart] Warning: Incomplete frame at offset $readOffset',
          );
          break;
        }

        // Extract frame data
        final frameData = opusBytes.sublist(
          readOffset,
          readOffset + frameLength,
        );
        readOffset += frameLength;

        // Decode frame
        try {
          final decoded = decoder.decode(input: frameData);
          pcmSamples.addAll(decoded);
        } catch (e) {
          debugPrint('[AudioCompressionDart] Failed to decode frame: $e');
          // Continue with next frame
        }
      }

      debugPrint(
        '[AudioCompressionDart] Decoded ${pcmSamples.length} PCM samples',
      );

      return Int16List.fromList(pcmSamples);
    } finally {
      decoder.destroy();
    }
  }

  /// Build WAV file from PCM samples
  Uint8List _buildWavFile({
    required Int16List pcmData,
    required int sampleRate,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    // Convert Int16List to bytes
    final pcmBytes = _int16ListToBytes(pcmData);

    // Build WAV header
    final header = _buildWavHeader(
      dataLength: pcmBytes.length,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );

    // Combine header and data
    return Uint8List.fromList([...header, ...pcmBytes]);
  }

  /// Convert Int16List samples to PCM bytes (little-endian)
  Uint8List _int16ListToBytes(Int16List samples) {
    final byteData = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      byteData.setInt16(i * 2, samples[i], Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  /// Build WAV file header (44 bytes)
  Uint8List _buildWavHeader({
    required int dataLength,
    required int sampleRate,
    int bitsPerSample = 16,
    int channels = 1,
  }) {
    final sampleWidth = bitsPerSample ~/ 8;
    final byteData = ByteData(44);
    final fileSize = dataLength + 36;
    final byteRate = sampleRate * channels * sampleWidth;
    final blockAlign = channels * sampleWidth;

    // RIFF chunk
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, fileSize, Endian.little);
    byteData.setUint8(8, 0x57); // 'W'
    byteData.setUint8(9, 0x41); // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'

    // fmt chunk
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
    byteData.setUint16(22, channels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, byteRate, Endian.little);
    byteData.setUint16(32, blockAlign, Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, dataLength, Endian.little);

    return byteData.buffer.asUint8List();
  }
}
