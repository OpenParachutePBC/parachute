# Parachute Daily - Development Guide

**Local-first voice journaling app that runs completely standalone.**

---

## Overview

Parachute Daily is a Flutter app for voice-first journaling. Unlike Parachute Chat (which requires a server), Daily runs entirely on-device with local transcription.

**Key Characteristics:**
- **No server required** - Works offline, local-first
- **On-device transcription** - Whisper models, no cloud
- **Voice Activity Detection** - Auto-pause during silence
- **Journals as markdown** - Stored in `Daily/journals/`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       PARACHUTE DAILY                            │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    UI Layer (Screens)                     │   │
│  │  JournalScreen, RecorderScreen, SettingsScreen           │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                 State Layer (Riverpod)                    │   │
│  │  journalProvider, recordingProvider, transcriptionProvider│   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Service Layer                            │   │
│  │  AudioService, TranscriptionService, StorageService      │   │
│  └────────────────────────┬─────────────────────────────────┘   │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Local ML Models                          │   │
│  │  Whisper (transcription), Gemma (titles)                 │   │
│  └──────────────────────────────────────────────────────────┘   │
│                           │                                      │
└───────────────────────────┼──────────────────────────────────────┘
                            │
                            ▼
              ┌───────────────────────────┐
              │      LOCAL VAULT          │
              │  ~/Parachute/Daily/       │
              │  ├── journals/            │
              │  └── assets/              │
              └───────────────────────────┘
```

---

## Directory Structure

```
daily/lib/
├── main.dart                    # App entry point
├── core/                        # Shared infrastructure
│   ├── config/                  # App configuration
│   ├── errors/                  # Error types
│   ├── models/                  # Shared models
│   ├── providers/               # Core Riverpod providers
│   ├── services/                # Core services
│   │   └── search/              # Local search implementation
│   └── theme/                   # Design tokens, themes
│
└── features/                    # Feature modules
    ├── home/                    # Main screen
    │   └── screens/             # HomeScreen
    │
    ├── journal/                 # Journal entries
    │   ├── models/              # JournalEntry, JournalDay
    │   ├── providers/           # Journal state
    │   ├── screens/             # JournalScreen
    │   ├── services/            # JournalService
    │   └── widgets/             # Entry cards, input bar
    │
    ├── recorder/                # Voice recording
    │   ├── models/              # Recording model
    │   ├── providers/           # Recording state
    │   ├── services/            # Audio, transcription
    │   │   ├── audio_service.dart
    │   │   ├── live_transcription_service_v3.dart
    │   │   ├── storage_service.dart
    │   │   └── vad/             # Voice activity detection
    │   └── widgets/             # Recording visualizer
    │
    ├── search/                  # Local search
    │   └── screens/             # SearchScreen
    │
    └── settings/                # App settings
        ├── screens/             # SettingsScreen
        └── widgets/             # Settings sections
```

---

## Key Files

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry point, provider scope |
| `lib/features/journal/services/journal_service.dart` | Journal CRUD operations |
| `lib/features/recorder/services/audio_service.dart` | Audio recording |
| `lib/features/recorder/services/live_transcription_service_v3.dart` | Real-time transcription |
| `lib/features/recorder/services/vad/` | Voice activity detection |
| `lib/core/services/file_system_service.dart` | Vault paths |

---

## Recording Flow

### Voice Capture

```
User taps Record
       │
       ▼
AudioService starts mic stream
       │
       ▼
Audio chunks sent to VAD
       │
       ▼
VAD detects speech → TranscriptionService
       │
       ▼
Whisper model transcribes chunk
       │
       ▼
Text appended to current entry
       │
       ▼
VAD detects silence → Auto-pause (optional)
       │
       ▼
User taps Stop
       │
       ▼
StorageService saves audio + transcript
```

### Transcription Models

Daily uses on-device Whisper models for transcription:

| Model | Size | Speed | Quality |
|-------|------|-------|---------|
| `tiny` | 75MB | Fastest | Good for short clips |
| `base` | 142MB | Fast | Better accuracy |
| `small` | 466MB | Medium | High accuracy |

Models are downloaded on first use and cached locally.

---

## Data Paths

Daily stores all data locally:

| Path | Contents |
|------|----------|
| `Daily/journals/` | Daily journal entries (markdown) |
| `Daily/journals/YYYY/MM/DD.md` | Entry for specific date |
| `assets/YYYY-MM/` | Audio files, photos |

Configured in `FileSystemService`:
```dart
String get journalsPath => path.join(vaultPath, 'Daily', 'journals');
String get assetsPath => path.join(vaultPath, 'assets');
```

---

## Journal Entry Format

```markdown
---
date: 2025-12-30
entries: 3
duration_seconds: 245
---

## 10:30 AM

Voice transcription text goes here...

[Audio: 2025-12-30_10-30-00.opus]

## 2:15 PM

Another entry from later in the day...
```

---

## State Management (Riverpod)

### Core Providers

```dart
// Current journal entries
final journalProvider = StateNotifierProvider<JournalNotifier, JournalState>((ref) {
  return JournalNotifier(ref.read(journalServiceProvider));
});

// Recording state
final recordingProvider = StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
  return RecordingNotifier(
    ref.read(audioServiceProvider),
    ref.read(transcriptionServiceProvider),
  );
});

// Transcription model status
final transcriptionModelProvider = FutureProvider<ModelStatus>((ref) async {
  return ref.read(transcriptionServiceProvider).getModelStatus();
});
```

---

## Commands

```bash
cd daily
flutter pub get                 # Install dependencies
flutter run -d macos            # Run on macOS
flutter run -d android          # Run on Android
flutter analyze                 # Check for issues
flutter test                    # Run tests
```

---

## Voice Activity Detection (VAD)

Daily includes sophisticated VAD for hands-free recording:

### Features
- **Auto-pause**: Stop recording during prolonged silence
- **Speech detection**: Only transcribe when speech is present
- **Noise filtering**: Ignore background noise

### Configuration
```dart
class VadConfig {
  final double speechThreshold = 0.5;
  final Duration silenceTimeout = Duration(seconds: 3);
  final Duration minSpeechDuration = Duration(milliseconds: 250);
}
```

---

## Offline Operation

Daily is designed for offline-first operation:

1. **No network required** for core features
2. **Local transcription** via Whisper models
3. **Local storage** in vault directory
4. **Optional sync** via Git or Syncthing

### First Run
1. App prompts for vault location
2. Downloads transcription model (~75-466MB)
3. Creates `Daily/journals/` structure
4. Ready to record

---

## Adding Features

### New Journal Widget

1. Create widget in `lib/features/journal/widgets/`
2. Use `ref.watch(journalProvider)` for state
3. Access services via `ref.read(journalServiceProvider)`

### New Settings Option

1. Add to `lib/features/settings/widgets/`
2. Use `SharedPreferences` for persistence
3. Update settings screen

### New Audio Processing

1. Add to `lib/features/recorder/services/audio_processing/`
2. Integrate with `AudioService`
3. Test with various audio sources

---

## Debugging

### Recording Issues

```dart
// Check microphone permissions
final status = await Permission.microphone.status;
print('Mic permission: $status');

// Check audio service state
final isRecording = ref.read(recordingProvider).isRecording;
print('Recording: $isRecording');
```

### Transcription Issues

```dart
// Check model status
final status = await transcriptionService.getModelStatus();
print('Model: ${status.modelName}, loaded: ${status.isLoaded}');

// Test transcription
final result = await transcriptionService.transcribe(audioBytes);
print('Transcript: ${result.text}');
```

### Enable Debug Logging

```dart
// In services
debugPrint('[AudioService] Buffer size: ${buffer.length}');
debugPrint('[VAD] Speech detected: $isSpeech');
```

---

## Platform Differences

| Feature | macOS | Android | iOS |
|---------|-------|---------|-----|
| Recording | ✅ | ✅ | ✅ |
| Transcription | ✅ | ✅ | ✅ |
| Background recording | ✅ | ✅ | Limited |
| Omi pendant | ✅ | ✅ | ✅ |

---

## Related Documentation

| Path | Description |
|------|-------------|
| `../CLAUDE.md` | Monorepo overview |
| `../chat/CLAUDE.md` | Chat app (for shared patterns) |
| `../base/claude.md` | Server documentation |

---

**Last Updated:** December 30, 2025
