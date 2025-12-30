# Parachute Daily

**Local-first voice journaling — capture thoughts wherever you are.**

---

## What is Parachute Daily?

Daily is a voice-first journaling app that runs entirely on your device. No server, no cloud, no account required.

- **Voice-first**: Tap to record, speak your thoughts
- **Local-first**: Everything stays on your device
- **On-device transcription**: Whisper models, no internet needed
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
- Real-time transcription as you speak
- Voice activity detection for hands-free recording
- Support for Omi pendant (Bluetooth capture device)

### Journal Organization
- Daily entries organized by date
- Audio files preserved alongside transcripts
- Full-text search across all entries

### Offline Operation
- Works without internet connection
- Local Whisper models for transcription
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
| iOS | 🚧 Coming soon |
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
