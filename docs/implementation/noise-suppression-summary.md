# Noise Suppression for Parachute - Quick Summary

**Date**: November 7, 2025
**Context**: Based on RichardTate analysis

---

## Yes, RichardTate Does Noise Suppression!

RNNoise runs **first in the pipeline**, before VAD and before Whisper. This is crucial for quality.

### The RichardTate Pipeline

```
Microphone Audio (16kHz)
    ↓
🎛️ RNNoise (removes keyboards, fans, traffic, background voices)
    ↓
🎤 VAD (detects speech vs silence on CLEAN audio)
    ↓
✂️ Auto-segment on 1s silence
    ↓
🗣️ Whisper (transcribes CLEAN audio)
```

### What RNNoise Removes

- ✅ Keyboard typing sounds
- ✅ Fan noise / AC hum
- ✅ Traffic outside
- ✅ Background TV/music
- ✅ Other people talking
- ✅ Mouse clicks
- ✅ Paper rustling

**Result:** Much better VAD accuracy + better Whisper transcription quality

---

## Flutter Implementation Options

### Recommended: Start Simple, Add Later

**Phase 1: Ship VAD without noise suppression**
- Validate auto-pause works in quiet environments
- Get user feedback quickly
- ~1 week to implement

**Phase 2: Add WebRTC noise suppression if needed**
- If users report noise problems, add `flutter_webrtc`
- Built-in noise suppression (based on RNNoise)
- Already in Flutter ecosystem
- ~2-3 days to integrate

**Phase 3: Consider full RNNoise FFI (advanced)**
- Only if WebRTC isn't sufficient
- Requires native code compilation
- ~1 week engineering effort

---

## Quick Comparison

| Option | Quality | Complexity | Time | Recommendation |
|--------|---------|------------|------|----------------|
| **No suppression** | ⭐⭐ | ✅ Simple | 0 days | **Start here** |
| **WebRTC built-in** | ⭐⭐⭐⭐ | ✅ Medium | 2-3 days | **Add in Phase 2** |
| **High-pass filter** | ⭐⭐⭐ | ✅ Simple | 1 day | Alternative to WebRTC |
| **RNNoise FFI** | ⭐⭐⭐⭐⭐ | ❌ Complex | 1 week | Future enhancement |

---

## Why Start Without It?

1. **Validate core functionality first** - Make sure auto-pause VAD works
2. **User testing in real conditions** - See if noise is actually a problem
3. **Ship faster** - Get feedback earlier
4. **Iterate based on data** - Add noise suppression if users need it

Many users record in quiet environments (home office, bedroom). For them, noise suppression is nice-to-have, not essential.

---

## Implementation Strategy

```dart
// Phase 1: Simple VAD
class LiveTranscriptionService {
  final SimpleVAD _vad;

  void _processAudioChunk(List<int> samples) {
    // Direct to VAD, no noise suppression yet
    _vad.processFrame(samples);
    if (_vad.shouldChunk()) {
      _autoSegment();
    }
  }
}

// Phase 2: Add WebRTC noise suppression (if needed)
class LiveTranscriptionService {
  final SimpleVAD _vad;
  final WebRTCNoiseFilter? _noiseFilter;  // ← Optional
  final bool _enableNoiseSuppress;  // ← Settings toggle

  Future<void> initialize() async {
    if (_enableNoiseSuppress) {
      _noiseFilter = WebRTCNoiseFilter();
      await _noiseFilter!.initialize();
    }
  }

  void _processAudioChunk(List<int> samples) {
    // Apply noise suppression if enabled
    final cleanSamples = _enableNoiseSuppress
        ? _noiseFilter!.process(samples)
        : samples;

    // Process clean audio through VAD
    _vad.processFrame(cleanSamples);
    if (_vad.shouldChunk()) {
      _autoSegment();
    }
  }
}
```

---

## Settings UI

```
┌─────────────────────────────────────┐
│ Recording Settings                  │
├─────────────────────────────────────┤
│                                     │
│ Auto-pause Detection                │
│ ◉ Enabled  ○ Disabled               │
│                                     │
│ Silence threshold: [====|===] 1.0s  │
│                                     │
│ Background Noise Suppression  🆕    │
│ ○ Enabled  ◉ Disabled               │
│   ⚠️ May increase battery usage     │
│                                     │
└─────────────────────────────────────┘
```

Start with noise suppression **OFF by default**. Users can enable if they have noise problems.

---

## Next Steps

1. ✅ **Implement simple VAD** (from main plan)
2. ✅ **Test in quiet environment**
3. ✅ **Ship to users**
4. 📊 **Gather feedback** about noise interference
5. ❓ **If needed:** Add WebRTC noise suppression

See `auto-pause-vad-implementation.md` for full technical details.

---

## Bottom Line

**You're right to ask about noise suppression!** It's a key part of RichardTate's quality. But for Parachute:

- ✅ Start without it (ship fast)
- ✅ Add it in Phase 2 if users need it
- ✅ Use WebRTC (easiest integration)
- ❌ Don't block v1 on noise suppression

The VAD will work fine for most users without noise suppression. Add it based on real-world feedback.
