import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:app/features/recorder/models/recording.dart';

/// Computes content hashes for change detection
///
/// Used by SearchIndexService to detect when recordings have changed
/// and need to be re-indexed. Hashes all searchable content fields.
///
/// **Why hashing?**
/// - File timestamps change on git sync even if content is identical
/// - Hash-based detection is more reliable for distributed sync
/// - SHA-256 provides strong uniqueness guarantees
///
/// **Usage:**
/// ```dart
/// final hasher = ContentHasher();
/// final hash1 = hasher.computeHash(recording);
/// // ... recording is modified ...
/// final hash2 = hasher.computeHash(recording);
/// if (hash1 != hash2) {
///   // Re-index the recording
/// }
/// ```
class ContentHasher {
  /// Compute SHA-256 hash of all searchable content in a recording
  ///
  /// Includes:
  /// - Title
  /// - Summary
  /// - Context
  /// - Tags (joined with commas)
  /// - Transcript
  ///
  /// Returns a hexadecimal string representation of the hash.
  String computeHash(Recording recording) {
    final content = [
      recording.title,
      recording.summary,
      recording.context,
      recording.tags.join(','),
      recording.transcript,
    ].join('\n');

    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute hash from individual content fields
  ///
  /// Useful when you don't have a full Recording object.
  /// Uses the same algorithm as [computeHash].
  String computeHashFromFields({
    required String title,
    String summary = '',
    String context = '',
    List<String> tags = const [],
    String transcript = '',
  }) {
    final content = [
      title,
      summary,
      context,
      tags.join(','),
      transcript,
    ].join('\n');

    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
