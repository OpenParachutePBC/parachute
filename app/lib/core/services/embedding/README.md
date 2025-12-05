# Embedding Service

This directory contains the foundational embedding interface and model management for Parachute's RAG search feature.

## Architecture

The embedding system follows a platform-adaptive architecture:

```
EmbeddingService (abstract interface)
    ├── MobileEmbeddingService (flutter_gemma) - Issue #20
    └── DesktopEmbeddingService (Ollama) - Issue #22
```

## Core Components

### 1. EmbeddingService (`embedding_service.dart`)

Abstract interface that all platform implementations must follow:

- `embed(String)` - Generate embedding for a single text
- `embedBatch(List<String>)` - Batch embedding for efficiency
- `downloadModel()` - Stream model download progress
- `isReady()` - Check if model is loaded
- `needsDownload()` - Check if model needs downloading

### 2. EmbeddingModelManager (`embedding_model_manager.dart`)

Manages model lifecycle:

- Auto-download on app startup (non-blocking)
- Status tracking (notDownloaded → downloading → ready)
- Error handling
- Progress reporting for UI

### 3. EmbeddingDimensionHelper

Utility for dimension truncation (Matryoshka embeddings):

- Truncate 768d → 256d for faster search
- Normalize vectors to unit length
- Check if vectors are normalized (for testing)

## Models

### Mobile (Android/iOS)
- **EmbeddingGemma** via flutter_gemma
- 300 MB model
- 768d native, truncated to 256d
- On-device, private, no internet required

### Desktop (macOS/Linux/Windows)
- **Ollama** with embedding models
- nomic-embed-text (274 MB, 768d) - Fast
- mxbai-embed-large (670 MB, 1024d) - Higher quality

## Dimension Strategy

Starting with **256 dimensions** (truncated from 768):

| Dimensions | Storage/chunk | Search Speed | Quality vs 768d |
|------------|---------------|--------------|-----------------|
| 768        | 3 KB          | Baseline     | 100%            |
| 512        | 2 KB          | ~2x faster   | ~98%            |
| 256        | 1 KB          | ~3x faster   | ~97%            |

Rationale: 256d provides excellent quality with 3x faster search and 1/3 storage.

## Matryoshka Embeddings

EmbeddingGemma supports Matryoshka Representation Learning:
- Embeddings can be truncated to smaller sizes without retraining
- Just take the first N dimensions
- Must renormalize after truncation

See: https://arxiv.org/abs/2205.13147

## Usage

### App Startup (main.dart)

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();

  // Trigger embedding model download (non-blocking)
  container.read(embeddingModelManagerProvider).ensureModelReady();

  runApp(ProviderScope(child: ParachuteApp()));
}
```

### Generating Embeddings

```dart
// Get the service
final embeddingService = ref.read(embeddingServiceProvider);

// Check if ready
if (!await embeddingService.isReady()) {
  // Show download UI or wait for download
  return;
}

// Embed a single text
final embedding = await embeddingService.embed('Hello world');
// embedding: List<double> of length 256

// Embed multiple texts (more efficient)
final embeddings = await embeddingService.embedBatch([
  'First text',
  'Second text',
  'Third text',
]);
// embeddings: List<List<double>>, each inner list has 256 elements
```

### Monitoring Download Progress

```dart
final manager = ref.read(embeddingModelManagerProvider);

// Start download
await for (final progress in manager.downloadModel()) {
  print('Download: ${(progress * 100).toStringAsFixed(1)}%');
  // Update UI progress bar
}

// Check status
if (manager.status.isReady) {
  print('Model ready!');
} else if (manager.status.hasError) {
  print('Error: ${manager.error}');
}
```

## Testing

Tests are located in `app/test/core/services/embedding/`:

- `embedding_models_test.dart` - Model enums and status
- `embedding_dimension_helper_test.dart` - Dimension truncation
- `embedding_model_manager_test.dart` - Lifecycle management

Run tests:
```bash
cd app && flutter test test/core/services/embedding/
```

## Next Steps

This foundation enables:

- **Issue #20**: Mobile embedding implementation (flutter_gemma)
- **Issue #22**: Desktop embedding implementation (Ollama)
- **Issue #23**: Chunking service (split documents for embedding)
- **Issue #4**: Vector search and RAG retrieval

## Platform Detection

The system automatically detects the platform:

```dart
if (EmbeddingModelManager.isMobile) {
  // Use flutter_gemma (Android/iOS)
} else if (EmbeddingModelManager.isDesktop) {
  // Use Ollama (macOS/Linux/Windows)
}
```

This is handled by the `embeddingServiceProvider` in `embedding_provider.dart`.
