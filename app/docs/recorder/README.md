# Recorder Documentation

**Voice recorder feature documentation and development resources.**

---

## Overview

This directory contains documentation specific to the voice recorder feature of Parachute, including Omi device integration details, testing guides, and development notes.

---

## Files

### Integration Documentation

**[omi-integration.md](omi-integration.md)**
- Complete Omi device integration guide
- BLE protocol details
- Audio streaming architecture
- Button handling and tap detection
- Background service implementation
- ~19KB of detailed technical documentation

**[omi-integration-summary.md](omi-integration-summary.md)**
- Quick reference for key design decisions
- Audio format choices (WAV for device, M4A for phone)
- Background recording requirements
- Auto-reconnect strategy
- Button tap metadata handling

### Development Guides

**[firmware-migration-plan.md](firmware-migration-plan.md)**
- Firmware update strategy
- Migration path from old to new versions
- Breaking changes and compatibility
- OTA update procedures

**[suggested-testing.md](suggested-testing.md)**
- Comprehensive testing checklist
- Omi device testing scenarios
- Background recording tests
- Edge case handling
- ~14KB of testing procedures

### Work Logs

**[work-log/](work-log/)**
- Development history and decisions
- Bug fixes and feature additions
- Performance optimizations

---

## Related Resources

### In Repository

**Firmware Source Code**
- Location: `/firmware/` (root of repository)
- Zephyr RTOS-based firmware for nRF52840
- Audio capture, BLE, button handling, OTA updates
- See `/firmware/README.md` for build instructions

**App Code**
- Location: `/lib/features/recorder/`
- Flutter implementation
- See `/lib/features/recorder/CLAUDE.md` for context

**Firmware Assets**
- Location: `/assets/firmware/`
- Pre-built firmware binaries
- OTA update instructions

### External

**Omi Device Hardware**
- Seeed XIAO nRF52840 development kit
- PDM microphone
- Bluetooth Low Energy
- Button and LED

---

## Quick Links

### For Developers

- **Start Here**: Read `omi-integration-summary.md` for quick overview
- **Deep Dive**: Read `omi-integration.md` for complete details
- **Testing**: Use `suggested-testing.md` checklist
- **Firmware**: See `/firmware/README.md` for building firmware

### For Testing

1. Read `suggested-testing.md`
2. Follow Omi device pairing procedure
3. Test background recording scenarios
4. Verify button tap detection
5. Test OTA firmware updates (if available)

---

## Key Concepts

### Background Recording
- App maintains BLE connection even when backgrounded
- Button press on device triggers recording
- Audio streams from device → phone via BLE
- Recording saved automatically to storage
- Works even when app is completely closed (killed)

### Audio Formats
- **Phone recordings**: M4A (AAC codec)
- **Device recordings**: WAV (PCM)
- Both compatible with Whisper transcription
- No conversion needed

### Button Tap Patterns
- Single tap: Quick voice note
- Double tap: Extended recording
- Triple tap: Special recording type
- Tap count stored in metadata: `buttonTapCount: 1|2|3`

### Firmware Updates
- Over-the-air (OTA) via Nordic DFU
- MCUboot bootloader for safe updates
- Version checking and compatibility
- See firmware-migration-plan.md for process

---

## Contributing

When working on the recorder feature:

1. **Read existing docs** before making changes
2. **Update relevant docs** when implementing features
3. **Add test cases** to suggested-testing.md
4. **Document decisions** in work-log/ if significant

---

## History

This documentation was migrated from the standalone recorder repository during Phase 1 of the Parachute merger (October 2025). It preserves the development history and integration decisions made during Omi device support development.

---

**Last Updated**: October 25, 2025
