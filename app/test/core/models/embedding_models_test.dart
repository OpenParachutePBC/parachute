import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/models/embedding_models.dart';

void main() {
  group('EmbeddingModelStatus', () {
    test('has correct display names', () {
      expect(
        EmbeddingModelStatus.notDownloaded.displayName,
        'Not Downloaded',
      );
      expect(EmbeddingModelStatus.downloading.displayName, 'Downloading');
      expect(EmbeddingModelStatus.ready.displayName, 'Ready');
      expect(EmbeddingModelStatus.error.displayName, 'Error');
    });

    test('has correct status flags', () {
      expect(EmbeddingModelStatus.notDownloaded.needsDownload, true);
      expect(EmbeddingModelStatus.notDownloaded.isReady, false);

      expect(EmbeddingModelStatus.downloading.isDownloading, true);
      expect(EmbeddingModelStatus.downloading.isReady, false);

      expect(EmbeddingModelStatus.ready.isReady, true);
      expect(EmbeddingModelStatus.ready.needsDownload, false);

      expect(EmbeddingModelStatus.error.hasError, true);
      expect(EmbeddingModelStatus.error.isReady, false);
    });
  });

  group('EmbeddingGemmaModelType', () {
    test('has correct properties', () {
      final model = EmbeddingGemmaModelType.standard;

      expect(model.modelName, 'embedding-gemma-256');
      expect(model.sizeInMB, 300);
      expect(model.dimensions, 256);
      expect(model.downloadUrl, contains('embedding-gemma.task'));
      expect(model.huggingFaceUrl, contains('huggingface.co'));
    });

    test('formats size correctly', () {
      final model = EmbeddingGemmaModelType.standard;
      expect(model.formattedSize, '300 MB');
    });

    test('converts from string', () {
      expect(
        EmbeddingGemmaModelType.fromString('embedding-gemma-256'),
        EmbeddingGemmaModelType.standard,
      );
      expect(
        EmbeddingGemmaModelType.fromString('EMBEDDING-GEMMA-256'),
        EmbeddingGemmaModelType.standard,
      );
      expect(
        EmbeddingGemmaModelType.fromString('standard'),
        EmbeddingGemmaModelType.standard,
      );
      expect(EmbeddingGemmaModelType.fromString('invalid'), null);
    });
  });

  group('OllamaEmbeddingModelType', () {
    test('has correct properties', () {
      final model = OllamaEmbeddingModelType.nomicEmbedText;

      expect(model.modelName, 'nomic-embed-text');
      expect(model.sizeInMB, 274);
      expect(model.dimensions, 768);
    });

    test('formats size correctly', () {
      expect(
        OllamaEmbeddingModelType.nomicEmbedText.formattedSize,
        '274 MB',
      );
      expect(
        OllamaEmbeddingModelType.mxbaiEmbedLarge.formattedSize,
        '670 MB',
      );
    });

    test('converts from string', () {
      expect(
        OllamaEmbeddingModelType.fromString('nomic-embed-text'),
        OllamaEmbeddingModelType.nomicEmbedText,
      );
      expect(
        OllamaEmbeddingModelType.fromString('NOMIC-EMBED-TEXT'),
        OllamaEmbeddingModelType.nomicEmbedText,
      );
      expect(
        OllamaEmbeddingModelType.fromString('nomicEmbedText'),
        OllamaEmbeddingModelType.nomicEmbedText,
      );
      expect(OllamaEmbeddingModelType.fromString('invalid'), null);
    });
  });

  group('EmbeddingModelDownloadProgress', () {
    test('creates with correct initial values', () {
      const progress = EmbeddingModelDownloadProgress(
        modelName: 'test-model',
        status: EmbeddingModelStatus.downloading,
        progress: 0.5,
      );

      expect(progress.modelName, 'test-model');
      expect(progress.status, EmbeddingModelStatus.downloading);
      expect(progress.progress, 0.5);
      expect(progress.error, null);
    });

    test('copyWith creates new instance with updated values', () {
      const original = EmbeddingModelDownloadProgress(
        modelName: 'test-model',
        status: EmbeddingModelStatus.downloading,
        progress: 0.5,
      );

      final updated = original.copyWith(
        progress: 0.75,
        status: EmbeddingModelStatus.ready,
      );

      expect(updated.modelName, 'test-model'); // unchanged
      expect(updated.progress, 0.75); // changed
      expect(updated.status, EmbeddingModelStatus.ready); // changed
    });

    test('formats progress percentage correctly', () {
      const progress1 = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.downloading,
        progress: 0.0,
      );
      expect(progress1.progressPercentage, '0%');

      const progress2 = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.downloading,
        progress: 0.5,
      );
      expect(progress2.progressPercentage, '50%');

      const progress3 = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.downloading,
        progress: 1.0,
      );
      expect(progress3.progressPercentage, '100%');
    });

    test('has correct status flags', () {
      const downloading = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.downloading,
      );
      expect(downloading.isDownloading, true);
      expect(downloading.isReady, false);

      const ready = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.ready,
      );
      expect(ready.isReady, true);
      expect(ready.needsDownload, false);

      const error = EmbeddingModelDownloadProgress(
        modelName: 'test',
        status: EmbeddingModelStatus.error,
        error: 'Download failed',
      );
      expect(error.hasError, true);
      expect(error.error, 'Download failed');
    });
  });
}
