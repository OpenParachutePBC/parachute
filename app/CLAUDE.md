# Frontend Context

**Flutter frontend for Parachute - local-first, voice-first capture tool.**

---

## Quick Commands

```bash
cd app && flutter run -d macos   # Run on macOS
cd app && flutter run -d android # Run on Android
cd app && flutter test           # Run tests
cd app && flutter clean          # Clean build
```

---

## Core Architecture

```
Screens (UI) → Providers (Riverpod) → Services → Local File System
                                   → Git Sync (optional)
```

**Stack:** Dart 3.5+ / Flutter 3.24+ / Riverpod state management

**Primary Platforms:** macOS, Android (iOS coming soon)

---

## Critical Implementation Details

### ⚠️ Package Name

```dart
✅ import 'package:app/...'        // Correct
❌ import 'package:parachute/...'  // Wrong - package name is "app"
```

### ⚠️ Riverpod Requirements

**All widgets using providers MUST be wrapped in `ProviderScope`:**
```dart
// main.dart
runApp(ProviderScope(child: ParachuteApp()));

// tests
testWidgets('Test', (tester) async {
  await tester.pumpWidget(ProviderScope(child: MyWidget()));
});
```

**Missing ProviderScope = crash!**

### ⚠️ File Paths

**Always use `FileSystemService` - NEVER hardcode paths:**
```dart
✅ final captures = fileSystemService.capturesPath;
❌ final captures = '~/Parachute/captures/';  // WRONG!
```

**Why:** Vault location and subfolder names are configurable.

### ⚠️ Git Sync Race Conditions

**Don't assume GitSync is ready immediately:**
```dart
✅ if (gitSyncState.isInitialized) {
     await gitSync.commitAndPush();
   }

❌ await gitSync.commitAndPush();  // May fail if not initialized!
```

### ⚠️ API Response Format (Backend Only)

**If using backend, collection endpoints return wrapped objects:**
```dart
✅ final Map<String, dynamic> data = response.data;
   final List<dynamic> spheres = data['spheres'];

❌ final List<dynamic> spheres = response.data;  // CRASHES!
```

---

## Design System

### Design Tokens (`lib/core/theme/design_tokens.dart`)

Centralized brand styling constants:

```dart
// Colors
BrandColors.forest      // Primary green (#40695B)
BrandColors.turquoise   // Accent (#5EA8A7)
BrandColors.cream       // Light background
BrandColors.nightSurface // Dark mode background

// Spacing
Spacing.xs, Spacing.sm, Spacing.md, Spacing.lg, Spacing.xl, Spacing.xxl

// Radii
Radii.sm, Radii.md, Radii.lg

// Typography
TypographyTokens.bodySmall, .bodyMedium, .bodyLarge, .titleMedium, etc.

// Motion
Motion.quick     // 150ms
Motion.standard  // 250ms
Motion.settling  // Curves.easeOutCubic
```

### Brand Components (`lib/core/widgets/brand_components.dart`)

Reusable styled widgets following brand guidelines.

### Settings Section Widgets (`lib/features/settings/widgets/`)

Settings is organized into focused section widgets:
- `expandable_settings_section.dart` - Collapsible section container
- `transcription_section.dart`, `storage_section.dart`, etc. - Individual sections

---

## Key Services

### FileSystemService (`lib/core/services/file_system_service.dart`)

Central service for all file path management:

- `capturesPath` - Path to captures folder
- `spheresPath` - Path to spheres folder
- `vaultPath` - Root vault location
- Platform-specific defaults
- Configurable via Settings

### GitService (`lib/core/services/git/git_service.dart`)

Local Git operations using git2dart (libgit2):

- Repository init, status, add, commit
- GitHub push/pull with PAT authentication
- Auto-commit on recording save

### StorageService (`lib/features/recorder/services/storage_service.dart`)

Recording persistence:

- Save recordings to captures folder
- Load recordings from filesystem
- 30-second cache for performance
- Triggers Git sync on save

### Transcription Services (`lib/features/recorder/services/`)

Platform-adaptive transcription:

- `parakeet_service.dart` - iOS/macOS (Apple Neural Engine)
- `sherpa_onnx_service.dart` - Android (ONNX Runtime)
- `transcription_service_adapter.dart` - Platform detection

### VAD Services (`lib/features/recorder/services/vad/`)

Auto-pause voice recording:

- `simple_vad.dart` - RMS energy-based voice activity detection
- `smart_chunker.dart` - Silence detection → auto-segment
- `simple_noise_filter.dart` - High-pass filter (80Hz)

---

## App Structure

Three main tabs in bottom navigation:

1. **Spheres** - Organize themed knowledge containers
2. **Recorder** - Voice capture with real-time transcription
3. **Files** - Browse vault directory

---

## Data Flow: Recording

```
1. User starts recording
   └─→ AudioService captures audio
   └─→ VAD monitors for silence

2. On silence (1s)
   └─→ SmartChunker triggers chunk
   └─→ TranscriptionServiceAdapter transcribes
   └─→ UI displays in real-time

3. User stops recording
   └─→ Final segment transcribed
   └─→ StorageService saves files
   └─→ GitService commits (if enabled)

4. Recording appears in list
   └─→ Loaded from local filesystem
```

---

## Terminology

- **Spheres** (not "Spaces") - Themed knowledge containers
- **Captures** - Voice recordings and notes
- **Vault** - The `~/Parachute/` folder containing all data

---

## Testing

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/features/recorder/services/vad/simple_vad_test.dart

# 116 tests for audio pipeline
flutter test test/features/recorder/
```

---

## Documentation

- Root `CLAUDE.md` - Overall project guidance
- Root `ARCHITECTURE.md` - System design
- `app/lib/features/recorder/CLAUDE.md` - Recorder-specific docs
- `docs/recorder/` - Omi integration guides

---

**Last Updated:** November 30, 2025
