# Week 1.5: UI Integration for Auto-Pause Testing

**Goal**: Validate Week 1's auto-pause implementation with minimal UI changes
**Why**: Test before building complex RNNoise FFI (de-risk Week 2)
**Time**: 1-2 hours

---

## Strategy

Add a **Settings toggle** to switch between:
- **Manual Mode** (V2): Current behavior with pause/resume buttons
- **Auto Mode** (V3): New auto-pause with VAD

This lets us:
1. ✅ Test Week 1 implementation works end-to-end
2. ✅ Compare manual vs auto-pause behavior
3. ✅ Validate VAD chunking quality
4. ✅ Keep existing manual mode as fallback

---

## Implementation Tasks

### 1. Add Settings Toggle (15 min)

**File**: `app/lib/features/settings/screens/settings_screen.dart`

```dart
// Add to settings
SwitchListTile(
  title: Text('Auto-Pause Recording'),
  subtitle: Text('Automatically detect silence (experimental)'),
  value: _autoMode,
  onChanged: (value) => setState(() => _autoMode = value),
)
```

**Storage**: Use `StorageService` to persist preference

### 2. Update LiveRecordingScreen (30 min)

**File**: `app/lib/features/recorder/screens/live_recording_screen.dart`

**Changes**:
```dart
class _LiveRecordingScreenState extends ConsumerState<LiveRecordingScreen> {
  // Switch service based on settings
  late dynamic _transcriptionService; // SimpleTranscriptionService OR AutoPauseTranscriptionService
  
  @override
  void initState() {
    super.initState();
    final autoMode = ref.read(autoModeSettingProvider);
    if (autoMode) {
      _transcriptionService = AutoPauseTranscriptionService(whisperService);
    } else {
      _transcriptionService = SimpleTranscriptionService(whisperService);
    }
  }
}
```

**UI Changes**:
- Auto mode: Hide pause/resume buttons, show "listening..." indicator
- Manual mode: Keep existing pause/resume buttons

### 3. Add VAD Activity Indicator (15 min)

Show when VAD detects speech (optional, nice-to-have):

```dart
// In auto mode, show live speech detection
if (_autoMode && _vadActive) {
  Icon(Icons.mic, color: Colors.green) // Speech detected
} else if (_autoMode) {
  Icon(Icons.mic_off, color: Colors.grey) // Silence
}
```

---

## Testing Checklist

After integration, test:

- [ ] **Manual mode still works** (V2 unchanged)
- [ ] **Auto mode starts recording** (no errors)
- [ ] **Auto-chunking triggers** (speak 2-3 sentences, pause 1s, see segment appear)
- [ ] **Transcription quality** (compare manual vs auto chunks)
- [ ] **Stop & Save works** (final WAV file generated correctly)
- [ ] **Settings toggle persists** (app restart remembers choice)

---

## File Changes Summary

```
app/lib/features/settings/
  screens/settings_screen.dart         # Add toggle
  providers/settings_provider.dart     # Add autoModeProvider

app/lib/features/recorder/
  screens/live_recording_screen.dart   # Conditional service init
  providers/service_providers.dart     # Add autoPauseServiceProvider
```

**Estimate**: 1-2 hours of focused work

---

## After This

✅ **Week 1 validated** → Proceed confidently to Week 2 RNNoise
❌ **Issues found** → Fix before investing in FFI work

This de-risks the entire auto-pause feature!
