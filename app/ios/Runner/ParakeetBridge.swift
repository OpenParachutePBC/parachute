import Flutter
import Foundation
import FluidAudio

/// Flutter bridge for FluidAudio Parakeet ASR
/// Provides async transcription and speaker diarization via platform channels
class ParakeetBridge {
    static let shared = ParakeetBridge()

    private var asrManager: AsrManager?
    private var models: AsrModels?
    private var isInitialized = false

    // Speaker diarization
    private var diarizerManager: OfflineDiarizerManager?
    private var isDiarizerInitialized = false

    private init() {}

    /// Initialize Parakeet models (download if needed)
    func initialize(version: AsrModelVersion = .v3, result: @escaping FlutterResult) {
        Task {
            do {
                // Download and load models
                let models = try await AsrModels.downloadAndLoad(version: version)
                self.models = models

                // Initialize ASR manager
                let config = ASRConfig.default
                let manager = AsrManager(config: config)
                try await manager.initialize(models: models)
                self.asrManager = manager
                self.isInitialized = true

                // Success
                await MainActor.run {
                    result(["status": "success", "version": version == .v3 ? "v3" : "v2"])
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "INITIALIZATION_FAILED",
                        message: "Failed to initialize Parakeet: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }

    /// Transcribe audio file (WAV format, 16kHz mono)
    func transcribe(audioPath: String, result: @escaping FlutterResult) {
        guard isInitialized, let manager = asrManager else {
            result(FlutterError(
                code: "NOT_INITIALIZED",
                message: "Parakeet not initialized. Call initialize() first.",
                details: nil
            ))
            return
        }

        Task {
            do {
                // Load audio samples from WAV file
                let samples = try await loadAudioSamples(from: audioPath)

                // Transcribe
                let transcription = try await manager.transcribe(samples)

                // Return text (Parakeet doesn't provide language detection)
                await MainActor.run {
                    result(["text": transcription.text, "language": "auto"])
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "TRANSCRIPTION_FAILED",
                        message: "Failed to transcribe audio: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }

    /// Check if models are initialized
    func isReady(result: FlutterResult) {
        result(["ready": isInitialized])
    }

    /// Get model info
    func getModelInfo(result: FlutterResult) {
        guard isInitialized else {
            result(["initialized": false])
            return
        }

        result([
            "initialized": true,
            "version": "v3", // TODO: Track actual version
            "languages": 25 // v3 supports 25 European languages
        ])
    }

    // MARK: - Speaker Diarization

    /// Initialize speaker diarization models
    func initializeDiarizer(result: @escaping FlutterResult) {
        Task {
            do {
                let config = OfflineDiarizerConfig()
                let manager = OfflineDiarizerManager(config: config)
                try await manager.prepareModels()

                self.diarizerManager = manager
                self.isDiarizerInitialized = true

                await MainActor.run {
                    result(["status": "success"])
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "DIARIZER_INIT_FAILED",
                        message: "Failed to initialize diarizer: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }

    /// Perform speaker diarization on audio file
    func diarizeAudio(audioPath: String, result: @escaping FlutterResult) {
        guard isDiarizerInitialized, let manager = diarizerManager else {
            result(FlutterError(
                code: "DIARIZER_NOT_INITIALIZED",
                message: "Diarizer not initialized. Call initializeDiarizer() first.",
                details: nil
            ))
            return
        }

        Task {
            do {
                let url = URL(fileURLWithPath: audioPath)
                let diarizationResult = try await manager.process(url)

                // Convert segments to Flutter-friendly format
                let segments = diarizationResult.segments.map { segment in
                    return [
                        "speakerId": segment.speakerId,
                        "startTimeSeconds": segment.startTimeSeconds,
                        "endTimeSeconds": segment.endTimeSeconds
                    ] as [String: Any]
                }

                await MainActor.run {
                    result(["segments": segments])
                }
            } catch {
                await MainActor.run {
                    result(FlutterError(
                        code: "DIARIZATION_FAILED",
                        message: "Failed to diarize audio: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }

    /// Check if diarizer is ready
    func isDiarizerReady(result: FlutterResult) {
        result(["ready": isDiarizerInitialized])
    }

    // MARK: - Audio Loading

    /// Load audio samples from WAV file
    /// Expects 16kHz mono PCM16 WAV file
    private func loadAudioSamples(from path: String) async throws -> [Float] {
        let url = URL(fileURLWithPath: path)

        // Read file data
        guard let data = try? Data(contentsOf: url) else {
            throw NSError(domain: "ParakeetBridge", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read audio file at: \(path)"
            ])
        }

        // Parse WAV header (skip first 44 bytes)
        let headerSize = 44
        guard data.count > headerSize else {
            throw NSError(domain: "ParakeetBridge", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid WAV file: too small"
            ])
        }

        // Extract PCM samples (int16 little-endian)
        let audioData = data.subdata(in: headerSize..<data.count)
        let sampleCount = audioData.count / 2 // 2 bytes per int16 sample

        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)

        audioData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                // Convert int16 to float [-1.0, 1.0]
                let sample = Float(int16Ptr[i]) / 32768.0
                samples.append(sample)
            }
        }

        return samples
    }
}
