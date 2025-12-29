# Embedding Service

Cross-platform embedding using **EmbeddingGemma** everywhere for compatible embeddings across devices.

## Architecture

```
EmbeddingService (abstract interface)
    ├── MobileEmbeddingService (flutter_gemma) - Android/iOS
    └── DesktopEmbeddingService (Ollama)       - macOS/Linux/Windows
```

Both platforms use **EmbeddingGemma** (768d → 256d via Matryoshka) for cross-device compatibility.

## Quick Start

### Desktop (macOS)

```bash
# Install Ollama (starts automatically)
brew install ollama

# The app will auto-pull embeddinggemma when you use semantic search
```

### Mobile

The app downloads EmbeddingGemma (~200MB) when you first use semantic search.

## Core Components

### EmbeddingService (`embedding_service.dart`)

Abstract interface:
- `embed(String)` - Generate 256d embedding for text
- `embedBatch(List<String>)` - Batch embedding
- `downloadModel()` - Stream download progress
- `isReady()` - Check if model is loaded
- `needsDownload()` - Check if download needed

### EmbeddingDimensionHelper

Matryoshka truncation utility:
- Truncate 768d → 256d (preserves ~97% quality)
- Normalize vectors to unit length

## Model: EmbeddingGemma

| Platform | Backend | Native Dims | Output Dims |
|----------|---------|-------------|-------------|
| Mobile   | flutter_gemma | 768 | 256 |
| Desktop  | Ollama | 768 | 256 |

**Why EmbeddingGemma?**
- Same model everywhere = compatible embeddings across devices
- Matryoshka trained = truncation preserves quality
- Small (~200MB) and fast
- Multilingual (100+ languages)

## Usage

```dart
// Get the service (auto-selects platform)
final embeddingService = ref.read(embeddingServiceProvider);

// Check if ready
if (!await embeddingService.isReady()) {
  // Trigger download via UI
  return;
}

// Embed text
final embedding = await embeddingService.embed('Hello world');
// embedding: List<double> of length 256

// Batch embed
final embeddings = await embeddingService.embedBatch([
  'First text',
  'Second text',
]);
```

## Matryoshka Embeddings

EmbeddingGemma uses Matryoshka Representation Learning:
- First N dimensions form a valid smaller embedding
- 256d retains ~97% of 768d quality
- 3x faster search, 1/3 storage

See: https://arxiv.org/abs/2205.13147

## Testing

```bash
flutter test test/core/services/embedding/
```
