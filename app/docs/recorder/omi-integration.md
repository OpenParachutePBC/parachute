# Omi Device Integration Plan

## Executive Summary

This document outlines the integration of Omi device functionality into the Parachute recorder application. The integration will allow users to pair and use an Omi wearable device to initiate recordings that seamlessly sync with their existing Parachute recordings.

**Key Goal**: Enable users to link an Omi device from Settings and use it to create recordings that appear alongside phone-based recordings in Parachute.

## Architecture Overview

### Current State

#### Parachute App Architecture
- **State Management**: Riverpod (provider-based dependency injection)
- **Audio**: `record` package for local device recording, `just_audio` for playback
- **Storage**: File-based with markdown metadata (sync-friendly)
- **Services**: AudioService, StorageService, WhisperService
- **Screens**: HomeScreen, RecordingScreen, PostRecordingScreen, RecordingDetailScreen, SettingsScreen

#### My-Omi Architecture
- **State Management**: Provider (ChangeNotifier pattern)
- **BLE**: `flutter_blue_plus` for device communication
- **Audio**: Streams raw audio data from device, uses `WavBytesUtil` to build WAV files
- **Firmware**: OTA updates via `nordic_dfu` and `mcumgr_flutter`
- **Services**: DeviceService, DeviceConnection, OmiConnection, RecordingService
- **Providers**: DeviceProvider, CaptureProvider

### Integration Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Parachute App                         │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              UI Layer (Screens)                     │ │
│  │  - HomeScreen (existing)                            │ │
│  │  - RecordingScreen (enhanced)                       │ │
│  │  - SettingsScreen (device pairing UI added)        │ │
│  │  - DevicePairingScreen (NEW)                       │ │
│  └────────────────────────────────────────────────────┘ │
│                         │                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │           Recording Coordinator (NEW)               │ │
│  │  - Unified interface for phone/device recording     │ │
│  │  - Routes to AudioService or OmiCaptureService     │ │
│  └────────────────────────────────────────────────────┘ │
│         │                                   │            │
│  ┌──────────────┐                  ┌─────────────────┐ │
│  │ AudioService │                  │ OmiCaptureService│ │
│  │  (existing)  │                  │     (NEW)       │ │
│  │  - Phone     │                  │  - Device audio │ │
│  │    recording │                  │  - BLE stream   │ │
│  └──────────────┘                  └─────────────────┘ │
│                                             │            │
│                                     ┌────────────────┐  │
│                                     │  OmiBluetoothService│
│                                     │     (NEW)       │  │
│                                     │  - Device scan  │  │
│                                     │  - Connection   │  │
│                                     │  - Button events│  │
│                                     └────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │         StorageService (existing)                   │ │
│  │  - Unified storage for all recordings               │ │
│  │  - Metadata: source (phone/device)                 │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Detailed Integration Plan

### Phase 1: Core BLE Infrastructure (Week 1)

#### 1.1 Add Dependencies
Update `pubspec.yaml`:
```yaml
dependencies:
  flutter_blue_plus: ^1.33.6  # BLE communication
  opus_dart: ^3.0.1           # Opus decoding
  opus_flutter: ^3.0.3        # Opus native support
  nordic_dfu: ^6.1.4+hotfix   # Firmware updates
  mcumgr_flutter: ^0.4.2      # Firmware management
  collection: ^1.18.0         # Utilities
  uuid: ^4.4.0                # Device IDs
```

#### 1.2 Port Core BLE Services
Create new services in `lib/services/omi/`:

**`lib/services/omi/models.dart`**
- Port BLE UUIDs and constants
- Keep same characteristic definitions
- Add codec definitions (PCM8, PCM16, Opus)

**`lib/services/omi/device_connection.dart`**
- Base class for device connections
- Service/characteristic discovery
- Connection state management
- Ping/pong for health checks

**`lib/services/omi/omi_connection.dart`**
- Omi-specific connection implementation
- Audio stream subscription
- Button event subscription
- Battery status monitoring

**`lib/services/omi/omi_bluetooth_service.dart`** (NEW)
- Replaces my-omi's DeviceService
- Adapted to use Riverpod providers
- Device scanning and discovery
- Connection management
- Singleton connection handling

#### 1.3 Create Models
**`lib/models/omi_device.dart`**
```dart
class OmiDevice {
  final String id;
  final String name;
  final DeviceType type;  // omi, openglass, frame
  final int rssi;
  final String? modelNumber;
  final String? firmwareRevision;

  // Serialization for persistence
  Map<String, dynamic> toJson();
  factory OmiDevice.fromJson(Map<String, dynamic> json);
}
```

**Update `lib/models/recording.dart`**
```dart
class Recording {
  // ... existing fields ...
  final RecordingSource source;  // phone, omiDevice
  final String? deviceId;  // If from Omi device

  enum RecordingSource { phone, omiDevice }
}
```

### Phase 2: Audio Capture Integration (Week 2)

#### 2.1 Audio Processing Utilities
**`lib/utils/audio/wav_bytes.dart`**
- Port WavBytesUtil from my-omi
- Handles raw BLE audio data
- Builds WAV file from packets
- Codec support (PCM8, PCM16, Opus)

**`lib/utils/audio/opus_decoder.dart`** (if needed)
- Opus decoding utilities
- Buffer management

#### 2.2 Omi Capture Service
**`lib/services/omi/omi_capture_service.dart`**
```dart
class OmiCaptureService {
  final OmiBluetoothService _bluetoothService;
  WavBytesUtil? _wavBytesUtil;
  bool _isRecording = false;

  // Listen to audio stream from device
  Future<void> startCapture();

  // Process incoming audio packets
  void _onAudioData(List<int> bytes);

  // Save completed recording
  Future<String?> stopCaptureAndSave();

  // Handle button events (start/stop recording)
  void _onButtonEvent(int tapCount);
}
```

#### 2.3 Recording Coordinator
**`lib/services/recording_coordinator.dart`** (NEW)
```dart
class RecordingCoordinator {
  final AudioService _audioService;
  final OmiCaptureService _omiCaptureService;
  final StorageService _storageService;

  RecordingSource _activeSource = RecordingSource.phone;

  // Unified recording interface
  Future<bool> startRecording({RecordingSource? source});
  Future<String?> stopRecording();

  bool get isRecording;
  RecordingSource get activeSource;
}
```

**Riverpod Provider**: `lib/providers/omi_providers.dart`
```dart
final omiBluetoothServiceProvider = Provider<OmiBluetoothService>((ref) {
  final service = OmiBluetoothService();
  service.start();
  ref.onDispose(() => service.stop());
  return service;
});

final omiCaptureServiceProvider = Provider<OmiCaptureService>((ref) {
  final bluetoothService = ref.watch(omiBluetoothServiceProvider);
  return OmiCaptureService(bluetoothService);
});

final recordingCoordinatorProvider = Provider<RecordingCoordinator>((ref) {
  final audioService = ref.watch(audioServiceProvider);
  final omiCaptureService = ref.watch(omiCaptureServiceProvider);
  final storageService = ref.watch(storageServiceProvider);
  return RecordingCoordinator(audioService, omiCaptureService, storageService);
});
```

### Phase 3: UI Integration (Week 3)

#### 3.1 Device Pairing Screen
**`lib/screens/device_pairing_screen.dart`** (NEW)
```dart
class DevicePairingScreen extends ConsumerStatefulWidget {
  // Scan for nearby Omi devices
  // Display list with RSSI indicators
  // Connect to selected device
  // Show connection status
  // Firmware version info
}
```

Features:
- Device scanning with refresh
- Signal strength indicators
- Connection progress
- Device info display
- Disconnect option
- Firmware update button (future)

#### 3.2 Settings Screen Updates
**`lib/screens/settings_screen.dart`**

Add section:
```dart
// Omi Device Section
ListTile(
  leading: Icon(Icons.bluetooth),
  title: Text('Omi Device'),
  subtitle: Text(deviceConnected ? 'Connected: $deviceName' : 'Not connected'),
  trailing: Icon(Icons.chevron_right),
  onTap: () => Navigator.push(...DevicePairingScreen),
)
```

Persist device connection preference in SharedPreferences:
- Last connected device ID
- Auto-reconnect on app start preference

#### 3.3 Home Screen Indicators
**`lib/screens/home_screen.dart`**

Add visual indicators:
- Device connection status badge
- Filter recordings by source (phone/device)
- Device icon on device-sourced recordings

#### 3.4 Recording Screen Updates
**`lib/screens/recording_screen.dart`**

Display active source:
```dart
// Show if recording from phone or device
Text('Recording from: ${source == RecordingSource.phone ? 'Phone' : 'Omi Device'}')
```

Handle device disconnection during recording:
- Show warning if device disconnects
- Auto-save partial recording
- Graceful error handling

### Phase 4: Enhanced Features (Week 4)

#### 4.1 Device-Initiated Recording Flow
1. User taps Omi device button
2. OmiCaptureService receives button event
3. Automatically starts recording (no UI interaction needed)
4. Audio streams to phone via BLE
5. User taps button again to stop
6. Recording auto-saves with device source metadata
7. Appears immediately in HomeScreen list

**Background Recording Support**:
- Handle recordings when app is in background
- Use local notifications to show recording status
- Queue recordings if multiple made while app closed

#### 4.2 Firmware Management
**`lib/services/omi/firmware_service.dart`**
- Port firmware update logic from my-omi
- DFU (Device Firmware Update) via Nordic DFU
- Check for firmware updates
- UI for firmware update process

Assets: Copy firmware files to `assets/firmware/`

#### 4.3 Device Settings
Add device-specific settings:
- Audio codec selection (PCM8, PCM16, Opus)
- Auto-reconnect on app launch
- Button behavior customization (single/double/triple tap)
- Battery level monitoring

#### 4.4 Advanced Features (Optional)
- Multiple device support (pair multiple Omi devices)
- Device nickname/labeling
- Recording quality presets per device
- Sync status indicator (BLE signal strength)

## Technical Considerations

### State Management Migration

My-omi uses Provider with ChangeNotifier, Parachute uses Riverpod. Strategy:

1. **Convert ChangeNotifier to Riverpod Providers**
   - `DeviceProvider` → `omiBluetoothServiceProvider` (Provider)
   - `CaptureProvider` → Use StateNotifier or AsyncNotifier for reactive state

2. **Connection State Stream**
   ```dart
   final deviceConnectionStateProvider = StreamProvider<DeviceConnectionState>((ref) {
     final service = ref.watch(omiBluetoothServiceProvider);
     return service.connectionStateStream;
   });
   ```

3. **Active Device Provider**
   ```dart
   final activeOmiDeviceProvider = StateProvider<OmiDevice?>((ref) => null);
   ```

### Audio Format Compatibility

- **Omi Device Output**: Raw PCM or Opus audio data over BLE
- **Parachute Format**: M4A (AAC) files
- **Solution**:
  1. Save raw audio from device as WAV initially
  2. Convert WAV → M4A in background using FFmpeg (or just_audio supports WAV playback)
  3. OR: Keep WAV format (Whisper API supports both)

### Storage Strategy

Unified storage in StorageService:
```
recordings/
  ├── 2025-01-15-1234567890.m4a  (phone recording)
  ├── 2025-01-15-1234567890.md   (metadata)
  ├── 2025-01-15-1234567891.wav  (device recording)
  └── 2025-01-15-1234567891.md   (metadata with deviceId)
```

Metadata addition:
```yaml
---
id: 1234567891
title: Quick Note
created: 2025-01-15T10:30:00Z
duration: 45
source: omiDevice  # NEW
deviceId: ABC123   # NEW
deviceModel: Omi DevKit  # NEW
---
```

### Connection Management

**Challenge**: Maintain BLE connection stability

**Solution**:
1. Implement connection watchdog (ping every 5 seconds)
2. Auto-reconnect on disconnect (if user preference enabled)
3. Handle iOS/Android background BLE differences
4. Use `autoConnect: true` in flutter_blue_plus

### Permission Handling

Additional permissions needed:
- **Bluetooth**: Scanning and connecting
- **Location** (Android): Required for BLE scanning on Android <12
- **Bluetooth Scan/Connect** (Android 12+): New permission model

Update `AndroidManifest.xml` and `Info.plist` accordingly.

### Platform-Specific Considerations

**iOS**:
- Background BLE requires capabilities in Info.plist
- Limited background processing time
- Use background modes for audio

**Android**:
- Foreground service for continuous BLE connection
- Different permission models by Android version
- Battery optimization whitelist needed

## Testing Strategy

### Unit Tests
- `OmiBluetoothService`: Mock flutter_blue_plus
- `OmiCaptureService`: Test audio buffer handling
- `WavBytesUtil`: Verify WAV file generation
- `RecordingCoordinator`: Source routing logic

### Integration Tests
- Device pairing flow
- Recording from device to storage
- Reconnection handling
- Concurrent phone/device recording prevention

### Manual Testing Checklist
- [ ] Scan and discover Omi device
- [ ] Connect to device successfully
- [ ] Receive button events
- [ ] Start recording from device button
- [ ] Audio streams correctly
- [ ] Stop recording from device button
- [ ] Recording appears in list
- [ ] Playback device recording
- [ ] Disconnect and reconnect
- [ ] Handle disconnection during recording
- [ ] Phone recording still works
- [ ] Filter by source (phone/device)
- [ ] Firmware version displays correctly

## Migration Path

### For my-omi Code
1. **Keep**: Core BLE logic, device connection, audio streaming
2. **Adapt**: Provider → Riverpod, file paths, UI components
3. **Remove**: Full app scaffolding, transcription/AI services (use Parachute's), my-omi specific UI

### File Mapping
```
my-omi → Parachute

lib/services/devices.dart → lib/services/omi/omi_bluetooth_service.dart
lib/services/device_connection.dart → lib/services/omi/device_connection.dart
lib/services/omi_connection.dart → lib/services/omi/omi_connection.dart
lib/services/models.dart → lib/services/omi/models.dart
lib/utils/audio/wav_bytes.dart → lib/utils/audio/wav_bytes.dart
lib/providers/capture_provider.dart → lib/services/omi/omi_capture_service.dart
lib/backend/schema/bt_device/bt_device.dart → lib/models/omi_device.dart
```

## Risk Mitigation

### Risk: BLE connection instability
**Mitigation**: Implement robust reconnection logic, connection health monitoring, graceful degradation

### Risk: Audio sync issues
**Mitigation**: Thorough testing of audio codec handling, buffer size tuning, packet loss recovery

### Risk: Battery drain from BLE
**Mitigation**: Optimize BLE polling intervals, disconnect when not in use, user preference for auto-connect

### Risk: Platform-specific BLE quirks
**Mitigation**: Platform-specific testing, conditional code where needed, fallback behaviors

### Risk: Firmware compatibility
**Mitigation**: Version checking, firmware update mechanism, clear error messages

## Success Metrics

- ✅ User can pair Omi device from Settings in <30 seconds
- ✅ Device-initiated recordings appear in list within 2 seconds of stopping
- ✅ BLE connection remains stable for >30 minutes continuous use
- ✅ Audio quality matches phone recording quality
- ✅ No regression in existing phone recording functionality
- ✅ Battery drain <5% per hour with device connected but idle

## Questions for Discussion

1. **Audio Format**: Should we convert device recordings to M4A to match phone recordings, or keep WAV for simplicity?
   - **Recommendation**: Keep WAV initially, both work with Whisper API

2. **Auto-Connect**: Should the app auto-reconnect to last paired device on launch?
   - **Recommendation**: Yes, with user preference toggle in Settings

3. **Multiple Devices**: Support pairing multiple Omi devices, or single device only?
   - **Recommendation**: Start with single device, add multi-device in future

4. **Background Recording**: Should device button work when app is fully closed?
   - **Recommendation**: Not in MVP, requires significant background processing infrastructure

5. **Firmware Updates**: Include in MVP or defer to Phase 2?
   - **Recommendation**: Basic version check in MVP, full OTA update in Phase 2

6. **Recording Types**: Should device button taps map to recording types (single tap = quick, double = conversation, etc.)?
   - **Recommendation**: Yes, mirror my-omi's button behavior (1 tap = start/stop, 2 taps = AI query, 3 taps = journal)

7. **Button Behavior**: When device button is tapped:
   - Option A: Always start recording regardless of app state
   - Option B: Only record if app is open
   - **Recommendation**: Option B for MVP (app must be open), Option A in Phase 2

## Timeline Summary

- **Week 1**: Core BLE infrastructure, device connection, scanning UI
- **Week 2**: Audio capture, device-initiated recording, storage integration
- **Week 3**: UI polish, settings integration, error handling
- **Week 4**: Firmware updates, testing, documentation, refinement

**Total Estimated Effort**: 4 weeks for MVP

## Next Steps

1. **Review and Approve Plan**: Discuss questions and get alignment
2. **Set Up Branch**: Create `feature/omi-integration` branch
3. **Phase 1 Implementation**: Start with BLE infrastructure
4. **Iterative Testing**: Test on real Omi device after each phase
5. **Documentation**: Update CLAUDE.md with Omi integration details

---

**Document Version**: 1.0
**Last Updated**: 2025-10-08
**Author**: Claude (AI Assistant)
**Status**: Draft - Awaiting Review
