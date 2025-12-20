# Omi Integration - Key Decisions & Summary

## Design Decisions (Finalized)

### 1. Audio Format: WAV ✅
- Device recordings saved as **WAV files**
- Phone recordings remain M4A
- Both work with Whisper API
- No conversion needed

### 2. Background Recording: REQUIRED ✅
**Critical Feature:** Device button must work when app is:
- ✅ Open in foreground
- ✅ Backgrounded
- ✅ Completely closed (killed)

Recording flow:
1. User taps Omi device button (anywhere, anytime)
2. Audio streams from device → phone via BLE
3. Background service processes and saves to storage
4. Recording appears in app when opened

### 3. Auto-Reconnect: YES ✅
- Reconnect to last paired device on app launch
- Maintain background BLE connection
- Auto-reconnect if connection drops

### 4. Button Tap Metadata: Save in Markdown ✅
- Single tap (1), double tap (2), triple tap (3)
- All saved the same way to storage
- Tap count stored in metadata: `buttonTapCount: 1|2|3`
- Future-proof for different processing types

### 5. Storage Format
```
recordings/
  ├── 2025-01-15-1234567890.m4a  (phone)
  ├── 2025-01-15-1234567890.md
  ├── 2025-01-15-1234567891.wav  (device)
  └── 2025-01-15-1234567891.md   (with buttonTapCount)
```

Metadata example:
```yaml
---
id: 1234567891
title: Quick Note
created: 2025-01-15T10:30:00Z
duration: 45
source: omiDevice
deviceId: ABC123
buttonTapCount: 1
---
```

## Critical Components

### 1. OmiBackgroundService (NEW - MOST IMPORTANT)
- Runs continuously when device paired
- Maintains BLE connection in background
- Listens for button events 24/7
- Processes audio and saves recordings
- Works on iOS (background modes) and Android (foreground service)

### 2. Platform-Specific Requirements

**iOS:**
- Background modes: `bluetooth-central`, `audio`, `processing`
- Background task processing for file I/O
- ~30 second limit for saving recordings

**Android:**
- Foreground service with persistent notification
- Wake locks during recording
- Battery optimization whitelist request

### 3. Audio Pipeline
```
Omi Device
  ↓ (BLE audio stream)
OmiConnection.audioStream
  ↓ (raw bytes)
WavBytesUtil.storeFramePacket()
  ↓ (buffer audio)
WavBytesUtil.buildWavFile()
  ↓ (WAV bytes)
StorageService.saveRecording()
  ↓
recordings/YYYY-MM-DD-{id}.wav + .md
```

## Implementation Phases

### Phase 1: BLE Infrastructure (Week 1-2)
- [ ] Add dependencies (flutter_blue_plus, notifications, etc.)
- [ ] Platform setup (iOS Info.plist, Android manifest)
- [ ] Port BLE services from my-omi
- [ ] Create OmiDevice model
- [ ] Update Recording model (add source, deviceId, buttonTapCount)

### Phase 2: Background Recording (Week 2-3) ⚠️ CRITICAL
- [ ] Implement OmiBackgroundService
- [ ] iOS background task processing
- [ ] Android foreground service
- [ ] Port WavBytesUtil for WAV generation
- [ ] Local notifications for recording status
- [ ] End-to-end background recording flow

### Phase 3: UI Integration (Week 3-4)
- [ ] Device pairing screen
- [ ] Settings screen updates
- [ ] Home screen connection indicator
- [ ] Recording source badges
- [ ] Error handling UI

### Phase 4: Testing & Polish (Week 4)
- [ ] Background recording on iOS/Android
- [ ] Battery drain testing
- [ ] Connection stability (24+ hours)
- [ ] Edge cases and error handling

### Phase 5: Documentation (Week 5)
- [ ] Update CLAUDE.md
- [ ] User guide
- [ ] Troubleshooting docs

## Key Technical Challenges

### 1. Background BLE Connection
**Challenge:** Keep BLE alive when app not in foreground
**Solution:**
- iOS: Background modes + BGProcessingTask
- Android: Foreground service + sticky service
- Connection watchdog with auto-reconnect

### 2. Background Audio Processing
**Challenge:** Save recordings when app is killed
**Solution:**
- iOS: Request background time when button pressed
- Android: Foreground service survives app death
- Queue recordings if multiple made while app closed

### 3. Platform Differences
**Challenge:** iOS vs Android background behavior
**Solution:**
- Platform-specific service implementations
- Conditional code paths
- Extensive testing on both platforms

## Success Criteria

- ✅ Device button works with app closed
- ✅ Recordings appear when app reopened
- ✅ BLE connection stable for 24+ hours
- ✅ Battery drain <5% per hour
- ✅ Background success rate >95%
- ✅ Save time <2 seconds
- ✅ No regression in phone recording

## File Structure

```
lib/
├── models/
│   ├── recording.dart (UPDATE: add source, deviceId, buttonTapCount)
│   └── omi_device.dart (NEW)
├── services/
│   ├── omi/
│   │   ├── models.dart (NEW: BLE UUIDs, codecs)
│   │   ├── device_connection.dart (NEW)
│   │   ├── omi_connection.dart (NEW)
│   │   ├── omi_bluetooth_service.dart (NEW)
│   │   ├── omi_capture_service.dart (NEW)
│   │   └── omi_background_service.dart (NEW - CRITICAL)
│   ├── notification_service.dart (NEW)
│   └── storage_service.dart (UPDATE: support WAV + buttonTapCount)
├── providers/
│   └── omi_providers.dart (NEW: Riverpod providers)
├── screens/
│   ├── device_pairing_screen.dart (NEW)
│   ├── settings_screen.dart (UPDATE)
│   └── home_screen.dart (UPDATE)
└── utils/
    └── audio/
        └── wav_bytes.dart (NEW: from my-omi)
```

## Dependencies to Add

```yaml
flutter_blue_plus: ^1.33.6
opus_dart: ^3.0.1
opus_flutter: ^3.0.3
flutter_local_notifications: ^17.0.0
workmanager: ^0.5.2
collection: ^1.18.0
uuid: ^4.4.0
```

## Next Steps

1. ✅ Plan finalized and approved
2. Create `feature/omi-integration` branch
3. Start Phase 1 implementation
4. Test on real Omi device after each phase
5. Weekly progress check-ins

---

**Status**: Ready for Implementation
**Timeline**: 5 weeks
**Priority**: Background recording is critical - most effort goes here
**Full Plan**: See `omi-integration.md` for complete details
