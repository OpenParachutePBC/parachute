# Auto-Pause VAD Implementation Plan

**Date**: November 7, 2025
**Status**: Design Phase
**Goal**: Implement automatic pause detection using Voice Activity Detection (VAD) similar to RichardTate

---

## Overview

Based on analysis of [RichardTate](https://github.com/lucianHymer/richardtate), we can implement automatic silence detection to eliminate the need for manual pause button presses. The system will automatically segment recordings when the user stops speaking.

## How RichardTate Does It

### Core Components

**1. RNNoise Denoising (Background Noise Removal)**

- Uses **RNNoise** neural network for noise suppression
- Removes keyboards, fans, traffic, background chatter
- Operates at 48kHz internally (resamples 16kHz ↔ 48kHz)
- Processes 10ms frames (480 samples at 48kHz)
- Based on Xiph's recurrent neural network model
- Completely local processing (no cloud)

**2. Voice Activity Detection (VAD)**

- Uses **RMS (Root Mean Square) energy calculation** on audio frames
- Processes audio in 10ms frames (160 samples at 16kHz)
- Compares energy against calibrated threshold
- Tracks consecutive speech/silence frames
- Works on **denoised audio** from RNNoise

**3. Smart Chunker**

- Accumulates audio in buffer while monitoring VAD
- Triggers transcription after **1 second of continuous silence**
- Requires **minimum 1 second of actual speech** before chunking
- Prevents hallucinations by discarding mostly-silent chunks

**4. Key Parameters**

```go
SampleRate: 16000           // 16kHz audio
FrameDurationMs: 10         // 10ms frames
EnergyThreshold: 100.0      // Calibrated per microphone
SilenceThresholdMs: 1000    // 1 second silence triggers segment
MinSpeechDuration: 1000ms   // Must have 1s of speech to transcribe
```

### The Flow

```
Audio Stream (16kHz, mono)
    ↓
RNNoise Denoising (removes background noise)
    ↓
VAD (10ms frames, RMS energy calculation on clean audio)
    ↓
Smart Chunker (accumulate + monitor silence)
    ↓
Detect 1s silence → Trigger transcription
    ↓
Whisper transcribes segment (clean audio = better accuracy)
    ↓
Reset buffer, continue recording
```

**Important:** RNNoise is **not optional** in RichardTate—it's a core part of the pipeline. The noise suppression runs **before** VAD, which means:

- VAD sees clean audio (fewer false positives from background noise)
- Whisper gets clean audio (better transcription accuracy)
- Users get better experience in real-world environments

---

## Noise Suppression Options for Flutter

### Background: Why RNNoise Matters

RichardTate's audio quality comes from **RNNoise running before everything else**. Without it:

- Background sounds trigger false VAD positives
- Whisper transcribes "keyboard typing" as words
- Music/TV in background confuses the system
- Fan noise degrades transcription quality

**The Challenge:** RNNoise is a C library—Flutter integration is non-trivial.

### Flutter Noise Suppression Options

#### Option A: FFI Bridge to RNNoise (Most Accurate, Complex)

**What it is:** Bind to native RNNoise library using Dart FFI

**Pros:**

- ✅ Exact same quality as RichardTate
- ✅ Proven technology (used by WebRTC, Discord, etc.)
- ✅ Local processing, no cloud
- ✅ Real-time performance

**Cons:**

- ❌ Requires native code compilation per platform
- ❌ Complex FFI integration (~1 week effort)
- ❌ Need to bundle native libraries with app
- ❌ Platform-specific build complexity

**Implementation Sketch:**

```dart
// Would require:
// 1. Compile RNNoise for iOS/Android/macOS
// 2. Create FFI bindings
// 3. Handle sample rate conversion (16kHz ↔ 48kHz)
// 4. Manage native library lifecycle

import 'dart:ffi' as ffi;

class RNNoiseFFI {
  final ffi.DynamicLibrary _lib;
  ffi.Pointer<ffi.Void>? _state;

  RNNoiseFFI() : _lib = ffi.DynamicLibrary.open('librnnoise.so');

  // FFI function signatures
  late final _create = _lib.lookupFunction<
    ffi.Pointer<ffi.Void> Function(),
    ffi.Pointer<ffi.Void> Function()>('rnnoise_create');

  late final _process = _lib.lookupFunction<
    ffi.Float Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>),
    double Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Float>)>('rnnoise_process_frame');

  // ... implementation
}
```

#### Option B: WebRTC-Based Noise Suppression (Practical, Available Now)

**What it is:** Use Flutter's `flutter_webrtc` which includes built-in noise suppression

**Pros:**

- ✅ Already available in ecosystem
- ✅ Battle-tested (used in video calls)
- ✅ Cross-platform (iOS, Android, Web)
- ✅ Uses WebRTC's noise suppression (based on RNNoise)
- ✅ Can work without actual WebRTC connection

**Cons:**

- ❌ Heavier dependency (full WebRTC stack)
- ❌ May be overkill for audio-only use
- ❌ Less control over parameters

**Implementation Sketch:**

```dart
// Using flutter_webrtc for noise suppression
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCNoiseFilter {
  MediaRecorder? _recorder;
  MediaStream? _stream;

  Future<void> initialize() async {
    // Get audio stream with constraints
    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,  // ← WebRTC noise suppression
        'autoGainControl': true,
        'sampleRate': 16000,
      }
    });
  }

  // Process audio through WebRTC's filters
  Stream<Uint8List> getCleanAudio() {
    // WebRTC handles filtering automatically
    return _stream!.getAudioTracks()[0].captureStream();
  }
}
```

#### Option C: Simple High-Pass Filter (Lightweight, Basic)

**What it is:** Implement basic audio filtering in pure Dart

**Pros:**

- ✅ No dependencies
- ✅ Simple to implement (~50 lines)
- ✅ Removes low-frequency rumble
- ✅ Fast, real-time capable

**Cons:**

- ❌ Much less effective than RNNoise
- ❌ Only removes constant noise (fans, hum)
- ❌ Won't handle keyboards, voices, music

**Implementation:**

```dart
class SimpleAudioFilter {
  // Simple high-pass filter to remove low-frequency noise
  List<double> _prevInput = [0, 0];
  List<double> _prevOutput = [0, 0];

  List<int> applyHighPassFilter(List<int> samples, {double cutoffFreq = 80.0}) {
    const sampleRate = 16000;
    final rc = 1.0 / (2 * pi * cutoffFreq);
    final dt = 1.0 / sampleRate;
    final alpha = rc / (rc + dt);

    List<int> filtered = [];

    for (var i = 0; i < samples.length; i++) {
      final input = samples[i].toDouble();
      final output = alpha * (_prevOutput[0] + input - _prevInput[0]);

      filtered.add(output.round().clamp(-32768, 32767));

      _prevInput[0] = input;
      _prevOutput[0] = output;
    }

    return filtered;
  }
}
```

#### Option D: No Noise Suppression (Start Here)

**What it is:** Ship VAD first, add noise suppression later

**Pros:**

- ✅ Ship fast, iterate based on feedback
- ✅ Works fine in quiet environments
- ✅ Users can test core VAD functionality
- ✅ Add noise suppression in v2

**Cons:**

- ❌ Background noise causes false VAD triggers
- ❌ Transcription quality suffers in noisy environments
- ❌ May frustrate users in real-world usage

**Strategy:**

1. Ship auto-pause VAD without noise suppression
2. Gather user feedback about false triggers
3. If noise is a problem, add Option B (WebRTC)
4. If more control needed, invest in Option A (FFI)

### Recommended Approach: Phased Implementation

**Phase 1: Ship without noise suppression**

- Focus on VAD + auto-pause core functionality
- Works great in quiet home offices
- Gather real-world feedback

**Phase 2: Add WebRTC noise suppression**

- If users report noise issues, add `flutter_webrtc`
- Toggle in settings: "Background noise suppression"
- Battle-tested solution with minimal integration effort

**Phase 3: Consider RNNoise FFI (optional)**

- Only if WebRTC insufficient or users want more control
- Significant engineering investment
- Could be community contribution opportunity

---

## Implementation Options for Parachute (VAD)

### Option 1: Pure Dart RMS-Based VAD (Simple, No Dependencies)

**Pros:**

- ✅ No external dependencies
- ✅ Lightweight (~100 lines of code)
- ✅ Complete control over algorithm
- ✅ Works exactly like RichardTate
- ✅ Cross-platform (iOS, Android, macOS, Web)

**Cons:**

- ❌ Less sophisticated than ML-based VAD
- ❌ Requires per-device calibration
- ❌ May struggle with noisy environments

**Implementation:**

```dart
// lib/features/recorder/services/vad/simple_vad.dart

class SimpleVAD {
  final double energyThreshold;
  final int sampleRate;
  final int frameDurationMs;
  final int silenceThresholdMs;

  Duration _silenceDuration = Duration.zero;
  Duration _speechDuration = Duration.zero;
  bool _lastFrameWasSpeech = false;

  SimpleVAD({
    this.energyThreshold = 100.0,
    this.sampleRate = 16000,
    this.frameDurationMs = 10,
    this.silenceThresholdMs = 1000,
  });

  /// Process audio frame and return true if speech detected
  bool processFrame(List<int> samples) {
    final energy = _calculateRMSEnergy(samples);
    final isSpeech = energy > energyThreshold;

    final frameDuration = Duration(milliseconds: frameDurationMs);

    if (isSpeech) {
      _speechDuration += frameDuration;
      _silenceDuration = Duration.zero;
      _lastFrameWasSpeech = true;
    } else {
      _silenceDuration += frameDuration;
      _lastFrameWasSpeech = false;
    }

    return isSpeech;
  }

  /// Calculate RMS energy of audio samples
  double _calculateRMSEnergy(List<int> samples) {
    if (samples.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }

    return sqrt(sumSquares / samples.length);
  }

  /// Check if we should chunk based on accumulated silence
  bool shouldChunk() {
    return _silenceDuration >= Duration(milliseconds: silenceThresholdMs);
  }

  /// Check if we have enough speech to warrant transcription
  bool hasMinimumSpeech() {
    return _speechDuration >= Duration(seconds: 1);
  }

  void reset() {
    _silenceDuration = Duration.zero;
    _speechDuration = Duration.zero;
    _lastFrameWasSpeech = false;
  }
}
```

### Option 2: Silero VAD Package (ML-Based, Production Ready)

**Pros:**

- ✅ State-of-the-art ML-based detection
- ✅ Production-ready Flutter package
- ✅ Works in noisy environments
- ✅ No calibration needed
- ✅ Cross-platform (iOS, Android, Web)
- ✅ MIT licensed

**Cons:**

- ❌ Adds dependency + ONNX model (~1-2 MB)
- ❌ Slightly higher CPU usage
- ❌ More complex integration

**Package:** [`vad` on pub.dev](https://pub.dev/packages/vad)

**Implementation:**

```yaml
# pubspec.yaml
dependencies:
  vad: ^0.0.5
```

```dart
// lib/features/recorder/services/vad/silero_vad_service.dart

import 'package:vad/vad.dart';

class SileroVADService {
  final Vad _vad = Vad();
  Duration _silenceDuration = Duration.zero;
  Duration _speechDuration = Duration.zero;
  DateTime _lastFrameTime = DateTime.now();

  Future<void> initialize() async {
    await _vad.start(
      onSpeechStart: () {
        _silenceDuration = Duration.zero;
      },
      onSpeechEnd: () {
        _lastFrameTime = DateTime.now();
      },
      onRealSpeechStart: () {
        // Confirmed speech after threshold
      },
      onFrameProcessed: (frame, probability) {
        final now = DateTime.now();
        final frameDuration = now.difference(_lastFrameTime);
        _lastFrameTime = now;

        if (probability > 0.5) {
          _speechDuration += frameDuration;
          _silenceDuration = Duration.zero;
        } else {
          _silenceDuration += frameDuration;
        }
      },
    );
  }

  bool shouldChunk() {
    return _silenceDuration >= Duration(seconds: 1);
  }

  bool hasMinimumSpeech() {
    return _speechDuration >= Duration(seconds: 1);
  }

  void reset() {
    _silenceDuration = Duration.zero;
    _speechDuration = Duration.zero;
  }

  Future<void> dispose() async {
    await _vad.stop();
  }
}
```

### Option 3: Hybrid Approach (Best of Both)

Start with **Option 1 (Simple RMS VAD)** and add **Option 2 (Silero)** as an optional enhancement:

```dart
// Settings toggle
enum VADMode {
  simple,   // RMS-based (fast, lightweight)
  silero,   // ML-based (accurate, noisy environments)
}
```

**Why this is best:**

- ✅ Ship fast with simple implementation
- ✅ Add ML enhancement later based on user feedback
- ✅ Users can choose based on their needs
- ✅ Fallback if ML model fails to load

---

## Integration with Current Parachute Architecture

### Current Flow (Manual Pause)

```
User presses Record
    ↓
AudioRecorder starts → segment_1.wav
    ↓
User presses Pause
    ↓
Segment saved → Queue for transcription
    ↓
User presses Resume → segment_2.wav
    ↓
Repeat...
```

### New Flow (Auto-Pause with VAD)

```
User presses Record
    ↓
AudioRecorder starts (continuous stream)
    ↓
    ↓ [Audio frames stream to VAD]
    ↓
VAD detects 1s silence
    ↓
Auto-trigger "pause" → Save segment → Transcribe
    ↓
    ↓ [Continue recording seamlessly]
    ↓
VAD detects speech again
    ↓
Start new segment
    ↓
Repeat automatically...
```

### Modified `SimpleTranscriptionService`

```dart
class SimpleTranscriptionService {
  final WhisperLocalService _whisperService;
  final SimpleVAD _vad;  // ← Add VAD

  // New: Audio stream subscription for VAD
  StreamSubscription<List<int>>? _audioStreamSubscription;

  // Buffer for current segment
  final List<int> _currentSegmentBuffer = [];

  Future<bool> startRecording() async {
    // ... existing permission checks ...

    // Initialize VAD
    _vad.reset();

    // Start recording with stream access
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,  // ← Raw PCM for VAD
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    // Process audio through VAD
    _audioStreamSubscription = stream.listen((audioData) {
      _processAudioChunk(audioData);
    });

    _isRecording = true;
    return true;
  }

  void _processAudioChunk(List<int> audioData) {
    // Add to segment buffer
    _currentSegmentBuffer.addAll(audioData);

    // Process through VAD in 10ms frames
    const frameSize = 160;  // 10ms at 16kHz

    for (var i = 0; i < audioData.length - frameSize; i += frameSize) {
      final frame = audioData.sublist(i, i + frameSize);
      _vad.processFrame(frame);
    }

    // Check if we should auto-segment
    if (_vad.shouldChunk() && _vad.hasMinimumSpeech()) {
      _autoSegment();
    }
  }

  Future<void> _autoSegment() async {
    debugPrint('[AutoVAD] Detected 1s silence, auto-segmenting...');

    // Save current buffer to segment file
    final segmentFile = await _saveSegmentBuffer();

    // Queue for transcription (existing logic)
    _queueSegmentForProcessing(segmentFile);

    // Reset for next segment
    _currentSegmentBuffer.clear();
    _vad.reset();
    _nextSegmentIndex++;

    // Emit event (for UI feedback)
    _segmentStreamController.add(TranscriptionSegment(
      index: _nextSegmentIndex - 1,
      text: '',  // Will be filled by transcription
      status: TranscriptionSegmentStatus.processing,
      timestamp: DateTime.now(),
    ));
  }

  Future<String> _saveSegmentBuffer() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final segmentPath = path.join(
      _tempDirectory!,
      'segment_${_nextSegmentIndex}_$timestamp.wav',
    );

    // Convert PCM buffer to WAV file
    final wavBytes = _convertPCMtoWAV(_currentSegmentBuffer);
    await File(segmentPath).writeAsBytes(wavBytes);

    _segmentAudioFiles.add(segmentPath);
    return segmentPath;
  }
}
```

---

## UI/UX Considerations

### Visual Feedback

**During Recording:**

- Show live VAD status: "🟢 Speaking" / "🔵 Listening for speech" / "⏸️ Silence detected"
- Real-time silence counter: "Silence: 0.3s / 1.0s"
- Live segment counter: "Segment 3 (auto)"

**Settings Screen:**

- Toggle: "Auto-pause on silence" (default: ON)
- Slider: "Silence threshold" (0.5s - 3s, default: 1s)
- Toggle: "Show VAD indicators" (for debugging)
- Button: "Calibrate microphone" (for RMS-based VAD)

### Calibration Flow (for Option 1)

```
┌──────────────────────────────┐
│ Microphone Calibration       │
├──────────────────────────────┤
│                              │
│ Step 1: Background Noise     │
│ "Stay silent for 5 seconds"  │
│ [████████░░] 80%             │
│                              │
│ Step 2: Speech Level         │
│ "Read this sentence aloud:"  │
│ "The quick brown fox..."     │
│ [███░░░░░░░] 30%             │
│                              │
│ ✓ Calibrated!                │
│ Threshold: 145.2             │
└──────────────────────────────┘
```

---

## Implementation Phases

### Phase 1: Proof of Concept (1-2 days)

- [ ] Implement `SimpleVAD` class (RMS-based)
- [ ] Add unit tests for VAD logic
- [ ] Create calibration screen UI
- [ ] Test with real audio recordings

### Phase 2: Integration (2-3 days)

- [ ] Modify `SimpleTranscriptionService` to use VAD
- [ ] Add PCM audio streaming
- [ ] Implement auto-segmentation logic
- [ ] Add settings toggle (manual vs auto-pause)
- [ ] Test with various speaking patterns

### Phase 3: Polish (1-2 days)

- [ ] Add visual VAD indicators
- [ ] Implement silence counter UI
- [ ] Add segment visualization
- [ ] Performance optimization
- [ ] Edge case handling (very short/long segments)

### Phase 4: Optional ML Enhancement (2-3 days)

- [ ] Integrate `vad` package (Silero)
- [ ] Add VAD mode selector in settings
- [ ] Compare accuracy between simple vs ML
- [ ] Fallback handling

---

## Technical Decisions

### Recommended Approach: Start with Option 3 (Hybrid)

**Rationale:**

1. **Ship fast**: Simple RMS VAD is ~100 lines, no dependencies
2. **Proven approach**: Exactly what RichardTate uses successfully
3. **Future-proof**: Easy to add ML enhancement later
4. **User choice**: Power users can enable advanced features

### Audio Format

- **Sample Rate**: 16kHz (matches Whisper requirement)
- **Channels**: Mono
- **Format**: PCM16 for VAD processing, save as WAV for storage
- **Frame Size**: 10ms (160 samples)

### Performance Considerations

- VAD processing is extremely lightweight (< 1ms per frame)
- Buffer management: Keep last 30s in memory, flush older data
- Transcription: Queue-based async processing (already implemented)
- Battery: Minimal impact vs continuous recording

---

## Testing Strategy

### Unit Tests

```dart
test('VAD detects speech above threshold', () {
  final vad = SimpleVAD(energyThreshold: 100.0);
  final speechFrame = List.filled(160, 500); // High energy
  expect(vad.processFrame(speechFrame), true);
});

test('VAD detects silence below threshold', () {
  final vad = SimpleVAD(energyThreshold: 100.0);
  final silenceFrame = List.filled(160, 10); // Low energy
  expect(vad.processFrame(silenceFrame), false);
});

test('Chunking triggers after 1s silence', () {
  final vad = SimpleVAD(silenceThresholdMs: 1000);

  // Process 100 frames (1 second) of silence
  for (var i = 0; i < 100; i++) {
    vad.processFrame(List.filled(160, 10));
  }

  expect(vad.shouldChunk(), true);
});
```

### Integration Tests

- Record 30s with pauses → Verify correct segmentation
- Rapid speech → Ensure no premature chunking
- Long silence → Verify single chunk after 1s
- Noisy environment → Test threshold calibration

---

## Open Questions

1. **Should we keep the manual pause button?**
   - Recommendation: Yes, as fallback and for precise control

2. **What happens if user stops speaking mid-sentence?**
   - After 1s silence, auto-segment
   - Next speech continues as new segment
   - User can manually combine in post-recording screen

3. **Should minimum speech duration be configurable?**
   - Start with fixed 1s (like RichardTate)
   - Add to settings if users request it

4. **How to handle background noise (TV, music)?**
   - Simple VAD: Requires calibration per environment
   - Silero VAD: More robust, but may still trigger on loud sounds
   - Future: Add RNNoise for denoising (like RichardTate)

---

## References

- **RichardTate**: https://github.com/lucianHymer/richardtate
  - `server/internal/transcription/vad.go` - RMS VAD implementation
  - `server/internal/transcription/chunker.go` - Smart chunking logic
- **Flutter VAD Package**: https://pub.dev/packages/vad
- **Silero VAD**: https://github.com/snakers4/silero-vad

---

## Next Steps

Ready to proceed? Here's the recommended order:

1. **Review this plan** - Any questions or concerns?
2. **Start with Phase 1** - Implement simple RMS VAD
3. **Test with your voice** - Calibrate and validate
4. **Iterate on thresholds** - Find optimal values
5. **Phase 2 integration** - Wire up auto-segmentation
6. **User testing** - Gather feedback
7. **Consider ML upgrade** - If simple VAD isn't sufficient

**Estimated Total Time**: 1-2 weeks for full implementation with polish

---

**Last Updated**: November 7, 2025
**Author**: Claude (via analysis of RichardTate)
