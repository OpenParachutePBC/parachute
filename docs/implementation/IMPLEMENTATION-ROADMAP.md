# Auto-Pause + Noise Suppression Implementation Roadmap

**Date**: November 7, 2025
**Goal**: Port RichardTate's proven auto-pause and noise suppression to Parachute
**Strategy**: Maximum code reuse, phased delivery, FFI for native libraries

---

## 🎯 What We're Building

A voice recording system that:
1. **Auto-detects silence** - No manual pause button needed
2. **Removes background noise** - Keyboards, fans, traffic, TV
3. **Segments intelligently** - Natural speech boundaries (1s silence)
4. **Transcribes cleanly** - Better Whisper accuracy with clean audio

**Exactly like RichardTate**, but in Flutter.

---

## 📊 Code Analysis

RichardTate has **1,437 lines** of audio processing code:

| Component | Lines | Complexity | Our Strategy |
|-----------|-------|------------|--------------|
| **VAD** | 148 | ⭐ Simple | **Direct port to Dart** |
| **Resampler** | 119 | ⭐ Simple | **Direct port to Dart** |
| **Chunker** | 225 | ⭐⭐ Medium | **Direct port to Dart** |
| **Pipeline** | 318 | ⭐⭐ Medium | **Adapt for Flutter** |
| **RNNoise** | 228 | ⭐⭐⭐ Complex | **FFI bindings to C** |
| **Whisper** | 197 | N/A | **Already have it** ✅ |

**Total portable**: ~1,040 lines we can directly reuse!

---

## 🗺️ Three-Week Roadmap

### Week 1: Pure Dart Ports (No Dependencies)

**What**: Port VAD, Resampler, Chunker from Go to Dart
**Why**: Get auto-pause working fast, validate approach
**Deliverable**: ✅ Auto-pause WITHOUT noise suppression

**Tasks**:
- [x] Day 1-2: Port `vad.go` → `simple_vad.dart` + `resample.go` → `resampler.dart`
- [x] Day 3-4: Port `chunker.go` → `smart_chunker.dart`
- [x] Day 5: Test against RichardTate, validate identical behavior

**Files created**:
```
app/lib/features/recorder/services/
  vad/
    simple_vad.dart               # 148 lines (direct port)
    smart_chunker.dart            # 225 lines (direct port)
  audio_processing/
    resampler.dart                # 119 lines (direct port)
```

**End of Week 1**: Users can record with auto-pause in quiet environments!

---

### Week 2: RNNoise Integration (FFI Magic)

**What**: Build native RNNoise libraries + create Dart FFI bindings
**Why**: Add noise suppression for real-world environments
**Deliverable**: ✅ Complete RichardTate-quality pipeline

**Tasks**:
- [x] Day 1-2: Compile RNNoise for iOS, Android, macOS
- [x] Day 3-4: Create FFI bindings (`rnnoise_ffi.dart`)
- [x] Day 5: Build `RichardTatePipeline` - full integration

**Files created**:
```
app/lib/features/recorder/services/
  audio_processing/
    rnnoise_ffi.dart              # FFI bindings to C
    rnnoise_processor.dart        # High-level wrapper
  live_transcription_service_v3.dart  # Complete pipeline

app/
  ios/Frameworks/librnnoise.dylib
  android/src/main/jniLibs/*/librnnoise.so
  macos/Frameworks/librnnoise.dylib
```

**End of Week 2**: Production-quality auto-pause + noise suppression!

---

### Week 3: Polish & Ship

**What**: UI, settings, edge cases, testing
**Why**: Make it production-ready
**Deliverable**: ✅ Ship to users!

**Tasks**:
- [x] Day 1-2: Settings UI, VAD indicators, calibration screen
- [x] Day 3-4: Edge cases, battery optimization, error handling
- [x] Day 5: User testing (quiet, noisy, background sounds)

**End of Week 3**: Feature complete and polished!

---

## 🔧 Technical Architecture

### The Pipeline (Mirrors RichardTate Exactly)

```
┌─────────────────────────────────────────────────────────┐
│                    User speaks into mic                 │
└────────────────────┬────────────────────────────────────┘
                     ↓
         Flutter AudioRecorder (16kHz, mono PCM)
                     ↓
    ┌────────────────────────────────────────┐
    │     RichardTatePipeline                │
    │                                        │
    │  1. RNNoise (FFI → C library)         │
    │     • Upsample 16kHz → 48kHz          │
    │     • Denoise (removes background)     │
    │     • Downsample 48kHz → 16kHz        │
    │                                        │
    │  2. VAD (Pure Dart port)              │
    │     • RMS energy calculation          │
    │     • Speech vs silence detection      │
    │                                        │
    │  3. SmartChunker (Pure Dart port)     │
    │     • Accumulate clean audio          │
    │     • Monitor VAD for 1s silence      │
    │     • Trigger when silence detected    │
    │                                        │
    │  4. WhisperLocalService (existing)    │
    │     • Transcribe clean segment        │
    │     • Return text                      │
    └────────────────────────────────────────┘
                     ↓
          Display transcription in UI
```

### Key Files

```
richardtate-port-strategy.md         # Technical deep-dive (this exists)
auto-pause-vad-implementation.md     # Original analysis (this exists)
noise-suppression-summary.md         # Quick reference (this exists)
IMPLEMENTATION-ROADMAP.md            # This file - your action plan
```

---

## 📝 Development Checklist

### Week 1: Pure Dart Ports

#### VAD Implementation
- [ ] Create `app/lib/features/recorder/services/vad/simple_vad.dart`
- [ ] Port `calculateEnergy()` - RMS calculation
- [ ] Port `processFrame()` - Frame-by-frame analysis
- [ ] Port `shouldChunk()` - Silence detection logic
- [ ] Add `reset()`, `stats()` methods
- [ ] Write unit tests (compare vs RichardTate output)

#### Resampler Implementation
- [ ] Create `app/lib/features/recorder/services/audio_processing/resampler.dart`
- [ ] Port `upsample16to48()` - Linear interpolation
- [ ] Port `downsample48to16()` - Averaging for anti-aliasing
- [ ] Add float32 variants (for RNNoise)
- [ ] Write roundtrip tests (16→48→16 should be lossless)

#### Chunker Implementation
- [ ] Create `app/lib/features/recorder/services/vad/smart_chunker.dart`
- [ ] Port `SmartChunkerConfig` class
- [ ] Port `processSamples()` - Buffer accumulation
- [ ] Port `checkAndChunk()` - Silence trigger logic
- [ ] Port `flush()` - Handle final segment
- [ ] Wire up VAD integration
- [ ] Write integration tests

#### Integration Testing
- [ ] Record test audio in RichardTate
- [ ] Process same audio in Parachute
- [ ] Compare chunk boundaries
- [ ] Tune thresholds if needed
- [ ] Document calibration procedure

### Week 2: RNNoise FFI

#### Build Native Libraries
- [ ] Clone RNNoise: `git clone https://github.com/xiph/rnnoise`
- [ ] Compile for iOS arm64 (use Xcode toolchain)
- [ ] Compile for Android arm64-v8a (use NDK)
- [ ] Compile for Android armeabi-v7a (use NDK)
- [ ] Compile for macOS universal (arm64 + x86_64)
- [ ] Test libraries on real devices
- [ ] Document build process

#### FFI Bindings
- [ ] Create `rnnoise_ffi.dart` with function signatures
- [ ] Implement `initialize()` - Load library
- [ ] Implement `processFrame()` - Core denoising
- [ ] Implement `dispose()` - Memory cleanup
- [ ] Test for memory leaks (run for hours)
- [ ] Handle platform differences

#### High-Level Wrapper
- [ ] Create `rnnoise_processor.dart`
- [ ] Implement `processChunk()` API (matches RichardTate)
- [ ] Handle 16kHz ↔ 48kHz resampling internally
- [ ] Buffer incomplete frames
- [ ] Test with real audio

#### Pipeline Integration
- [ ] Create `live_transcription_service_v3.dart`
- [ ] Implement `RichardTatePipeline` class
- [ ] Wire up: RNNoise → VAD → Chunker → Whisper
- [ ] Test end-to-end flow
- [ ] Measure latency (should be 1-3s like RichardTate)

### Week 3: Polish

#### Settings UI
- [ ] Add toggle: "Auto-pause on silence"
- [ ] Add toggle: "Background noise suppression"
- [ ] Add slider: "Silence threshold" (0.5s - 3s)
- [ ] Add calibration button
- [ ] Show VAD status indicators
- [ ] Show silence countdown

#### Calibration Screen
- [ ] Step 1: Measure background noise (5s silence)
- [ ] Step 2: Measure speech level (read sentence)
- [ ] Calculate optimal threshold
- [ ] Save to settings
- [ ] Allow re-calibration

#### Edge Cases
- [ ] Very short utterances (< 1s speech)
- [ ] Very long monologues (> 30s)
- [ ] Rapid speech with short pauses
- [ ] Background voices (multiple speakers)
- [ ] App backgrounding during recording
- [ ] Low battery scenarios

#### Testing
- [ ] Test in quiet room (office, bedroom)
- [ ] Test with keyboard typing
- [ ] Test with fan/AC running
- [ ] Test with TV/music in background
- [ ] Test with traffic outside
- [ ] Test with multiple speakers
- [ ] Battery usage profiling

---

## 🎨 UI Mockups

### Recording Screen with VAD

```
┌─────────────────────────────────────┐
│ Recording: 2:34                     │
├─────────────────────────────────────┤
│                                     │
│ 🟢 Speaking                         │
│ Silence: 0.3s / 1.0s                │
│                                     │
│ ─────────────────────────────────── │
│                                     │
│ 💭 Segment 1 (auto) - 0:45          │
│ "I'm thinking about implementing    │
│ automatic pause detection..."       │
│                                     │
│ 🟢 Segment 2 (auto) - 0:32          │
│ [Transcribing...]                   │
│                                     │
│ 🔵 Listening for speech...          │
│                                     │
│ ─────────────────────────────────── │
│                                     │
│ [    Stop Recording    ]            │
│ [  Manual Pause (old)  ] ← optional │
└─────────────────────────────────────┘
```

### Settings

```
┌─────────────────────────────────────┐
│ Recording Settings                  │
├─────────────────────────────────────┤
│                                     │
│ Auto-pause Detection          🆕    │
│ ◉ Enabled  ○ Disabled               │
│                                     │
│ Silence threshold: [====|===] 1.0s  │
│                                     │
│ Background Noise Suppression  🆕    │
│ ◉ Enabled  ○ Disabled               │
│   ⚠️ Increases battery usage        │
│                                     │
│ [ Calibrate Microphone ]            │
│                                     │
│ Show VAD Indicators                 │
│ ◉ Enabled  ○ Disabled               │
│                                     │
└─────────────────────────────────────┘
```

---

## 📚 Documentation Created

1. **`richardtate-port-strategy.md`** ← Technical deep-dive
   - Code mapping Go → Dart
   - FFI binding details
   - Line-by-line port instructions

2. **`auto-pause-vad-implementation.md`** ← Original analysis
   - How RichardTate works
   - Flutter VAD options
   - Noise suppression research

3. **`noise-suppression-summary.md`** ← Quick reference
   - Why RNNoise matters
   - Implementation options
   - Phased approach

4. **`IMPLEMENTATION-ROADMAP.md`** ← This file
   - Week-by-week plan
   - Checklists
   - Architecture overview

---

## 🚀 Getting Started

### Day 1 Task: Port VAD

```bash
# 1. Create the file
touch app/lib/features/recorder/services/vad/simple_vad.dart

# 2. Reference RichardTate source
cat ~/Symbols/Codes/richardtate/server/internal/transcription/vad.go

# 3. Port function-by-function
# Start with calculateEnergy(), then processFrame(), etc.

# 4. Test as you go
flutter test test/vad_test.dart
```

See `richardtate-port-strategy.md` for detailed code mappings.

---

## ✅ Definition of Done

**Week 1 Complete** when:
- [ ] All VAD unit tests pass
- [ ] Resampler roundtrip test passes
- [ ] Chunker correctly segments test audio
- [ ] Can record with auto-pause (without noise suppression)
- [ ] Behavior matches RichardTate on same test files

**Week 2 Complete** when:
- [ ] RNNoise libraries built for all platforms
- [ ] FFI bindings working on iOS + Android
- [ ] No memory leaks after 1-hour test
- [ ] Full pipeline working end-to-end
- [ ] Transcription quality improved in noisy environments

**Week 3 Complete** when:
- [ ] Settings UI implemented
- [ ] Calibration flow working
- [ ] All edge cases handled
- [ ] Tested in 5+ different environments
- [ ] Battery usage acceptable (< 5% per hour)
- [ ] Ready to ship! 🎉

---

## 🤝 License Compliance

- **RichardTate**: MIT License ✅
- **RNNoise**: BSD-3-Clause ✅
- **Attribution**: Add to app credits

All compatible with commercial use.

---

## 💡 Key Insights

1. **Port, don't rewrite** - RichardTate's code is battle-tested
2. **Phased delivery** - Ship VAD first, add RNNoise later
3. **FFI is the key** - RNNoise quality requires native library
4. **Test against source** - Compare output to validate ports
5. **Users will love it** - No more manual pause button!

---

## 🎯 Ready to Start?

**Recommended first step**:

```bash
# Create VAD file and start porting
cd app
mkdir -p lib/features/recorder/services/vad
touch lib/features/recorder/services/vad/simple_vad.dart

# Open both files side by side
code ~/Symbols/Codes/richardtate/server/internal/transcription/vad.go
code lib/features/recorder/services/vad/simple_vad.dart

# Port function by function, test as you go!
```

See detailed code mappings in `richardtate-port-strategy.md`.

---

**Last Updated**: November 7, 2025
**Next Review**: After Week 1 completion
**Questions?**: Check the other docs in `docs/implementation/`
