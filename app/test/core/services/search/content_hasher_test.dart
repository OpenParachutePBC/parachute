import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/search/content_hasher.dart';
import 'package:app/features/recorder/models/recording.dart';

void main() {
  group('ContentHasher', () {
    late ContentHasher hasher;

    setUp(() {
      hasher = ContentHasher();
    });

    group('computeHash', () {
      test('computes consistent hash for same recording', () {
        final recording = _createSampleRecording();

        final hash1 = hasher.computeHash(recording);
        final hash2 = hasher.computeHash(recording);

        expect(hash1, equals(hash2));
      });

      test('computes different hash when title changes', () {
        final recording1 = _createSampleRecording(title: 'Original Title');
        final recording2 = _createSampleRecording(title: 'Modified Title');

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('computes different hash when summary changes', () {
        final recording1 = _createSampleRecording(summary: 'Original summary');
        final recording2 = _createSampleRecording(summary: 'Modified summary');

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('computes different hash when context changes', () {
        final recording1 = _createSampleRecording(context: 'Original context');
        final recording2 = _createSampleRecording(context: 'Modified context');

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('computes different hash when tags change', () {
        final recording1 = _createSampleRecording(tags: ['tag1', 'tag2']);
        final recording2 = _createSampleRecording(tags: ['tag1', 'tag3']);

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('computes different hash when transcript changes', () {
        final recording1 = _createSampleRecording(
          transcript: 'Original transcript',
        );
        final recording2 = _createSampleRecording(
          transcript: 'Modified transcript',
        );

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('computes same hash when non-content fields change', () {
        final now = DateTime.now();

        final recording1 = _createSampleRecording(
          timestamp: now,
          duration: const Duration(minutes: 15),
          fileSizeKB: 500.0,
        );

        final recording2 = _createSampleRecording(
          timestamp: now.add(const Duration(hours: 1)),
          duration: const Duration(minutes: 30),
          fileSizeKB: 1000.0,
        );

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        // Hash should be same because searchable content hasn't changed
        expect(hash1, equals(hash2));
      });

      test('handles empty fields', () {
        final recording = _createSampleRecording(
          title: '',
          summary: '',
          context: '',
          tags: [],
          transcript: '',
        );

        // Should not throw
        final hash = hasher.computeHash(recording);
        expect(hash, isNotEmpty);
      });

      test('produces different hashes for different recordings', () {
        final recording1 = Recording(
          id: 'rec-1',
          title: 'Recording 1',
          filePath: '/test/rec-1.opus',
          timestamp: DateTime.now(),
          duration: const Duration(minutes: 5),
          tags: ['test'],
          transcript: 'This is recording 1',
          fileSizeKB: 100.0,
        );

        final recording2 = Recording(
          id: 'rec-2',
          title: 'Recording 2',
          filePath: '/test/rec-2.opus',
          timestamp: DateTime.now(),
          duration: const Duration(minutes: 5),
          tags: ['test'],
          transcript: 'This is recording 2',
          fileSizeKB: 100.0,
        );

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        expect(hash1, isNot(equals(hash2)));
      });
    });

    group('computeHashFromFields', () {
      test('computes consistent hash for same fields', () {
        final hash1 = hasher.computeHashFromFields(
          title: 'Test Title',
          summary: 'Test Summary',
          context: 'Test Context',
          tags: ['tag1', 'tag2'],
          transcript: 'Test Transcript',
        );

        final hash2 = hasher.computeHashFromFields(
          title: 'Test Title',
          summary: 'Test Summary',
          context: 'Test Context',
          tags: ['tag1', 'tag2'],
          transcript: 'Test Transcript',
        );

        expect(hash1, equals(hash2));
      });

      test('matches hash from recording', () {
        final recording = _createSampleRecording(
          title: 'Test Title',
          summary: 'Test Summary',
          context: 'Test Context',
          tags: ['tag1', 'tag2'],
          transcript: 'Test Transcript',
        );

        final recordingHash = hasher.computeHash(recording);
        final fieldsHash = hasher.computeHashFromFields(
          title: 'Test Title',
          summary: 'Test Summary',
          context: 'Test Context',
          tags: ['tag1', 'tag2'],
          transcript: 'Test Transcript',
        );

        expect(fieldsHash, equals(recordingHash));
      });

      test('handles default values', () {
        final hash = hasher.computeHashFromFields(
          title: 'Test Title',
          // All other fields use defaults
        );

        expect(hash, isNotEmpty);
      });

      test('computes different hash when any field changes', () {
        final baseHash = hasher.computeHashFromFields(
          title: 'Title',
          summary: 'Summary',
          context: 'Context',
          tags: ['tag'],
          transcript: 'Transcript',
        );

        final titleHash = hasher.computeHashFromFields(
          title: 'Different Title',
          summary: 'Summary',
          context: 'Context',
          tags: ['tag'],
          transcript: 'Transcript',
        );

        expect(titleHash, isNot(equals(baseHash)));
      });
    });

    group('hash properties', () {
      test('produces 64-character hexadecimal hash (SHA-256)', () {
        final recording = _createSampleRecording();
        final hash = hasher.computeHash(recording);

        // SHA-256 produces 256 bits = 32 bytes = 64 hex characters
        expect(hash.length, equals(64));
        expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(hash), isTrue);
      });

      test('hash changes detectably with minimal content change', () {
        final recording1 = _createSampleRecording(title: 'Test');
        final recording2 = _createSampleRecording(title: 'Test.');

        final hash1 = hasher.computeHash(recording1);
        final hash2 = hasher.computeHash(recording2);

        // Even a single character change should produce completely different hash
        expect(hash1, isNot(equals(hash2)));
      });
    });
  });
}

/// Helper function to create a sample recording for testing
Recording _createSampleRecording({
  String? id,
  String? title,
  String? summary,
  String? context,
  List<String>? tags,
  String? transcript,
  DateTime? timestamp,
  Duration? duration,
  double? fileSizeKB,
}) {
  return Recording(
    id: id ?? 'test-recording',
    title: title ?? 'Test Recording',
    filePath: '/test/recording.opus',
    timestamp: timestamp ?? DateTime.now(),
    duration: duration ?? const Duration(minutes: 5),
    tags: tags ?? ['test'],
    transcript: transcript ?? 'This is a test transcript',
    context: context ?? '',
    summary: summary ?? '',
    fileSizeKB: fileSizeKB ?? 100.0,
  );
}
