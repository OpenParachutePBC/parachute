import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:app/core/models/embedding_models.dart';
import 'package:app/core/services/embedding/embedding_service.dart';
import 'package:app/core/services/embedding/desktop_embedding_service.dart';

// Mock classes
class MockOllamaClient extends Mock implements OllamaClient {}

void main() {
  late MockOllamaClient mockClient;
  late DesktopEmbeddingService service;

  setUp(() {
    mockClient = MockOllamaClient();
    service = DesktopEmbeddingService(
      client: mockClient,
      modelType: OllamaEmbeddingModelType.nomicEmbedText,
    );
  });

  group('DesktopEmbeddingService', () {
    group('isReady', () {
      test('returns true when model is available', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [
              Model(model: 'nomic-embed-text'),
              Model(model: 'llama2'),
            ],
          ),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, true);
        verify(() => mockClient.listModels()).called(1);
      });

      test('returns false when model is not available', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [
              Model(model: 'llama2'),
              Model(model: 'mistral'),
            ],
          ),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, false);
      });

      test('returns false when Ollama is not running', () async {
        // Arrange
        when(() => mockClient.listModels()).thenThrow(
          Exception('Connection refused'),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, false);
      });

      test('handles empty model list', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, false);
      });

      test('handles null model list', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: null),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, false);
      });
    });

    group('needsDownload', () {
      test('returns false when model is ready', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );

        // Act
        final result = await service.needsDownload();

        // Assert
        expect(result, false);
      });

      test('returns true when model is not available', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );

        // Act
        final result = await service.needsDownload();

        // Assert
        expect(result, true);
      });

      test('returns true on error', () async {
        // Arrange
        when(() => mockClient.listModels()).thenThrow(
          Exception('Connection error'),
        );

        // Act
        final result = await service.needsDownload();

        // Assert
        expect(result, true);
      });
    });

    group('downloadModel', () {
      test('successfully downloads model', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );
        when(() => mockClient.pullModel(request: any(named: 'request')))
            .thenAnswer((_) async => PullModelResponse());

        // Act
        final progressList = <double>[];
        await for (final progress in service.downloadModel()) {
          progressList.add(progress);
        }

        // Assert
        expect(progressList, [0.0, 1.0]);
        verify(() => mockClient.listModels()).called(1);
        verify(() => mockClient.pullModel(request: any(named: 'request'))).called(1);
      });

      test('throws when Ollama is not running', () async {
        // Arrange
        when(() => mockClient.listModels()).thenThrow(
          Exception('Connection refused'),
        );

        // Act & Assert
        expect(
          () => service.downloadModel().toList(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Ollama is not running'),
            ),
          ),
        );
      });

      test('throws when pull fails', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );
        when(() => mockClient.pullModel(request: any(named: 'request')))
            .thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => service.downloadModel().toList(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to download model'),
            ),
          ),
        );
      });
    });

    group('embed', () {
      test('successfully embeds text', () async {
        // Arrange
        final fullEmbedding = List.generate(768, (i) => i / 768.0);

        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenAnswer(
          (_) async => GenerateEmbeddingResponse(
            embedding: fullEmbedding,
          ),
        );

        // Act
        final result = await service.embed('test text');

        // Assert
        expect(result.length, 256); // Truncated dimensions
        expect(EmbeddingDimensionHelper.isNormalized(result), true);
        verify(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .called(1);
      });

      test('throws when text is empty', () async {
        // Act & Assert
        expect(
          () => service.embed(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws when text is whitespace only', () async {
        // Act & Assert
        expect(
          () => service.embed('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('throws when model is not ready', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );

        // Act & Assert
        expect(
          () => service.embed('test text'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('is not ready'),
            ),
          ),
        );
      });

      test('throws when Ollama returns empty embedding', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenAnswer(
          (_) async => GenerateEmbeddingResponse(embedding: []),
        );

        // Act & Assert
        expect(
          () => service.embed('test text'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('empty embedding'),
            ),
          ),
        );
      });

      test('throws when Ollama returns null embedding', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenAnswer(
          (_) async => GenerateEmbeddingResponse(embedding: null),
        );

        // Act & Assert
        expect(
          () => service.embed('test text'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('empty embedding'),
            ),
          ),
        );
      });

      test('properly truncates larger embeddings', () async {
        // Arrange - test with 1024 dim model
        final largeEmbedding = List.generate(1024, (i) => i / 1024.0);

        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenAnswer(
          (_) async => GenerateEmbeddingResponse(embedding: largeEmbedding),
        );

        // Act
        final result = await service.embed('test text');

        // Assert
        expect(result.length, 256);
        expect(EmbeddingDimensionHelper.isNormalized(result), true);
      });
    });

    group('embedBatch', () {
      test('successfully embeds multiple texts', () async {
        // Arrange
        final fullEmbedding = List.generate(768, (i) => i / 768.0);

        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenAnswer(
          (_) async => GenerateEmbeddingResponse(embedding: fullEmbedding),
        );

        // Act
        final result = await service.embedBatch(['text1', 'text2', 'text3']);

        // Assert
        expect(result.length, 3);
        expect(result[0].length, 256);
        expect(result[1].length, 256);
        expect(result[2].length, 256);
        verify(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .called(3);
      });

      test('returns empty list for empty input', () async {
        // Act
        final result = await service.embedBatch([]);

        // Assert
        expect(result, isEmpty);
        verifyNever(() => mockClient.generateEmbedding(request: any(named: 'request')));
      });

      test('throws when any text is empty', () async {
        // Act & Assert
        expect(
          () => service.embedBatch(['text1', '', 'text3']),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              contains('index 1'),
            ),
          ),
        );
      });

      test('stops on first error and propagates exception', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'nomic-embed-text')],
          ),
        );
        when(() => mockClient.generateEmbedding(request: any(named: 'request')))
            .thenThrow(Exception('Network error'));

        // Act & Assert
        expect(
          () => service.embedBatch(['text1', 'text2']),
          throwsException,
        );
      });
    });

    group('dimensions', () {
      test('returns 256 dimensions', () {
        // Act & Assert
        expect(service.dimensions, 256);
      });
    });

    group('setModel', () {
      test('changes the model type', () {
        // Act
        service.setModel(OllamaEmbeddingModelType.mxbaiEmbedLarge);

        // Assert
        expect(service.modelType, OllamaEmbeddingModelType.mxbaiEmbedLarge);
      });

      test('updated model is used in subsequent operations', () async {
        // Arrange
        service.setModel(OllamaEmbeddingModelType.mxbaiEmbedLarge);

        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [Model(model: 'mxbai-embed-large')],
          ),
        );

        // Act
        final result = await service.isReady();

        // Assert
        expect(result, true);
      });
    });

    group('utility methods', () {
      test('isOllamaAvailable returns true when server is running', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(models: []),
        );

        // Act
        final result = await service.isOllamaAvailable();

        // Assert
        expect(result, true);
      });

      test('isOllamaAvailable returns false when server is not running', () async {
        // Arrange
        when(() => mockClient.listModels()).thenThrow(Exception('Connection error'));

        // Act
        final result = await service.isOllamaAvailable();

        // Assert
        expect(result, false);
      });

      test('getAvailableModels returns list of models', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [
              Model(model: 'nomic-embed-text'),
              Model(model: 'llama2'),
              Model(model: 'mistral'),
            ],
          ),
        );

        // Act
        final result = await service.getAvailableModels();

        // Assert
        expect(result, ['nomic-embed-text', 'llama2', 'mistral']);
      });

      test('getAvailableModels filters out empty names', () async {
        // Arrange
        when(() => mockClient.listModels()).thenAnswer(
          (_) async => ModelsResponse(
            models: [
              Model(model: 'nomic-embed-text'),
              Model(model: ''),
              Model(model: null),
              Model(model: 'llama2'),
            ],
          ),
        );

        // Act
        final result = await service.getAvailableModels();

        // Assert
        expect(result, ['nomic-embed-text', 'llama2']);
      });

      test('getAvailableModels returns empty list on error', () async {
        // Arrange
        when(() => mockClient.listModels()).thenThrow(Exception('Connection error'));

        // Act
        final result = await service.getAvailableModels();

        // Assert
        expect(result, isEmpty);
      });
    });

    group('dispose', () {
      test('calls endSession on client', () async {
        // Arrange
        when(() => mockClient.endSession()).thenAnswer((_) async {});

        // Act
        await service.dispose();

        // Assert
        verify(() => mockClient.endSession()).called(1);
      });
    });
  });
}
