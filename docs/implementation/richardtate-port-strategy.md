# RichardTate → Parachute Port Strategy

**Date**: November 7, 2025
**Goal**: Maximum code reuse from RichardTate for production-quality auto-pause with noise suppression

---

## Philosophy: Port, Don't Rewrite

RichardTate has **1,437 lines** of battle-tested audio processing code. Instead of reimplementing:
- **Port the algorithms directly** (Dart is similar to Go)
- **Use FFI for native libraries** (RNNoise C bindings)
- **Mirror the exact architecture** (proven pipeline design)

---

## Code Analysis: What's in RichardTate

### Core Audio Processing (All Portable!)

| File | Lines | Complexity | Port Strategy |
|------|-------|------------|---------------|
| `vad.go` | 148 | ⭐ Simple | **Direct port to Dart** |
| `chunker.go` | 225 | ⭐⭐ Medium | **Direct port to Dart** |
| `resample.go` | 119 | ⭐ Simple | **Direct port to Dart** |
| `pipeline.go` | 318 | ⭐⭐ Medium | **Adapt for Flutter** |
| `rnnoise_real.go` | 228 | ⭐⭐⭐ Complex | **FFI bindings** |
| `whisper.go` | 197 | ⭐⭐⭐ Complex | **Already have** |

**Total portable code: ~1,040 lines** (VAD + Chunker + Resample + Pipeline)

### What We Already Have

✅ **Whisper transcription** - Local Whisper service working
✅ **Audio recording** - Flutter `record` package
✅ **Segment management** - `SimpleTranscriptionService`
✅ **File handling** - WAV generation, storage

### What We Need to Port

🎯 **RNNoise** - Noise suppression (FFI)
🎯 **VAD** - Voice activity detection (direct port)
🎯 **Chunker** - Smart segmentation (direct port)
🎯 **Resample** - 16kHz ↔ 48kHz (direct port)
🎯 **Pipeline** - Orchestration (adapt)

---

## Implementation Strategy

### Phase 1: Direct Dart Ports (No Dependencies)

Port pure-algorithm code directly from Go to Dart. These files have **zero external dependencies**.

#### 1.1 VAD (Voice Activity Detection)

**Source**: `server/internal/transcription/vad.go` (148 lines)

**Port to**: `app/lib/features/recorder/services/vad/simple_vad.dart`

**What it does**:
- RMS energy calculation
- Speech/silence detection
- Frame-by-frame processing (10ms chunks)
- Tracks consecutive silence for chunking trigger

**Port difficulty**: ⭐ **EASY** - Pure math, no dependencies

**Code mapping**:
```go
// Go (RichardTate)
func (v *VoiceActivityDetector) calculateEnergy(samples []int16) float64 {
    var sumSquares float64
    for _, sample := range samples {
        val := float64(sample)
        sumSquares += val * val
    }
    return math.Sqrt(sumSquares / float64(len(samples)))
}
```

```dart
// Dart (Parachute) - IDENTICAL LOGIC
double _calculateEnergy(List<int> samples) {
  if (samples.isEmpty) return 0.0;

  double sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }

  return sqrt(sumSquares / samples.length);
}
```

#### 1.2 Resampler (16kHz ↔ 48kHz)

**Source**: `server/internal/transcription/resample.go` (119 lines)

**Port to**: `app/lib/features/recorder/services/audio_processing/resampler.dart`

**What it does**:
- Upsample 16kHz → 48kHz (linear interpolation)
- Downsample 48kHz → 16kHz (averaging for anti-aliasing)
- Both int16 and float32 variants

**Port difficulty**: ⭐ **EASY** - Pure math, no dependencies

**Code mapping**:
```go
// Go
func Upsample16to48(input []int16) []int16 {
    output := make([]int16, len(input)*3)
    for i := 0; i < len(input); i++ {
        baseIdx := i * 3
        if i < len(input)-1 {
            curr := input[i]
            next := input[i+1]
            diff := next - curr
            output[baseIdx] = curr
            output[baseIdx+1] = curr + diff/3
            output[baseIdx+2] = curr + 2*diff/3
        } else {
            output[baseIdx] = input[i]
            output[baseIdx+1] = input[i]
            output[baseIdx+2] = input[i]
        }
    }
    return output
}
```

```dart
// Dart - IDENTICAL ALGORITHM
List<int> upsample16to48(List<int> input) {
  final output = List<int>.filled(input.length * 3, 0);

  for (var i = 0; i < input.length; i++) {
    final baseIdx = i * 3;

    if (i < input.length - 1) {
      final curr = input[i];
      final next = input[i + 1];
      final diff = next - curr;

      output[baseIdx] = curr;
      output[baseIdx + 1] = curr + diff ~/ 3;
      output[baseIdx + 2] = curr + 2 * diff ~/ 3;
    } else {
      output[baseIdx] = input[i];
      output[baseIdx + 1] = input[i];
      output[baseIdx + 2] = input[i];
    }
  }

  return output;
}
```

#### 1.3 Smart Chunker

**Source**: `server/internal/transcription/chunker.go` (225 lines)

**Port to**: `app/lib/features/recorder/services/vad/smart_chunker.dart`

**What it does**:
- Accumulates audio samples in buffer
- Monitors VAD for silence detection
- Triggers callback when 1s silence detected
- Requires minimum 1s of speech before chunking
- Handles safety limits (max chunk duration)

**Port difficulty**: ⭐⭐ **MEDIUM** - Uses VAD, callback pattern

**Key classes to port**:
```dart
class SmartChunkerConfig {
  final int sampleRate;
  final Duration silenceThreshold;
  final Duration minChunkDuration;
  final Duration maxChunkDuration;
  final double vadEnergyThreshold;
  final Function(List<int> chunk) onChunkReady;

  // ... same as Go
}

class SmartChunker {
  final SimpleVAD _vad;
  final List<int> _buffer;

  void processSamples(List<int> samples) {
    // Port Go logic line-by-line
  }

  void _checkAndChunk() {
    // Identical to RichardTate
  }
}
```

---

### Phase 2: RNNoise FFI Bindings

**Source**: Uses `github.com/xaionaro-go/audio` which wraps C RNNoise

**Challenge**: RNNoise is C code, not Dart

**Solution**: Create FFI bindings to native RNNoise library

#### 2.1 Build Native RNNoise Libraries

**For each platform**, compile RNNoise as shared library:

```bash
# iOS (arm64)
git clone https://github.com/xiph/rnnoise
cd rnnoise
./autogen.sh
./configure --host=arm-apple-darwin CFLAGS="-arch arm64 -mios-version-min=12.0"
make
# Output: librnnoise.dylib

# Android (arm64-v8a, armeabi-v7a, x86_64, x86)
./configure --host=aarch64-linux-android CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang
make
# Output: librnnoise.so

# macOS (arm64 + x86_64)
./configure CFLAGS="-arch arm64 -arch x86_64"
make
# Output: librnnoise.dylib
```

**Include in app**:
```
app/
  ios/
    Frameworks/
      librnnoise.dylib  # Bundle with iOS app
  android/
    src/main/jniLibs/
      arm64-v8a/librnnoise.so
      armeabi-v7a/librnnoise.so
  macos/
    Frameworks/
      librnnoise.dylib
```

#### 2.2 Create Dart FFI Bindings

**File**: `app/lib/features/recorder/services/audio_processing/rnnoise_ffi.dart`

```dart
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// RNNoise C API signatures
typedef RNNoiseStateNative = ffi.Pointer<ffi.Void>;
typedef RNNoiseCreateNative = RNNoiseStateNative Function();
typedef RNNoiseCreateDart = RNNoiseStateNative Function();

typedef RNNoiseProcessFrameNative = ffi.Float Function(
  RNNoiseStateNative state,
  ffi.Pointer<ffi.Float> frame,
);
typedef RNNoiseProcessFrameDart = double Function(
  RNNoiseStateNative state,
  ffi.Pointer<ffi.Float> frame,
);

typedef RNNoiseDestroyNative = ffi.Void Function(RNNoiseStateNative state);
typedef RNNoiseDestroyDart = void Function(RNNoiseStateNative state);

class RNNoiseFFI {
  late final ffi.DynamicLibrary _lib;
  late final RNNoiseCreateDart _create;
  late final RNNoiseProcessFrameDart _processFrame;
  late final RNNoiseDestroyDart _destroy;

  RNNoiseStateNative? _state;

  RNNoiseFFI() {
    // Load platform-specific library
    if (Platform.isIOS || Platform.isMacOS) {
      _lib = ffi.DynamicLibrary.open('librnnoise.dylib');
    } else if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('librnnoise.so');
    } else {
      throw UnsupportedError('Platform not supported');
    }

    // Bind functions
    _create = _lib
        .lookup<ffi.NativeFunction<RNNoiseCreateNative>>('rnnoise_create')
        .asFunction();

    _processFrame = _lib
        .lookup<ffi.NativeFunction<RNNoiseProcessFrameNative>>('rnnoise_process_frame')
        .asFunction();

    _destroy = _lib
        .lookup<ffi.NativeFunction<RNNoiseDestroyNative>>('rnnoise_destroy')
        .asFunction();
  }

  void initialize() {
    _state = _create();
  }

  /// Process 480 samples (10ms at 48kHz) of float32 audio
  /// Returns voice activity probability
  double processFrame(List<double> samples) {
    assert(samples.length == 480, 'RNNoise requires 480 samples (10ms @ 48kHz)');

    // Allocate native memory
    final ptr = malloc.allocate<ffi.Float>(samples.length * ffi.sizeOf<ffi.Float>());

    // Copy samples to native memory
    for (var i = 0; i < samples.length; i++) {
      ptr[i] = samples[i];
    }

    // Process frame
    final vadProb = _processFrame(_state!, ptr);

    // Copy back denoised samples
    final denoised = List<double>.generate(
      samples.length,
      (i) => ptr[i],
    );

    // Free memory
    malloc.free(ptr);

    return vadProb;
  }

  void dispose() {
    if (_state != null) {
      _destroy(_state!);
      _state = null;
    }
  }
}
```

#### 2.3 Wrapper Service (Match RichardTate API)

**File**: `app/lib/features/recorder/services/audio_processing/rnnoise_processor.dart`

```dart
import 'rnnoise_ffi.dart';
import 'resampler.dart';

/// High-level RNNoise processor that matches RichardTate's API
class RNNoiseProcessor {
  final RNNoiseFFI _ffi;
  final Resampler _resampler;
  final List<int> _buffer16k = [];

  static const int frameSize16k = 160; // 10ms at 16kHz
  static const int frameSize48k = 480; // 10ms at 48kHz

  RNNoiseProcessor()
      : _ffi = RNNoiseFFI(),
        _resampler = Resampler();

  Future<void> initialize() async {
    _ffi.initialize();
  }

  /// Process 16kHz int16 samples, return denoised 16kHz int16 samples
  /// This API matches RichardTate's ProcessChunk exactly!
  List<int> processChunk(List<int> samples) {
    // Add to buffer
    _buffer16k.addAll(samples);

    final List<int> output = [];

    // Process complete 10ms frames
    while (_buffer16k.length >= frameSize16k) {
      // Extract frame
      final frame16k = _buffer16k.sublist(0, frameSize16k);
      _buffer16k.removeRange(0, frameSize16k);

      // Upsample to 48kHz (RNNoise operates at 48kHz)
      final frame48k = _resampler.upsample16to48(frame16k);

      // Convert to float32 [-1.0, 1.0]
      final frame48kFloat = frame48k.map((s) => s / 32768.0).toList();

      // Process through RNNoise
      _ffi.processFrame(frame48kFloat);
      // (frame48kFloat now contains denoised audio)

      // Convert back to int16
      final denoised48k = frame48kFloat
          .map((f) => (f * 32767.0).round().clamp(-32768, 32767))
          .toList();

      // Downsample back to 16kHz
      final denoised16k = _resampler.downsample48to16(denoised48k);

      output.addAll(denoised16k);
    }

    return output;
  }

  void dispose() {
    _ffi.dispose();
  }
}
```

---

### Phase 3: Pipeline Integration

**Source**: Adapt `pipeline.go` architecture

**File**: `app/lib/features/recorder/services/live_transcription_service_v3.dart`

```dart
/// Complete audio processing pipeline matching RichardTate
/// Flow: Raw PCM → RNNoise → VAD → Chunker → Whisper
class RichardTatePipeline {
  final RNNoiseProcessor _rnnoise;
  final SimpleVAD _vad;
  final SmartChunker _chunker;
  final WhisperLocalService _whisper;

  RichardTatePipeline({
    required WhisperLocalService whisper,
  })  : _whisper = whisper,
        _rnnoise = RNNoiseProcessor(),
        _vad = SimpleVAD(
          energyThreshold: 100.0,
          sampleRate: 16000,
          frameDurationMs: 10,
          silenceThresholdMs: 1000,
        ),
        _chunker = SmartChunker(
          config: SmartChunkerConfig(
            sampleRate: 16000,
            silenceThreshold: Duration(seconds: 1),
            minChunkDuration: Duration(milliseconds: 500),
            maxChunkDuration: Duration(seconds: 30),
            vadEnergyThreshold: 100.0,
            onChunkReady: _transcribeChunk,
          ),
        );

  Future<void> initialize() async {
    await _rnnoise.initialize();
  }

  /// Process incoming audio chunk through full pipeline
  /// Matches RichardTate's ProcessChunk exactly!
  void processChunk(List<int> audioSamples) {
    // Step 1: RNNoise denoising
    final denoised = _rnnoise.processChunk(audioSamples);

    // Step 2: Smart chunker (includes VAD internally)
    _chunker.processSamples(denoised);

    // Chunker will call onChunkReady when silence detected
  }

  void _transcribeChunk(List<int> chunk) async {
    // Convert int16 to float32 for Whisper
    final floatSamples = chunk.map((s) => s / 32768.0).toList();

    // Transcribe
    final result = await _whisper.transcribe(floatSamples);

    // Emit result
    // (integrate with existing segment system)
  }

  void dispose() {
    _rnnoise.dispose();
  }
}
```

---

## File Structure

```
app/lib/features/recorder/services/
  audio_processing/
    rnnoise_ffi.dart              # FFI bindings (Phase 2)
    rnnoise_processor.dart        # High-level wrapper (Phase 2)
    resampler.dart                # Port of resample.go (Phase 1)

  vad/
    simple_vad.dart               # Port of vad.go (Phase 1)
    smart_chunker.dart            # Port of chunker.go (Phase 1)

  live_transcription_service_v3.dart  # Pipeline (Phase 3)
```

---

## Implementation Timeline

### Week 1: Pure Dart Ports (No dependencies)

**Days 1-2: VAD + Resampler**
- [ ] Port `vad.go` → `simple_vad.dart`
- [ ] Port `resample.go` → `resampler.dart`
- [ ] Unit tests (verify against RichardTate output)

**Days 3-4: Smart Chunker**
- [ ] Port `chunker.go` → `smart_chunker.dart`
- [ ] Integration tests with VAD
- [ ] Test with real audio samples

**Day 5: Testing & Validation**
- [ ] Record test audio in RichardTate
- [ ] Process same audio in Parachute
- [ ] Compare chunking behavior
- [ ] Tune thresholds if needed

**Deliverable**: ✅ Auto-pause working WITHOUT noise suppression

### Week 2: RNNoise Integration

**Days 1-2: Build Native Libraries**
- [ ] Compile RNNoise for iOS (arm64)
- [ ] Compile RNNoise for Android (arm64-v8a, armeabi-v7a)
- [ ] Compile RNNoise for macOS (universal binary)
- [ ] Bundle libraries in app

**Days 3-4: FFI Bindings**
- [ ] Create `rnnoise_ffi.dart`
- [ ] Create `rnnoise_processor.dart`
- [ ] Test on real device (iOS/Android)
- [ ] Verify no memory leaks

**Day 5: Pipeline Integration**
- [ ] Create `RichardTatePipeline` class
- [ ] Wire up: RNNoise → VAD → Chunker → Whisper
- [ ] End-to-end testing

**Deliverable**: ✅ Complete RichardTate-quality pipeline in Flutter

### Week 3: Polish & Settings

**Days 1-2: UI Integration**
- [ ] Settings toggle: "Background noise suppression"
- [ ] VAD status indicators
- [ ] Silence countdown display
- [ ] Calibration screen (for VAD threshold)

**Days 3-4: Edge Cases**
- [ ] Handle very short/long segments
- [ ] Battery optimization
- [ ] Background processing
- [ ] Error recovery

**Day 5: User Testing**
- [ ] Test in quiet environment
- [ ] Test with keyboard noise
- [ ] Test with background TV
- [ ] Test with multiple speakers

**Deliverable**: ✅ Production-ready auto-pause with noise suppression

---

## Code Reuse Summary

| Component | Source | Lines | Strategy | Effort |
|-----------|--------|-------|----------|---------|
| **VAD** | vad.go | 148 | Direct port | 1 day |
| **Resampler** | resample.go | 119 | Direct port | 1 day |
| **Chunker** | chunker.go | 225 | Direct port | 2 days |
| **RNNoise** | C library | - | FFI bindings | 3 days |
| **Pipeline** | pipeline.go | 318 | Adapt | 2 days |
| **Integration** | - | - | Wire up | 2 days |
| **Polish** | - | - | UI/UX | 3 days |

**Total**: ~14 days (3 weeks with buffer)

---

## Testing Strategy

### Unit Tests (Match RichardTate Output)

```dart
test('VAD energy calculation matches RichardTate', () {
  final vad = SimpleVAD();

  // Use same test samples as RichardTate
  final samples = [100, 200, -150, 300, -250];

  // Expected RMS: sqrt((100^2 + 200^2 + 150^2 + 300^2 + 250^2) / 5)
  // = sqrt(192500 / 5) = sqrt(38500) ≈ 196.21

  final energy = vad.calculateEnergy(samples);
  expect(energy, closeTo(196.21, 0.01));
});

test('Resampler 16→48→16 roundtrip is lossless', () {
  final resampler = Resampler();

  final original = List.generate(160, (i) => (i * 100) % 32767);

  final upsampled = resampler.upsample16to48(original);
  expect(upsampled.length, 480);

  final downsampled = resampler.downsample48to16(upsampled);
  expect(downsampled.length, 160);

  // Should be very close to original (allow small rounding error)
  for (var i = 0; i < original.length; i++) {
    expect(downsampled[i], closeTo(original[i], 10));
  }
});
```

### Integration Tests

```dart
test('Chunker auto-segments after 1s silence', () async {
  var chunkCount = 0;

  final chunker = SmartChunker(
    config: SmartChunkerConfig(
      sampleRate: 16000,
      silenceThreshold: Duration(seconds: 1),
      onChunkReady: (_) => chunkCount++,
    ),
  );

  // Send 1s of speech (high energy)
  for (var i = 0; i < 100; i++) {
    final frame = List.filled(160, 1000); // Loud audio
    chunker.processSamples(frame);
  }

  expect(chunkCount, 0); // No chunk yet

  // Send 1s of silence (low energy)
  for (var i = 0; i < 100; i++) {
    final frame = List.filled(160, 10); // Quiet audio
    chunker.processSamples(frame);
  }

  // Should have triggered chunk after 1s silence
  await Future.delayed(Duration(milliseconds: 100));
  expect(chunkCount, 1);
});
```

---

## Advantages of This Approach

✅ **Proven algorithms** - RichardTate's code is battle-tested
✅ **Maximum reuse** - Port ~1,000 lines directly
✅ **Same quality** - Identical RNNoise + VAD behavior
✅ **Phased delivery** - Ship VAD first, add RNNoise later
✅ **Future-proof** - Easy to sync improvements from RichardTate
✅ **Community** - Can contribute back improvements

---

## License Considerations

- **RichardTate**: MIT License ✅ (can reuse)
- **RNNoise**: BSD-3-Clause ✅ (can bundle)
- **Parachute**: (check your license)

All compatible for commercial use.

---

## Next Steps

1. ✅ **Review this plan** - Any questions or concerns?
2. 🎯 **Start Week 1, Day 1** - Port VAD to Dart
3. 🧪 **Test against RichardTate** - Ensure identical behavior
4. 📦 **Ship incrementally** - VAD first, RNNoise when ready

Ready to start porting?
