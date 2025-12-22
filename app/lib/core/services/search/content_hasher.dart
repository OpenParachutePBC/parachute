import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:app/features/recorder/models/recording.dart';
import 'package:app/features/journal/models/journal_entry.dart';
import 'package:app/features/journal/models/journal_day.dart';
import 'package:app/features/chat/services/local_session_reader.dart';

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

  /// Compute SHA-256 hash of a journal entry
  ///
  /// Includes:
  /// - Entry ID
  /// - Title
  /// - Content
  ///
  /// Returns a hexadecimal string representation of the hash.
  String computeJournalEntryHash(JournalEntry entry) {
    final content = [
      entry.id,
      entry.title,
      entry.content,
    ].join('\n');

    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute SHA-256 hash of an entire journal day
  ///
  /// Combines hashes of all entries in the day.
  /// Used to detect if any entry in the day has changed.
  String computeJournalDayHash(JournalDay journal) {
    final entryHashes = journal.entries
        .map((e) => computeJournalEntryHash(e))
        .join('\n');

    final bytes = utf8.encode(entryHashes);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute SHA-256 hash of a chat session with messages
  ///
  /// Includes:
  /// - Session ID
  /// - Title
  /// - All message content
  ///
  /// Returns a hexadecimal string representation of the hash.
  String computeChatSessionHash(ChatSessionWithLocalMessages sessionData) {
    final session = sessionData.session;
    final messages = sessionData.messages;

    final content = [
      session.id,
      session.title ?? '',
      ...messages.map((m) => '${m.role.name}:${m.textContent}'),
    ].join('\n');

    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
