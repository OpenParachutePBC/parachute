# Firmware Migration Plan

## Overview

This document outlines the plan for migrating Omi device firmware from the `my-omi` project into the Parachute recorder app, enabling firmware editing and OTA updates directly within this project.

## Current State Analysis

### my-omi Firmware Structure

**Location**: `~/Symbols/Codes/my-omi/firmware/`

**Key Directories**:
- `devkit/` - Development kit firmware (Seeed XIAO nRF52840 Sense)
  - `src/` - C source files for firmware logic
  - `overlay/` - Hardware pin configurations
  - `prj_*.conf` - Build configuration files
- `omi/` - Production Omi device firmware
- `boards/` - Custom board definitions
- `bootloader/` - MCUboot bootloader
- `v2.7.0/` - Zephyr RTOS SDK v2.7.0
- `scripts/` - Build and utility scripts

**Key Source Files** (`devkit/src/`):
- `main.c` - Main entry point, LED state management
- `button.c` - Smart tap detection with debouncing (18KB, most complex)
- `mic.c` - Audio capture initialization and control
- `transport.c` - BLE communication (28KB, handles GATT services)
- `codec.c` - Audio codec selection (PCM8/16, Opus, μLaw)
- `storage.c` - SD card operations for offline recording
- `led.c` - LED control primitives
- `nfc.c` - NFC functionality
- `speaker.c` - Audio playback
- `sdcard.c` - SD card low-level operations
- `usb.c` - USB charging detection
- `utils.h` - Utility macros

**Build System**:
- Zephyr RTOS with nRF Connect SDK v2.7.0
- CMake-based build system
- Docker build support via `scripts/build-docker.sh`
- West tool for dependency management

**Current Firmware Version**: v2.0.12 (DevKit v2)

### Recent Firmware Changes (v2.0.12)

The following patches have been applied to fix critical issues:

**1. Button Detection Fix** (`fix_button_and_led.patch`):
- Changed GPIO interrupt from `GPIO_INT_EDGE_RISING` to `GPIO_INT_EDGE_BOTH`
- Fixed button logic - button is active LOW (0=pressed, 1=released)
- Added 50ms debounce to prevent false triggers
- Made recording state persistent between button presses

**2. LED State Management**:
- Red LED: Recording active (highest priority)
- Blue LED: Connected to app (only when not recording)
- Green LED: Charging (blinks)
- Fixed LED priority so recording LED doesn't get overridden

**3. Microphone Initialization Fix** (`mic_init_fix.patch`):
- Device now starts with mic OFF (`nrfy_gpio_pin_clear(PDM_PWR_PIN)`)
- Prevents auto-recording on boot
- Mic only activates on button press

**4. Smart Tap Behavior**:
- Any tap (single/double/triple) starts recording
- Tap count when stopping determines recording type:
  - Single tap to stop → Standard recording
  - Double tap to stop → AI Query (gets AI response in app)
  - Triple tap to stop → Knowledge Capture (extracts action items)
- Long press (1s+) → Power off device

### Integration with Parachute

**Current Status in Parachute**:
- BLE service UUIDs defined in `lib/services/omi/models.dart`
- Audio codec enum matches firmware codecs (PCM8, PCM16, Opus, μLaw)
- Button event enum matches firmware notifications (single/double/triple tap)
- WAV file generation from BLE audio stream in `lib/utils/audio/wav_bytes_util.dart`
- No firmware files or build system yet

**What We Need**:
- Firmware source code in Parachute repo
- Build scripts for compiling firmware
- Compiled firmware binaries in Flutter assets for OTA
- Documentation for firmware development workflow

## Migration Strategy

### Phase 1: Copy Firmware Structure

**Goal**: Bring firmware source code into Parachute project

**Tasks**:
1. Create `firmware/` directory at project root
2. Copy essential directories from my-omi:
   - `firmware/devkit/` → Complete devkit firmware
   - `firmware/boards/` → Custom board definitions
   - `firmware/bootloader/` → MCUboot bootloader
   - `firmware/scripts/` → Build and utility scripts
3. Create `firmware/README.md` with build instructions
4. Add `.gitignore` for firmware build artifacts

**Files to Copy**:
```
my-omi/firmware/devkit/          → recorder/firmware/devkit/
my-omi/firmware/boards/          → recorder/firmware/boards/
my-omi/firmware/bootloader/      → recorder/firmware/bootloader/
my-omi/firmware/scripts/         → recorder/firmware/scripts/
my-omi/firmware/readme.md        → recorder/firmware/README.md
```

**Files to Skip**:
- `firmware/v2.7.0/` - Zephyr SDK (too large, users install separately)
- `firmware/omi/` - Production firmware (focus on devkit initially)
- `firmware/test/` - Test frameworks (can add later if needed)
- `firmware/build/` - Build artifacts (regenerated)

### Phase 2: Build System Setup

**Goal**: Enable firmware compilation in Parachute project

**Tasks**:
1. Copy build scripts:
   - `scripts/build-docker.sh` - Docker-based build (cross-platform)
   - `scripts/build-and-integrate.sh` - Build + copy to Flutter assets
2. Update paths in build scripts to match new repo structure
3. Test firmware compilation
4. Document prerequisites (Docker or nRF Connect SDK)

**Build Workflow**:
```bash
# Developer workflow
cd firmware
./scripts/build-docker.sh          # Compile firmware
./scripts/build-and-integrate.sh   # Compile + copy to assets
```

**Output**:
- Compiled firmware: `firmware/build/docker_build/zephyr.zip`
- Flutter asset: `assets/firmware/devkit-v2-firmware-2.0.12.zip`

### Phase 3: Asset Integration

**Goal**: Bundle firmware in Flutter app for OTA updates

**Tasks**:
1. Create `assets/firmware/` directory
2. Copy compiled firmware v2.0.12
3. Update `pubspec.yaml` to include firmware assets
4. Update OTA service to reference correct firmware path
5. Test OTA update flow

**pubspec.yaml update**:
```yaml
flutter:
  assets:
    - assets/firmware/
```

**OTA Service Update** (`lib/services/omi/omi_bluetooth_service.dart` or new OTA service):
- Add firmware update methods
- Implement Nordic DFU protocol
- Reference bundled firmware in assets

### Phase 4: Documentation

**Goal**: Document firmware development workflow

**Tasks**:
1. Create `dev-docs/firmware-development.md`:
   - Build instructions
   - Debugging guide
   - Patch creation workflow
   - Version management
2. Update main `CLAUDE.md` with firmware guidance
3. Create `firmware/CHANGELOG.md` to track firmware changes

**Key Documentation Topics**:
- Building firmware (Docker vs nRF Connect SDK)
- Flashing firmware to device
- Serial debugging
- Button behavior customization
- LED state logic
- Audio codec configuration
- Creating patches for bug fixes
- Version increment process

### Phase 5: Version Management

**Goal**: Track firmware versions in Parachute

**Tasks**:
1. Establish version naming convention
2. Create version file readable by app
3. Implement version checking in OTA flow
4. Document version increment process

**Version Format**: `MAJOR.MINOR.PATCH`
- MAJOR: Breaking changes to BLE protocol
- MINOR: New features, compatible with app
- PATCH: Bug fixes

**Version Storage**:
- Firmware: `prj_xiao_ble_sense_devkitv2-adafruit.conf` → `CONFIG_BT_DIS_FW_REV_STR`
- App: Read from device via BLE Device Information Service
- Asset: Filename includes version (e.g., `devkit-v2-firmware-2.0.12.zip`)

### Phase 6: Development Workflow

**Goal**: Enable iterative firmware development

**Workflow**:
1. Make changes to firmware source in `firmware/devkit/src/`
2. Update version in `prj_*.conf` if needed
3. Build firmware: `cd firmware && ./scripts/build-docker.sh`
4. Test on device: Flash via `flash.sh` or OTA
5. If working, integrate: `./scripts/build-and-integrate.sh`
6. Commit firmware source + compiled binary together
7. Update CHANGELOG.md

**Git Workflow**:
- Commit firmware source and binary together
- Use descriptive commit messages (e.g., "firmware: Fix button debouncing (v2.0.13)")
- Tag releases (e.g., `firmware-v2.0.13`)

## Key Firmware Components to Understand

### 1. Button Handling (`button.c`)

**Critical Logic**:
- GPIO pin 5 for button input (active LOW)
- Edge-triggered interrupts on both press and release
- 50ms debounce window
- Tap detection windows:
  - Single tap: < 300ms press duration
  - Double tap: Two taps within 600ms
  - Triple tap: Three taps within 900ms
  - Long press: > 1000ms
- Recording state persists between taps

**BLE Characteristics**:
- Single tap: Notifies app with event code
- Double tap: Notifies app with event code
- Triple tap: Notifies app with event code
- App uses tap count to categorize recording

**Key Functions**:
- `button_pressed_callback()` - GPIO interrupt handler
- `check_button_level()` - Periodic button state check (25 Hz)
- `notify_tap()`, `notify_double_tap()`, `notify_triple_tap()` - BLE notifications

### 2. Audio Streaming (`transport.c`)

**BLE GATT Services**:
- Device Information Service (DIS)
- Audio Service (custom UUID)
- Storage Service (for offline recordings)
- Button Service (button events)

**Audio Characteristics**:
- Audio Stream: Device → App (BLE notifications)
- Codec ID: Indicates audio format (PCM8=1, PCM16=10, Opus=20)
- Audio Packets: Frame-based with sequence numbers

**Packet Format**:
```
[frame_index_low, frame_index_high, frameId, ...audio_data]
```

**Key Functions**:
- `bt_ready()` - Bluetooth initialization
- `send_audio_frame()` - Send audio packet via BLE
- `on_codec_read()` - App queries codec

### 3. Audio Capture (`mic.c`)

**Hardware**:
- PDM (Pulse Density Modulation) microphone
- Power control via GPIO

**States**:
- OFF: Mic powered down (default on boot)
- ON: Mic powered, capturing audio

**Key Functions**:
- `mic_init()` - Initialize PDM peripheral
- `mic_on()` - Power on mic, start capture
- `mic_off()` - Stop capture, power down mic

**Integration**:
- Button press → `mic_on()` → Audio → Transport → BLE → App
- Button release → `mic_off()` → Stop recording

### 4. LED Management (`main.c`, `led.c`)

**LED Priority** (highest to lowest):
1. Red: Recording active
2. Blue: Connected to app
3. Green: Charging (blinks)

**Key Functions**:
- `set_led_red(bool on)` - Recording indicator
- `set_led_blue(bool on)` - Connection indicator
- `set_led_green(bool on)` - Charging indicator
- `set_led_state()` - Main LED state machine (called periodically)

**State Logic**:
```c
if (is_charging) {
    blink_green();
}
if (is_recording) {
    red = true;
    blue = false;
} else if (is_connected) {
    red = false;
    blue = true;
} else {
    red = false;
    blue = false;
}
```

### 5. Codec Selection (`codec.c`)

**Supported Codecs**:
- PCM8: 8-bit PCM, 16kHz, ~128 kbps
- PCM16: 16-bit PCM, 16kHz, ~256 kbps
- Opus: Compressed, 16kHz, ~24 kbps (best for BLE)
- μLaw8: 8-bit μ-law, 16kHz, ~128 kbps
- μLaw16: 16-bit μ-law, 16kHz, ~256 kbps

**Codec IDs** (must match `lib/services/omi/models.dart`):
- 1 = PCM8
- 10 = PCM16
- 20 = Opus
- 11 = μLaw8
- 12 = μLaw16

**Key Functions**:
- `codec_init()` - Set default codec
- `codec_get_id()` - Return current codec ID
- `codec_set(id)` - Change codec

## Migration Checklist

### Phase 1: Structure
- [ ] Create `firmware/` directory
- [ ] Copy `devkit/` source
- [ ] Copy `boards/` definitions
- [ ] Copy `bootloader/`
- [ ] Copy build scripts
- [ ] Create firmware README
- [ ] Add firmware .gitignore

### Phase 2: Build System
- [ ] Update script paths for new repo
- [ ] Test Docker build
- [ ] Test build-and-integrate script
- [ ] Document build prerequisites
- [ ] Verify output matches expected format

### Phase 3: Assets
- [ ] Create `assets/firmware/` directory
- [ ] Copy v2.0.12 firmware binary
- [ ] Update `pubspec.yaml`
- [ ] Implement/update OTA service
- [ ] Test OTA update on device

### Phase 4: Documentation
- [ ] Create firmware development guide
- [ ] Update main CLAUDE.md
- [ ] Create firmware CHANGELOG
- [ ] Document button behavior
- [ ] Document LED states
- [ ] Document codec selection

### Phase 5: Version Management
- [ ] Define version convention
- [ ] Create version tracking system
- [ ] Implement version checking in app
- [ ] Document version increment process

### Phase 6: Testing
- [ ] Build firmware from Parachute repo
- [ ] Flash to device and verify boot
- [ ] Test button single/double/triple tap
- [ ] Test LED states (recording, connected, charging)
- [ ] Test audio streaming
- [ ] Test OTA update
- [ ] Verify app integration

## Benefits of Migration

1. **Single Source of Truth**: All code (app + firmware) in one repo
2. **Coordinated Development**: Make firmware changes alongside app changes
3. **Version Consistency**: Firmware version tracked with app version
4. **Simplified OTA**: Bundled firmware always matches app expectations
5. **Better Documentation**: Firmware docs live with app docs
6. **Easier Onboarding**: New developers see full stack in one place

## Risks and Mitigations

**Risk**: Firmware builds fail in new repo structure
- Mitigation: Test builds thoroughly before committing, keep my-omi as reference

**Risk**: Firmware binary is large, bloats git repo
- Mitigation: Consider Git LFS for firmware binaries if size becomes issue

**Risk**: Zephyr SDK setup is complex for new developers
- Mitigation: Provide Docker build option (no SDK install needed)

**Risk**: Breaking changes to firmware break OTA for existing devices
- Mitigation: Implement version checking, maintain backwards compatibility

## Next Steps

1. Create firmware directory structure in Parachute
2. Copy essential files from my-omi
3. Test firmware build
4. Integrate compiled firmware into Flutter assets
5. Update documentation
6. Commit Phase 4 with firmware foundation

## References

- my-omi firmware: `~/Symbols/Codes/my-omi/firmware/`
- my-omi docs: `~/Symbols/Codes/my-omi/docs/`
- Zephyr RTOS: https://docs.zephyrproject.org/
- nRF Connect SDK: https://developer.nordicsemi.com/nRF_Connect_SDK/
- Nordic DFU: https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.1.0/lib_dfu_transport.html
