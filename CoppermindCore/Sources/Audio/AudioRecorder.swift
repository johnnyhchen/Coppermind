// AudioRecorder.swift — Manages AVAudioEngine-based recording
// CoppermindCore

import AVFoundation
import Foundation
import Observation

/// Manages audio recording sessions using AVAudioEngine.
/// Captures 16 kHz mono PCM from the input node and encodes to AAC .m4a on save.
/// Publishes real-time level metering and duration via @Observable.
@Observable
public final class AudioRecorder: @unchecked Sendable {

    // MARK: - State

    /// Recording session state.
    public enum State: Sendable, Equatable {
        case idle
        case preparing
        case recording(duration: TimeInterval)
        case paused(duration: TimeInterval)
        case stopping
        case failed(String)
    }

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let sampleRate: Double
        public let channels: Int
        public let bitDepth: Int
        public let fileFormat: AudioFileFormat
        public let maxDuration: TimeInterval

        public init(
            sampleRate: Double = 16000,
            channels: Int = 1,
            bitDepth: Int = 16,
            fileFormat: AudioFileFormat = .m4a,
            maxDuration: TimeInterval = 600
        ) {
            self.sampleRate = sampleRate
            self.channels = channels
            self.bitDepth = bitDepth
            self.fileFormat = fileFormat
            self.maxDuration = maxDuration
        }
    }

    public enum AudioFileFormat: String, Sendable {
        case wav
        case m4a
        case caf
    }

    // MARK: - Observable Properties

    /// Current recorder state.
    public private(set) var state: State = .idle

    /// Whether the recorder is actively capturing audio.
    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Elapsed recording duration in seconds.
    public private(set) var duration: TimeInterval = 0

    /// Current audio input level (0.0 – 1.0), updated in real time.
    public private(set) var audioLevel: Float = 0

    // MARK: - Properties

    private let configuration: Configuration
    private var currentFileURL: URL?
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0

    /// Callback for real-time audio level updates (0.0–1.0).
    private var levelCallback: (@Sendable (Float) -> Void)?

    // AVAudioEngine internals
    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var durationTimer: Timer?

    /// Lock for thread-safe access to mutable engine state.
    private let lock = NSLock()

    // MARK: - Init

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Current recorder state (thread-safe accessor).
    public func currentState() -> State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Prepare the audio engine and request microphone permission.
    public func prepare() async throws {
        lock.lock()
        state = .preparing
        lock.unlock()

        let permitted = await requestMicrophonePermission()
        guard permitted else {
            lock.lock()
            state = .failed("Microphone permission denied")
            lock.unlock()
            throw AudioRecorderError.permissionDenied
        }

        // Ensure audio storage directory exists
        let audioDir = AudioRecorder.defaultAudioStorageDirectory()
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        lock.lock()
        state = .idle
        lock.unlock()
    }

    /// Start recording audio. Captures 16 kHz mono PCM and writes to the file URL.
    ///
    /// - Parameter fileURL: Destination URL for the audio file. If nil, auto-generates
    ///   a path in the default audio storage directory.
    /// - Returns: The URL being written to.
    @discardableResult
    public func start(to fileURL: URL? = nil) async throws -> URL {
        lock.lock()
        guard case .idle = state else {
            let current = state
            lock.unlock()
            throw AudioRecorderError.invalidState(current: "\(current)")
        }
        lock.unlock()

        let destinationURL: URL
        if let fileURL {
            destinationURL = fileURL
        } else {
            let dir = AudioRecorder.defaultAudioStorageDirectory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let filename = "recording_\(UUID().uuidString).m4a"
            destinationURL = dir.appendingPathComponent(filename)
        }

        // Set up the audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create the recording format: 16 kHz mono PCM
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: configuration.sampleRate,
            channels: AVAudioChannelCount(configuration.channels),
            interleaved: false
        ) else {
            throw AudioRecorderError.engineSetupFailed("Failed to create recording format")
        }

        // Create format converter if needed
        let converter: AVAudioConverter?
        if inputFormat.sampleRate != recordingFormat.sampleRate ||
           inputFormat.channelCount != recordingFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: recordingFormat)
        } else {
            converter = nil
        }

        // Create the output file based on configured format
        let audioFile: AVAudioFile
        do {
            let outputSettings = self.outputSettings(for: configuration)
            audioFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioRecorderError.fileCreationFailed(destinationURL)
        }

        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            // Compute audio level from the buffer
            let level = self.computeLevel(from: buffer)
            self.lock.lock()
            self.audioLevel = level
            self.lock.unlock()
            self.levelCallback?(level)

            // Convert and write to file
            do {
                if let converter {
                    let frameCount = AVAudioFrameCount(
                        Double(buffer.frameLength) * recordingFormat.sampleRate / inputFormat.sampleRate
                    )
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: recordingFormat,
                        frameCapacity: frameCount
                    ) else { return }

                    var error: NSError?
                    let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    guard status != .error, error == nil else { return }
                    try audioFile.write(from: convertedBuffer)
                } else {
                    try audioFile.write(from: buffer)
                }
            } catch {
                // Log write error but don't crash — partial recordings are still useful
            }
        }

        // Start the engine
        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineSetupFailed(error.localizedDescription)
        }

        lock.lock()
        self.audioEngine = engine
        self.outputFile = audioFile
        self.currentFileURL = destinationURL
        self.recordingStartTime = Date.now
        self.accumulatedDuration = 0
        self.duration = 0
        self.state = .recording(duration: 0)
        lock.unlock()

        // Start duration tracking timer on main thread
        await MainActor.run {
            self.startDurationTimer()
        }

        return destinationURL
    }

    /// Convenience alias matching the original API.
    public func startRecording(to fileURL: URL) async throws {
        try await start(to: fileURL)
    }

    /// Stop recording and finalize the audio file.
    ///
    /// - Returns: The URL and duration of the completed recording.
    public func stop() async throws -> URL {
        lock.lock()
        guard case .recording = state, let fileURL = currentFileURL else {
            let current = state
            lock.unlock()
            throw AudioRecorderError.invalidState(current: "\(current)")
        }

        state = .stopping
        lock.unlock()

        await MainActor.run {
            self.stopDurationTimer()
        }

        // Tear down the engine
        lock.lock()
        let engine = audioEngine
        lock.unlock()

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        let finalDuration = recordingStartTime.map { Date.now.timeIntervalSince($0) } ?? 0

        lock.lock()
        self.audioEngine = nil
        self.outputFile = nil
        self.duration = finalDuration + accumulatedDuration
        self.state = .idle
        self.currentFileURL = nil
        self.recordingStartTime = nil
        self.audioLevel = 0
        lock.unlock()

        return fileURL
    }

    /// Stop recording returning both URL and duration (legacy API compatibility).
    public func stopRecording() async throws -> (url: URL, duration: TimeInterval) {
        let url = try await stop()
        return (url: url, duration: duration)
    }

    /// Cancel the current recording without saving.
    public func cancel() {
        lock.lock()
        let engine = audioEngine
        let fileURL = currentFileURL
        lock.unlock()

        // Tear down engine
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()

        // Remove the partial file
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        lock.lock()
        audioEngine = nil
        outputFile = nil
        currentFileURL = nil
        recordingStartTime = nil
        accumulatedDuration = 0
        duration = 0
        audioLevel = 0
        state = .idle
        lock.unlock()

        // Stop timer on main thread
        Task { @MainActor in
            self.stopDurationTimer()
        }
    }

    /// Pause the current recording.
    public func pause() throws {
        lock.lock()
        guard case .recording(let dur) = state else {
            let current = state
            lock.unlock()
            throw AudioRecorderError.invalidState(current: "\(current)")
        }

        audioEngine?.pause()
        accumulatedDuration += recordingStartTime.map { Date.now.timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        state = .paused(duration: dur)
        lock.unlock()

        Task { @MainActor in
            self.stopDurationTimer()
        }
    }

    /// Resume a paused recording.
    public func resume() throws {
        lock.lock()
        guard case .paused = state else {
            let current = state
            lock.unlock()
            throw AudioRecorderError.invalidState(current: "\(current)")
        }
        lock.unlock()

        do {
            try audioEngine?.start()
        } catch {
            throw AudioRecorderError.engineSetupFailed("Failed to resume: \(error.localizedDescription)")
        }

        lock.lock()
        recordingStartTime = Date.now
        state = .recording(duration: accumulatedDuration)
        lock.unlock()

        Task { @MainActor in
            self.startDurationTimer()
        }
    }

    /// Set a callback for real-time level metering.
    public func setLevelCallback(_ callback: @escaping @Sendable (Float) -> Void) {
        lock.lock()
        self.levelCallback = callback
        lock.unlock()
    }

    // MARK: - Static Helpers

    /// Default audio storage directory inside Documents.
    public static func defaultAudioStorageDirectory() -> URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
    }

    // MARK: - Private Helpers

    /// Request microphone access.
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Compute the RMS level from an audio buffer, normalized to 0.0–1.0.
    private func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelSamples = channelData[0]
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelSamples[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Convert to a 0–1 range using a dB-like mapping
        // Clamp the minimum to prevent -inf from log
        let minDb: Float = -60
        let maxDb: Float = 0
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = (db - minDb) / (maxDb - minDb)
        return min(max(normalized, 0), 1)
    }

    /// Build output settings dictionary for the configured file format.
    private func outputSettings(for config: Configuration) -> [String: Any] {
        switch config.fileFormat {
        case .m4a:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: config.sampleRate,
                AVNumberOfChannelsKey: config.channels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128_000,
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: config.sampleRate,
                AVNumberOfChannelsKey: config.channels,
                AVLinearPCMBitDepthKey: config.bitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        case .caf:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: config.sampleRate,
                AVNumberOfChannelsKey: config.channels,
                AVLinearPCMBitDepthKey: config.bitDepth,
                AVLinearPCMIsFloatKey: true,
            ]
        }
    }

    /// Start a repeating timer to update the published duration.
    @MainActor
    private func startDurationTimer() {
        stopDurationTimer()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let start = self.recordingStartTime
            let accumulated = self.accumulatedDuration
            let maxDur = self.configuration.maxDuration
            self.lock.unlock()

            let elapsed = accumulated + (start.map { Date.now.timeIntervalSince($0) } ?? 0)
            self.duration = elapsed

            self.lock.lock()
            if case .recording = self.state {
                self.state = .recording(duration: elapsed)
            }
            self.lock.unlock()

            // Auto-stop at max duration
            if elapsed >= maxDur {
                Task {
                    _ = try? await self.stop()
                }
            }
        }
    }

    /// Invalidate the duration timer.
    @MainActor
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    deinit {
        cancel()
    }
}

// MARK: - AudioRecorderError

public enum AudioRecorderError: Error, Sendable, LocalizedError {
    case permissionDenied
    case invalidState(current: String)
    case engineSetupFailed(String)
    case fileCreationFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied."
        case .invalidState(let current):
            return "Invalid recorder state: \(current)"
        case .engineSetupFailed(let reason):
            return "Audio engine setup failed: \(reason)"
        case .fileCreationFailed(let url):
            return "Failed to create audio file at: \(url.path)"
        }
    }
}
