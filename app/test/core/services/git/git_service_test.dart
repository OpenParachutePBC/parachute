import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/services/git/git_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('GitService POC Tests', () {
    late Directory tempDir;
    late GitService gitService;

    setUp(() async {
      // Create temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('parachute_git_test_');
      gitService = GitService.instance;
    });

    tearDown(() async {
      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should initialize a new Git repository', () async {
      final repo = await gitService.initRepository(tempDir.path);
      expect(repo, isNotNull);

      // Verify .git directory exists
      final gitDir = Directory(path.join(tempDir.path, '.git'));
      expect(await gitDir.exists(), isTrue);
    });

    test('should detect if directory is a Git repository', () async {
      // Before init
      expect(await gitService.isGitRepository(tempDir.path), isFalse);

      // After init
      await gitService.initRepository(tempDir.path);
      expect(await gitService.isGitRepository(tempDir.path), isTrue);
    });

    test('should add file and commit (basic workflow)', () async {
      // Initialize repository
      final repo = await gitService.initRepository(tempDir.path);
      expect(repo, isNotNull);

      // Create a test markdown file (simulating a capture)
      final testFile = File(path.join(tempDir.path, 'test-capture.md'));
      await testFile.writeAsString('''---
title: Test Recording
date: 2025-11-05
tags: [test, poc]
---

# Test Recording

This is a test recording to validate Git operations.
''');

      // Add file to staging
      final addSuccess = await gitService.addFile(repo!, 'test-capture.md');
      expect(addSuccess, isTrue);

      // Commit the file
      final commitOid = await gitService.commit(
        repo: repo,
        message: 'test: add test capture file',
        authorName: 'Parachute Test',
        authorEmail: 'test@parachute.local',
      );
      expect(commitOid, isNotNull);
      print('✅ Created commit: $commitOid');

      // Verify commit history
      final history = await gitService.getCommitHistory(repo);
      expect(history.length, 1);
      expect(history.first['message'], 'test: add test capture file');
      print('✅ Commit history verified');
    });

    test('should handle testBasicWorkflow helper', () async {
      final testFilePath = path.join(tempDir.path, 'workflow-test.md');
      final testContent = '''---
title: Workflow Test
---

Testing the basic workflow helper method.
''';

      final success = await gitService.testBasicWorkflow(
        repoPath: tempDir.path,
        testFilePath: testFilePath,
        testFileContent: testContent,
      );

      expect(success, isTrue);
      print('✅ testBasicWorkflow completed successfully');

      // Verify file was created
      expect(await File(testFilePath).exists(), isTrue);
    });

    test('should get repository status after changes', () async {
      final repo = await gitService.initRepository(tempDir.path);
      expect(repo, isNotNull);

      // Create an untracked file
      final untrackedFile = File(path.join(tempDir.path, 'untracked.md'));
      await untrackedFile.writeAsString('Untracked content');

      // Get status
      final status = await gitService.getStatus(repo!);
      print('📊 Repository status: $status');

      expect(status['untrackedCount'], greaterThan(0));
    });
  });

  group('GitService with Audio Files', () {
    late Directory tempDir;
    late GitService gitService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'parachute_git_audio_test_',
      );
      gitService = GitService.instance;
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should handle adding and committing audio files', () async {
      final repo = await gitService.initRepository(tempDir.path);
      expect(repo, isNotNull);

      // Create a mock WAV file (just a small binary file for testing)
      // In real scenario, this would be an actual audio recording
      final audioFile = File(
        path.join(tempDir.path, '2025-11-05_14-30-00.wav'),
      );
      final mockAudioData = List.generate(
        1024,
        (i) => i % 256,
      ); // 1KB of mock data
      await audioFile.writeAsBytes(mockAudioData);

      // Create corresponding markdown file
      final mdFile = File(path.join(tempDir.path, '2025-11-05_14-30-00.md'));
      await mdFile.writeAsString('''---
title: Test Audio Recording
date: 2025-11-05T14:30:00
duration: 5.2
transcription_status: completed
---

# Test Audio Recording

This is a test transcription of an audio recording.

**Speaker 1**: Testing one two three.
**Speaker 2**: Audio levels look good.
''');

      // Add both files
      final audioAddSuccess = await gitService.addFile(
        repo!,
        '2025-11-05_14-30-00.wav',
      );
      expect(audioAddSuccess, isTrue);

      final mdAddSuccess = await gitService.addFile(
        repo,
        '2025-11-05_14-30-00.md',
      );
      expect(mdAddSuccess, isTrue);

      // Commit both files
      final commitOid = await gitService.commit(
        repo: repo,
        message: 'feat: add audio recording with transcription',
        authorName: 'Parachute Test',
        authorEmail: 'test@parachute.local',
      );
      expect(commitOid, isNotNull);
      print('✅ Committed audio file + markdown: $commitOid');

      // Verify commit history
      final history = await gitService.getCommitHistory(repo);
      expect(history.length, 1);
      print('✅ Audio file workflow validated');
    });

    test('should handle multiple sequential commits', () async {
      final repo = await gitService.initRepository(tempDir.path);
      expect(repo, isNotNull);

      // Simulate multiple recordings over time
      for (int i = 1; i <= 3; i++) {
        final mdFile = File(path.join(tempDir.path, 'recording-$i.md'));
        await mdFile.writeAsString('Recording #$i content');

        await gitService.addFile(repo!, 'recording-$i.md');
        await gitService.commit(
          repo: repo,
          message: 'feat: add recording #$i',
          authorName: 'Parachute Test',
          authorEmail: 'test@parachute.local',
        );
      }

      // Verify all commits
      final history = await gitService.getCommitHistory(repo!);
      expect(history.length, 3);
      print('✅ Multiple commits validated: ${history.length} commits');
    });
  });
}
