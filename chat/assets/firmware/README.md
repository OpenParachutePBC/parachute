# Firmware Assets

This directory contains compiled Omi device firmware for over-the-air (OTA) updates.

## Current Status

⚠️ **No firmware binary is currently included in this repository.**

The OTA update feature is fully implemented but requires you to build or download the firmware binary.

## Quick Start

### Option 1: Build Firmware (Recommended)

```bash
cd firmware
./scripts/build-and-integrate.sh
```

This automatically builds and places firmware in this directory. **Requires Docker**.

### Option 2: Download Pre-built Firmware

Download the latest firmware from project releases and place it as:

- `devkit-v2-firmware-latest.zip`

### Option 3: Skip Firmware (Testing Only)

The app works without firmware - OTA updates just won't be available. The UI will show "No updates available" if firmware is missing.

## File Requirements

The firmware file must be:

- **Name**: `devkit-v2-firmware-latest.zip`
- **Format**: Nordic DFU package (contains `app_update.bin` and `manifest.json`)
- **Size**: ~400-600KB

## Current Expected Version

**2.0.12** - Defined in `lib/services/omi/omi_firmware_service.dart`

## OTA Update Flow

1. App connects to Omi device via BLE
2. App reads firmware version from device
3. If newer firmware available in assets, prompts user
4. User confirms update
5. App initiates Nordic DFU protocol
6. Device updates and reboots

## Version Management

Firmware version is defined in:

```
firmware/devkit/prj_xiao_ble_sense_devkitv2-adafruit.conf
CONFIG_BT_DIS_FW_REV_STR="X.Y.Z"
```

Asset filename must match this version for proper OTA detection.

## File Size

Typical firmware size: ~500KB - 1MB (compressed)

## Adding to Flutter Assets

Ensure `pubspec.yaml` includes:

```yaml
flutter:
  assets:
    - assets/firmware/
```

Then run `flutter pub get` to register new assets.
