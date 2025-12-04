import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/search/bm25_search_service.dart';
import 'package:app/features/recorder/models/recording.dart';

void main() {
  group('BM25SearchService', () {
    late BM25SearchService service;

    setUp(() {
      service = BM25SearchService();
    });

    tearDown(() {
      service.clear();
    });

    group('buildIndex', () {
      test('builds index successfully with multiple recordings', () async {
        final recordings = _createSampleRecordings();

        await service.buildIndex(recordings);

        expect(service.needsRebuild, false);
        expect(service.indexSize, recordings.length);
      });

      test('builds index successfully with empty list', () async {
        await service.buildIndex([]);

        expect(service.needsRebuild, false);
        expect(service.indexSize, 0);
      });

      test('rebuilds index when called multiple times', () async {
        final recordings1 = _createSampleRecordings().take(2).toList();
        final recordings2 = _createSampleRecordings();

        await service.buildIndex(recordings1);
        expect(service.indexSize, 2);

        await service.buildIndex(recordings2);
        expect(service.indexSize, recordings2.length);
      });
    });

    group('search', () {
      test('throws StateError if index not built', () async {
        expect(
          () => service.search('test'),
          throwsStateError,
        );
      });

      test('returns empty list for empty query', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('');
        expect(results, isEmpty);
      });

      test('returns empty list for whitespace query', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('   ');
        expect(results, isEmpty);
      });

      test('finds recordings matching title', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('Project Alpha');

        expect(results, isNotEmpty);
        expect(
          results.first.recording.title.toLowerCase(),
          contains('project alpha'),
        );
        expect(results.first.matchedFields, contains('title'));
      });

      test('finds recordings matching transcript', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('timeline milestones');

        expect(results, isNotEmpty);
        expect(
          results.first.recording.transcript.toLowerCase(),
          contains('timeline'),
        );
        expect(results.first.matchedFields, contains('transcript'));
      });

      test('finds recordings matching tags', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('work');

        expect(results, isNotEmpty);
        expect(results.first.recording.tags, contains('work'));
        expect(results.first.matchedFields, contains('tags'));
      });

      test('finds recordings matching context', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Test Recording',
            transcript: 'Some transcript',
            context: 'Weekly team sync meeting',
          ),
        ];
        await service.buildIndex(recordings);

        final results = await service.search('weekly sync');

        expect(results, isNotEmpty);
        expect(results.first.matchedFields, contains('context'));
      });

      test('finds recordings matching summary', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Test Recording',
            transcript: 'Some transcript',
            summary: 'Discussed quarterly goals and objectives',
          ),
        ];
        await service.buildIndex(recordings);

        final results = await service.search('quarterly goals');

        expect(results, isNotEmpty);
        expect(results.first.matchedFields, contains('summary'));
      });

      test('respects limit parameter', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('recording', limit: 2);

        expect(results.length, lessThanOrEqualTo(2));
      });

      test('returns results sorted by relevance', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Alpha Alpha Alpha', // High relevance
            transcript: 'Alpha Alpha Alpha',
          ),
          _createRecording(
            id: 'test-2',
            title: 'Beta',
            transcript: 'Alpha', // Lower relevance
          ),
          _createRecording(
            id: 'test-3',
            title: 'Gamma',
            transcript: 'Something else', // No match
          ),
        ];
        await service.buildIndex(recordings);

        final results = await service.search('Alpha');

        expect(results, isNotEmpty);
        // First result should have higher score than second
        if (results.length >= 2) {
          expect(results[0].score, greaterThan(results[1].score));
        }
      });

      test('identifies multiple matched fields', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Alpha Project',
            transcript: 'Discussing Alpha features',
            tags: ['alpha', 'project'],
            context: 'Alpha team meeting',
          ),
        ];
        await service.buildIndex(recordings);

        final results = await service.search('Alpha');

        expect(results, isNotEmpty);
        final matchedFields = results.first.matchedFields;
        expect(matchedFields, contains('title'));
        expect(matchedFields, contains('transcript'));
        expect(matchedFields, contains('tags'));
        expect(matchedFields, contains('context'));
      });

      test('handles case-insensitive search', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Project ALPHA',
            transcript: 'ALPHA project details',
          ),
        ];
        await service.buildIndex(recordings);

        final resultsLower = await service.search('alpha');
        final resultsUpper = await service.search('ALPHA');
        final resultsMixed = await service.search('Alpha');

        expect(resultsLower, isNotEmpty);
        expect(resultsUpper, isNotEmpty);
        expect(resultsMixed, isNotEmpty);
      });

      test('handles multi-word queries', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('project alpha timeline');

        expect(results, isNotEmpty);
      });

      test('returns results with BM25 scores', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        final results = await service.search('project');

        expect(results, isNotEmpty);
        for (final result in results) {
          expect(result.score, greaterThan(0));
        }
      });
    });

    group('clear', () {
      test('clears index and marks as needing rebuild', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);

        expect(service.needsRebuild, false);

        service.clear();

        expect(service.needsRebuild, true);
        expect(service.indexSize, 0);
      });

      test('allows rebuilding after clear', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);
        service.clear();

        await service.buildIndex(recordings);

        expect(service.needsRebuild, false);
        expect(service.indexSize, recordings.length);
      });
    });

    group('needsRebuild', () {
      test('returns true initially', () {
        expect(service.needsRebuild, true);
      });

      test('returns false after building index', () async {
        await service.buildIndex(_createSampleRecordings());
        expect(service.needsRebuild, false);
      });

      test('returns true after clearing', () async {
        await service.buildIndex(_createSampleRecordings());
        service.clear();
        expect(service.needsRebuild, true);
      });
    });

    group('indexSize', () {
      test('returns 0 initially', () {
        expect(service.indexSize, 0);
      });

      test('returns correct size after building', () async {
        final recordings = _createSampleRecordings();
        await service.buildIndex(recordings);
        expect(service.indexSize, recordings.length);
      });

      test('returns 0 after clearing', () async {
        await service.buildIndex(_createSampleRecordings());
        service.clear();
        expect(service.indexSize, 0);
      });
    });

    group('field weighting', () {
      test('title has higher weight than transcript', () async {
        final recordings = [
          _createRecording(
            id: 'test-1',
            title: 'Alpha Alpha Alpha', // Title with term repeated
            transcript: 'Other content',
          ),
          _createRecording(
            id: 'test-2',
            title: 'Other content',
            transcript: 'Alpha', // Transcript with single term
          ),
        ];
        await service.buildIndex(recordings);

        final results = await service.search('Alpha');

        expect(results, hasLength(2));
        // Recording with term in title should score higher
        expect(results[0].recording.id, 'test-1');
      });
    });
  });
}

/// Helper function to create sample recordings for testing
List<Recording> _createSampleRecordings() {
  final now = DateTime.now();

  return [
    _createRecording(
      id: 'sample-1',
      title: 'Project Alpha Planning',
      transcript: '''
        Today we discussed the new features for Project Alpha.
        Key decisions: 1) Move deadline to next quarter,
        2) Add two more developers to the team,
        3) Focus on mobile-first approach.
        Timeline and milestones were reviewed.
      ''',
      tags: ['work', 'project-alpha', 'planning'],
      timestamp: now.subtract(const Duration(days: 1)),
    ),
    _createRecording(
      id: 'sample-2',
      title: 'Weekly Team Sync',
      transcript: '''
        Weekly team sync discussion.
        Topics covered: Sprint review, backlog grooming, and upcoming releases.
      ''',
      tags: ['work', 'meeting'],
      timestamp: now.subtract(const Duration(days: 2)),
    ),
    _createRecording(
      id: 'sample-3',
      title: 'Personal Reminder',
      transcript: '''
        Remember to call the dentist tomorrow morning.
        Also pick up groceries on the way home.
      ''',
      tags: ['personal', 'reminder'],
      timestamp: now.subtract(const Duration(hours: 5)),
    ),
  ];
}

/// Helper function to create a recording with custom fields
Recording _createRecording({
  required String id,
  required String title,
  required String transcript,
  List<String> tags = const [],
  String context = '',
  String summary = '',
  DateTime? timestamp,
}) {
  return Recording(
    id: id,
    title: title,
    filePath: '/test/path/$id.opus',
    timestamp: timestamp ?? DateTime.now(),
    duration: const Duration(minutes: 5),
    tags: tags,
    transcript: transcript,
    context: context,
    summary: summary,
    fileSizeKB: 100.0,
  );
}
