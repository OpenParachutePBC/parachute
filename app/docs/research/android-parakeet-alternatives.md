# Android Alternatives for Parakeet v3 Transcription

**Date**: November 14, 2025
**Status**: Research Complete - Recommended Solution Identified

## Executive Summary

For Android devices, we cannot use FluidAudio (iOS/macOS only). After extensive research, the **recommended solution** is to use **sherpa-onnx** with Parakeet TDT models exported to ONNX format.

### Recommended Approach: sherpa-onnx

**sherpa-onnx** is a cross-platform speech recognition framework that:
- ✅ Supports Parakeet TDT models (v2 confirmed, v3 exportable)
- ✅ Has native Flutter package (`sherpa_onnx` on pub.dev)
- ✅ Supports Android, iOS, macOS, Windows, Linux
- ✅ Runs 100% offline (no internet required)
- ✅ Uses ONNX Runtime for fast inference
- ✅ Active development and community

## Detailed Analysis

### Option 1: sherpa-onnx (Recommended) ⭐

**Project**: https://github.com/k2-fsa/sherpa-onnx
**Flutter Package**: https://pub.dev/packages/sherpa_onnx
**License**: Apache 2.0

#### Pros
- **Native Flutter support** - Official `sherpa_onnx` package on pub.dev
- **Parakeet model support** - Confirmed support for `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8`
- **Cross-platform** - Single API works on Android, iOS, macOS, Windows, Linux
- **Offline-first** - All processing happens locally
- **Production-ready** - Used in multiple commercial applications
- **Active maintenance** - Regular updates and active Discord community
- **Comprehensive features** - ASR, TTS, VAD, speaker diarization, etc.
- **Optimized** - INT8 quantized models available for mobile devices
- **Pre-built APKs** - Easy to test on Android before integration

#### Cons
- Requires converting Parakeet v3 to ONNX format (if not already available)
- Slightly larger dependency (~20-30MB for library + models)
- Different API from current Whisper implementation (needs adapter layer)

#### Model Availability

**Currently Available:**
- `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` (English)
- Parakeet v2 models in ONNX format

**Parakeet v3 Status:**
- Not yet pre-converted to ONNX on sherpa-onnx
- Can be exported using NVIDIA NeMo toolkit
- Export process: NeMo → ONNX → sherpa-onnx compatible format

#### Integration Plan

1. **Add dependency** to `pubspec.yaml`:
   ```yaml
   dependencies:
     sherpa_onnx: ^1.12.12
   ```

2. **Download Parakeet ONNX model** (v2 or exported v3):
   - Place in `assets/models/parakeet/`
   - INT8 quantized version recommended for mobile (~200MB vs ~500MB)

3. **Create Android adapter** in `transcription_service_adapter.dart`:
   - iOS/macOS: Use FluidAudio (current implementation)
   - Android: Use sherpa-onnx with Parakeet ONNX model
   - Same API interface for both platforms

4. **Initialize on app startup**:
   - Load ONNX model from assets
   - Initialize sherpa-onnx recognizer
   - Ready for transcription

#### Code Example (Android Path)

```dart
import 'package:sherpa_onnx/sherpa_onnx.dart';

class SherpaOnnxService {
  OfflineRecognizer? _recognizer;

  Future<void> initialize() async {
    final modelConfig = OfflineTransducerModelConfig(
      encoder: 'assets/models/parakeet/encoder.onnx',
      decoder: 'assets/models/parakeet/decoder.onnx',
      joiner: 'assets/models/parakeet/joiner.onnx',
    );

    final config = OfflineRecognizerConfig(
      model: modelConfig,
      sampleRate: 16000,
      featureDim: 80,
    );

    _recognizer = await OfflineRecognizer.create(config);
  }

  Future<String> transcribe(String audioPath) async {
    final stream = _recognizer!.createStream();
    // Load audio samples
    final samples = await loadAudio(audioPath);
    stream.acceptWaveform(samples, 16000);

    // Decode
    _recognizer!.decode(stream);
    final result = _recognizer!.getResult(stream);
    stream.free();

    return result.text;
  }
}
```

### Option 2: ONNX Runtime Direct

**Project**: https://onnxruntime.ai/
**Status**: Possible but requires more manual work

#### Pros
- Lightweight (only ONNX Runtime dependency)
- Full control over model loading and inference
- No additional framework overhead

#### Cons
- No pre-built Parakeet TDT pipeline
- Must implement preprocessing (mel spectrogram, etc.)
- Must implement TDT decoding logic
- More complex integration
- Platform-specific code needed for Android

**Verdict**: Not recommended - sherpa-onnx already provides this with proper integration.

### Option 3: NVIDIA NeMo Direct

**Project**: https://github.com/NVIDIA/NeMo
**Status**: Not suitable for mobile

#### Pros
- Official Parakeet implementation
- Best quality and latest models

#### Cons
- ❌ Python-only (no Flutter/Dart support)
- ❌ Large dependencies (PyTorch, etc.)
- ❌ Not designed for mobile devices
- ❌ Requires significant RAM and compute

**Verdict**: Not viable for Android mobile app.

### Option 4: Python Backend Server

**Approach**: Run NeMo/Python backend, Android calls via HTTP

#### Pros
- Can use official NeMo implementation
- Easy to update models
- Offloads compute from mobile device

#### Cons
- ❌ Not offline-first (requires internet)
- ❌ Latency issues
- ❌ Server infrastructure costs
- ❌ Privacy concerns (audio sent to server)
- ❌ Goes against Parachute's local-first philosophy

**Verdict**: Conflicts with project principles.

## Recommended Implementation Plan

### Phase 1: Proof of Concept (1-2 days)
1. ✅ Research sherpa-onnx (COMPLETE)
2. Test sherpa-onnx Flutter package on Android
3. Download Parakeet v2 ONNX model from sherpa-onnx
4. Create simple Android test app with sherpa-onnx
5. Verify transcription quality and speed

### Phase 2: Export Parakeet v3 to ONNX (2-3 days)
1. Set up NVIDIA NeMo environment
2. Load Parakeet v3 model from HuggingFace
3. Export to ONNX format using NeMo's export tools
4. Quantize to INT8 for mobile optimization
5. Test exported model with sherpa-onnx

### Phase 3: Integration (2-3 days)
1. Add sherpa-onnx to Flutter dependencies
2. Bundle Parakeet v3 ONNX model in app assets
3. Update `TranscriptionServiceAdapter`:
   - iOS/macOS: FluidAudio (existing)
   - Android: sherpa-onnx (new)
4. Test on real Android devices
5. Update onboarding for Android (already platform-adaptive)

### Phase 4: Optimization (1-2 days)
1. Profile performance on Android devices
2. Tune sherpa-onnx parameters (num_threads, etc.)
3. Consider model quantization levels (INT8 vs FP16)
4. Add progress callbacks during transcription
5. Handle edge cases (long audio, errors, etc.)

## Expected Performance

Based on sherpa-onnx benchmarks:

- **Parakeet v2 INT8**: ~100-200x real-time on mid-range Android (RTFx)
- **Parakeet v3 INT8**: Expected similar or better (smaller, optimized)
- **Latency**: <1 second for 1 minute of audio
- **Model Size**: ~200-300MB (INT8 quantized)
- **RAM Usage**: ~500MB during inference

## Fallback Strategy

If Parakeet v3 ONNX export proves difficult:

1. **Option A**: Use Parakeet v2 ONNX (already available)
   - Still much better than Whisper Base
   - Multilingual support via v2 multilingual variant

2. **Option B**: Keep Whisper on Android temporarily
   - iOS/macOS gets Parakeet v3 (done)
   - Android continues with Whisper
   - Upgrade Android to Parakeet later when ONNX export is ready

## References

- **sherpa-onnx GitHub**: https://github.com/k2-fsa/sherpa-onnx
- **sherpa-onnx Flutter**: https://pub.dev/packages/sherpa_onnx
- **sherpa-onnx Docs**: https://k2-fsa.github.io/sherpa/onnx/index.html
- **Parakeet v3 HuggingFace**: https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
- **NeMo Export Guide**: https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/nlp/nemo_megatron/gpt/export.html
- **onnx-asr Python Package**: https://pypi.org/project/onnx-asr/ (supports Parakeet TDT)

## Next Steps

1. **Immediate**: Test sherpa-onnx Flutter package on Android device
2. **Short-term**: Export Parakeet v3 to ONNX or use v2 as interim
3. **Medium-term**: Integrate sherpa-onnx into `TranscriptionServiceAdapter`
4. **Long-term**: Monitor sherpa-onnx for pre-built Parakeet v3 ONNX models

## Conclusion

**sherpa-onnx is the clear winner** for Android Parakeet transcription:
- Native Flutter support
- Proven Parakeet TDT compatibility
- Cross-platform (can replace iOS/macOS FluidAudio if desired)
- Production-ready with active community
- Maintains offline-first philosophy

The main task is exporting Parakeet v3 to ONNX format, which is well-documented in the NVIDIA NeMo toolkit. Alternatively, we can use pre-converted Parakeet v2 ONNX models as an interim solution.
