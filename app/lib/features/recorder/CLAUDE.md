# Recorder Feature - CLAUDE.md

**Context for Claude Code when working with the voice recorder feature.**

---

## Overview

The recorder feature provides voice recording capabilities with Omi hardware device support and local Whisper transcription.

**Location**: `lib/features/recorder/`

**Key Features**:
- Local audio recording (microphone)
- Omi device Bluetooth integration for pendant recording
- Local Whisper AI transcription
- Recording management (list, play, delete, share)
- Firmware OTA updates for Omi devices

---

## Architecture

```
features/recorder/
├── models/           # Data models (Recording, OmiDevice, etc.)
├── providers/        # Riverpod state providers
├── repositories/     # Data access layer
├── screens/          # UI screens
├── services/         # Business logic
│   └── omi/         # Omi device-specific services
├── utils/           # Helper utilities
└── widgets/         # Reusable UI components
```

---

## Key Services

### AudioService (`services/audio_service.dart`)
Handles local microphone recording and playback.
- Uses `record` package for recording
- Uses `just_audio` for playback
- Manages recording state and file paths

### StorageService (`services/storage_service.dart`)
Manages recording persistence using SharedPreferences.
- Saves/loads recording metadata
- File system operations
- **IMPORTANT**: This will be abstracted for Phase 3 backend integration

### WhisperService (`services/whisper_service.dart`)
Local AI transcription using Whisper GGML models.
- Downloads and manages Whisper models
- Transcribes recordings locally on-device
- No cloud API calls needed

### Omi Services (`services/omi/`)
Bluetooth integration with Omi hardware pendant:
- `omi_bluetooth_service.dart` - Device discovery, pairing, **auto-reconnect**
- `omi_connection.dart` - Connection management
- `device_connection.dart` - Audio streaming
- `omi_firmware_service.dart` - OTA firmware updates (**reactive UI with ChangeNotifier**)

**Auto-Reconnect**: Enabled by default, happens in `HomeScreen.initState()`. Uses `lastPairedDeviceProvider` from SharedPreferences.

**Firmware Updates**: Service extends `ChangeNotifier` to provide real-time UI updates. Navigation is blocked during update via `PopScope` to prevent bricking.

---

## Important Models

### Recording (`models/recording.dart`)
```dart
class Recording {
  String id;
  String title;
  String? description;
  DateTime timestamp;
  int durationMillis;
  String filePath;
  String? transcription;
  RecordingSource source; // phone or omi
}
```

### OmiDevice (`models/omi_device.dart`)
Represents a paired Omi Bluetooth device with firmware info.

---

## Common Tasks

### Adding a New Field to Recording
1. Update `models/recording.dart`
2. Update `toJson()` and `fromJson()` methods
3. Update `repositories/recording_repository.dart` if needed
4. Update UI in relevant screens

### Modifying Recording Storage
**Current**: Uses SharedPreferences + local file system
**Future (Phase 3)**: Will use backend API

When modifying storage:
- Keep changes in `StorageService`
- Use interface/abstract pattern (see Phase 3 plan)
- Don't couple UI directly to storage implementation

---

## UI Screens

**Note:** Most recording UI is now handled through the Journal feature (`lib/features/journal/`).
The recorder feature now provides services and widgets used by the journal.

- `device_pairing_screen.dart` - Omi device setup (iOS/Android only)

---

## Dependencies

### Audio
- `record: ^6.1.2` - Microphone recording
- `just_audio: ^0.9.42` - Audio playback

### Bluetooth
- `flutter_blue_plus: ^1.33.6` - Omi device communication

### AI
- `whisper_ggml: ^1.7.0` - Local transcription

### Audio Codecs
- `opus_dart` / `opus_flutter` - Opus codec for Omi BLE audio decoding

### Utilities
- `permission_handler` - Microphone/Bluetooth permissions
- `flutter_local_notifications` - Background recording notifications
- `nordic_dfu` - Omi firmware updates

---

## Common Issues

### Permission Errors
Ensure macOS entitlements include:
- `com.apple.security.device.audio-input`
- `com.apple.security.files.user-selected.read-write`

### Omi Connection Issues
- Check Bluetooth permissions
- Verify FlutterBluePlus initialization in main.dart
- Opus codec must be initialized for Omi audio decoding
- **Auto-reconnect**: Check logs for "[HomeScreen] Attempting auto-reconnect"
- **Firmware updates**: Don't close app during update - navigation is blocked for safety

### Whisper Transcription Failures
- Model must be downloaded first (check settings)
- Requires sufficient device storage
- Processing can be slow on large files

---

## Future Integration (Phase 3)

The recorder will integrate with Parachute backend:

**Planned Changes**:
- Upload recordings to cloud storage
- Backend transcription API (alternative to local Whisper)
- Cross-device sync
- AI chat can reference recordings
- Shared recording links

**Preparation**:
- StorageService uses interface pattern for easy swap
- Recording model has optional `cloudUrl` field (add in Phase 3)
- Keep business logic separate from storage implementation

---

## Testing

**Manual Testing**:
```bash
flutter run -d macos
# Navigate to "Recorder" tab
# Test recording, playback, transcription
```

**Omi Testing** (requires hardware):
- Pair Omi device via settings
- Start recording from device
- Verify audio streams to app
- Test firmware update if available

---

## Related Documentation

**Project Documentation:**
- Main `CLAUDE.md` - Project-wide context

**Recorder-Specific:**
- `docs/recorder/` - Omi integration guides, testing procedures, dev notes
  - `omi-integration.md` - Complete Omi BLE protocol and architecture
  - `omi-integration-summary.md` - Quick reference for key decisions
  - `firmware-migration-plan.md` - Firmware update strategy
  - `suggested-testing.md` - Comprehensive testing checklist

**Firmware:**
- `firmware/` - Omi device firmware source code (Zephyr RTOS, nRF52840)
  - `firmware/README.md` - How to build and flash firmware
  - `firmware/devkit/` - Development kit firmware
  - `firmware/scripts/` - Build and utility scripts
- `assets/firmware/` - Pre-built firmware binaries for OTA updates
