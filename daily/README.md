# Parachute Daily

**Local-first voice journaling — capture thoughts wherever you are.**

---

## What is Parachute Daily?

Daily is a voice-first journaling app that runs entirely on your device. No server, no cloud, no account required.

- **Voice-first**: Tap to record, speak your thoughts
- **Local-first**: Everything stays on your device
- **On-device transcription**: Parakeet v3 models, no internet needed
- **Semantic search**: EmbeddingGemma for finding entries by meaning
- **Omi support**: Hands-free recording with Bluetooth wearable
- **Auto-pause**: Hands-free recording with silence detection

---

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run on macOS
flutter run -d macos

# Run on Android
flutter run -d android
```

---

## Features

### Voice Capture
- Real-time transcription as you speak (Parakeet v3)
- Voice activity detection for hands-free recording
- Support for Omi pendant (Bluetooth wearable)
- Button-triggered recording from device

### Journal Organization
- Daily entries organized by date
- Audio files preserved alongside transcripts
- Full-text search across all entries
- Semantic search via EmbeddingGemma

### Local AI Models
- **Parakeet v3** (~500MB) - On-device voice transcription
- **EmbeddingGemma** (~300MB) - Semantic search embeddings
- Download once, works offline forever

### Omi Device
- Bluetooth pairing and battery monitoring
- Over-the-air firmware updates
- Store-and-forward audio recovery

### Offline Operation
- Works without internet connection
- Local Parakeet models for transcription
- Local embeddings for semantic search
- Data syncs via Git or Syncthing

---

## Data Storage

Daily stores everything in your local vault:

```
~/Parachute/
├── Daily/
│   └── journals/
│       └── 2025/12/30.md    # Today's journal
└── assets/
    └── 2025-12/
        └── *.opus           # Audio files
```

---

## Platforms

| Platform | Status |
|----------|--------|
| macOS | ✅ Full support |
| Android | ✅ Full support |
| iOS | ✅ Full support |
| Windows | 🚧 Planned |
| Linux | 🚧 Planned |

---

## Development

See [CLAUDE.md](CLAUDE.md) for development documentation.

```bash
flutter analyze      # Check for issues
flutter test         # Run tests
```

---

## Part of Parachute

Daily is part of the Parachute ecosystem:

- **[Parachute Daily](../daily/)** — Local voice journaling (this app)
- **[Parachute Chat](../chat/)** — AI assistant with vault context
- **[Parachute Base](../base/)** — Backend server for Chat

---

## License

AGPL — Open source, community-first.
