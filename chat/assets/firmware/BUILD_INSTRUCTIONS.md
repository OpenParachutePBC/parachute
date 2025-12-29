# Firmware Build Instructions

The OTA firmware update feature requires a compiled firmware binary to be present in this directory.

## Quick Build (Recommended)

To build the firmware and automatically place it in this directory:

```bash
cd firmware
./scripts/build-and-integrate.sh
```

This will:
1. Build the firmware using Docker
2. Copy the compiled `zephyr.zip` to `assets/firmware/devkit-v2-firmware-latest.zip`
3. Generate build metadata

**Requirements**: Docker must be installed and running.

## Manual Build

If you have the Zephyr SDK installed locally:

```bash
cd firmware/devkit
# Build for your hardware variant
west build -b xiao_ble_sense_devkitv2_adafruit
# Package for DFU
cd build/zephyr
zip ../../firmware-2.0.12.zip app_update.bin manifest.json
```

Then copy the zip file to this directory as `devkit-v2-firmware-latest.zip`.

## Using Pre-built Firmware

If you don't have Docker or the build environment:

1. Download pre-built firmware from releases
2. Place it in this directory as `devkit-v2-firmware-latest.zip`
3. Run `flutter pub get` to register the asset

## Firmware Version

Current expected firmware version: **2.0.12**

To update this version, modify:
- `lib/services/omi/omi_firmware_service.dart` - Update `_expectedFirmwareVersion`
- `firmware/devkit/prj_xiao_ble_sense_devkitv2-adafruit.conf` - Update `CONFIG_BT_DIS_FW_REV_STR`

## Testing Without Firmware

The OTA update feature will gracefully handle missing firmware:
- "Check for Updates" button will show "No firmware available" if file is missing
- The app will continue to work normally for recording

## File Requirements

The firmware file must be:
- Named: `devkit-v2-firmware-latest.zip`
- Format: Nordic DFU package (zip containing app_update.bin and manifest.json)
- Size: Typically 400-600KB

## Troubleshooting

### Docker not running
```bash
# On macOS
open -a Docker

# On Linux
sudo systemctl start docker
```

### Build fails
Check firmware/README.md for detailed build instructions and troubleshooting.
