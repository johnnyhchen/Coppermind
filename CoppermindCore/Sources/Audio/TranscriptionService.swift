// TranscriptionService.swift — On-device speech-to-text via Speech framework
// CoppermindCore

import Foundation
import Speech

// MARK: - Transcribing Protocol

/// Protocol for any transcription backend (on-device Apple Speech, OpenAI Whisper, etc.).
public protocol Transcribing: Sendable {

    /// Request authorization for speech recognition.
    func requestAuthorization() async -> Bool

    /// Transcribe an audio file at the given URL.
    ///
    /// - Parameter audioURL: URL of the audio file.
    /// - Returns: The complete transcription result with segments.
    func transcribe(audioURL: URL) async throws -> TranscriptionResult

    /// Start a streaming transcription session that delivers partial results.
    ///
    /// - Parameter audioURL: URL of the audio file (or live engine buffer).
    /// - Returns: An `AsyncStream` of partial transcription results.
    func transcribeStreaming(audioURL: URL) -> AsyncStream<TranscriptionResult>
}

// MARK: - TranscriptionResult

/// Full transcription result with text, segments, and per-segment confidence.
public struct TranscriptionResult: Sendable, Equatable {
    /// The complete transcribed text.
    public let fullText: String

    /// Weighted average confidence across all segments (0.0–1.0).
    public let confidence: Double

    /// Per-segment breakdown with individual confidence scores.
    public let segments: [Segment]

    /// Total audio duration covered by the transcription.
    public let duration: TimeInterval

    /// Whether this is a partial (in-progress) or final result.
    public let isFinal: Bool

    /// A single transcription segment (word or phrase).
    public struct Segment: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let text: String
        public let timestamp: TimeInterval
        public let duration: TimeInterval
        public let confidence: Double

        /// Whether confidence is below the low-confidence threshold (0.6).
        public var isLowConfidence: Bool {
            confidence < 0.6
        }

        public init(
            id: UUID = UUID(),
            text: String,
            timestamp: TimeInterval,
            duration: TimeInterval,
            confidence: Double
        ) {
            self.id = id
            self.text = text
            self.timestamp = timestamp
            self.duration = duration
            self.confidence = min(max(confidence, 0.0), 1.0)
        }
    }

    /// Backward-compatible `text` alias for `fullText`.
    public var text: String { fullText }

    /// Segments flagged as low confidence (<0.6).
    public var lowConfidenceSegments: [Segment] {
        segments.filter(\.isLowConfidence)
    }

    /// Whether any segment has low confidence.
    public var hasLowConfidenceSegments: Bool {
        !lowConfidenceSegments.isEmpty
    }

    public init(
        fullText: String,
        confidence: Double,
        segments: [Segment],
        duration: TimeInterval,
        isFinal: Bool = true
    ) {
        self.fullText = fullText
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.segments = segments
        self.duration = duration
        self.isFinal = isFinal
    }

    /// Empty result for initialization.
    public static let empty = TranscriptionResult(
        fullText: "",
        confidence: 0,
        segments: [],
        duration: 0,
        isFinal: false
    )
}

// MARK: - AppleSpeechTranscriber

/// On-device transcription using Apple's SFSpeechRecognizer.
/// Supports both file-based and streaming partial results with per-segment confidence.
public final class AppleSpeechTranscriber: Transcribing, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let locale: Locale
        public let shouldReportPartialResults: Bool
        public let requiresOnDeviceRecognition: Bool
        public let taskHint: SFSpeechRecognitionTaskHint

        public init(
            locale: Locale = Locale(identifier: "en-US"),
            shouldReportPartialResults: Bool = true,
            requiresOnDeviceRecognition: Bool = true,
            taskHint: SFSpeechRecognitionTaskHint = .dictation
        ) {
            self.locale = locale
            self.shouldReportPartialResults = shouldReportPartialResults
            self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
            self.taskHint = taskHint
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var currentTask: SFSpeechRecognitionTask?
    private let lock = NSLock()

    // MARK: - Init

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Check current authorization status without prompting.
    public func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - File-based Transcription

    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard let recognizer = SFSpeechRecognizer(locale: configuration.locale) else {
            throw TranscriptionError.recognizerUnavailable(configuration.locale)
        }

        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerNotReady
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = configuration.requiresOnDeviceRecognition
        request.taskHint = configuration.taskHint

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !didResume else { return }

                if let error {
                    didResume = true
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else { return }
                didResume = true

                let transcriptionResult = Self.mapResult(result)
                continuation.resume(returning: transcriptionResult)
            }

            self.lock.lock()
            self.currentTask = task
            self.lock.unlock()
        }
    }

    // MARK: - Streaming Transcription

    public func transcribeStreaming(audioURL: URL) -> AsyncStream<TranscriptionResult> {
        AsyncStream { continuation in
            guard let recognizer = SFSpeechRecognizer(locale: configuration.locale),
                  recognizer.isAvailable else {
                continuation.finish()
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = configuration.shouldReportPartialResults
            request.requiresOnDeviceRecognition = configuration.requiresOnDeviceRecognition
            request.taskHint = configuration.taskHint

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    let errorResult = TranscriptionResult(
                        fullText: "Error: \(error.localizedDescription)",
                        confidence: 0,
                        segments: [],
                        duration: 0,
                        isFinal: true
                    )
                    continuation.yield(errorResult)
                    continuation.finish()
                    return
                }

                guard let result else { return }

                let mapped = Self.mapResult(result, isFinal: result.isFinal)
                continuation.yield(mapped)

                if result.isFinal {
                    continuation.finish()
                }
            }

            self.lock.lock()
            self.currentTask = task
            self.lock.unlock()

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Cancel any in-progress transcription task.
    public func cancelTranscription() {
        lock.lock()
        currentTask?.cancel()
        currentTask = nil
        lock.unlock()
    }

    // MARK: - Mapping Helpers

    /// Map an `SFSpeechRecognitionResult` to our `TranscriptionResult`.
    private static func mapResult(
        _ result: SFSpeechRecognitionResult,
        isFinal: Bool? = nil
    ) -> TranscriptionResult {
        let bestTranscription = result.bestTranscription

        let segments = bestTranscription.segments.map { segment in
            TranscriptionResult.Segment(
                text: segment.substring,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: Double(segment.confidence)
            )
        }

        let avgConfidence: Double
        if segments.isEmpty {
            avgConfidence = 0.0
        } else {
            // Weight confidence by segment duration for more accurate overall score
            let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
            if totalDuration > 0 {
                avgConfidence = segments.reduce(0.0) { $0 + $1.confidence * $1.duration } / totalDuration
            } else {
                avgConfidence = segments.reduce(0.0) { $0 + $1.confidence } / Double(segments.count)
            }
        }

        let totalDuration = segments.last.map { $0.timestamp + $0.duration } ?? 0

        return TranscriptionResult(
            fullText: bestTranscription.formattedString,
            confidence: avgConfidence,
            segments: segments,
            duration: totalDuration,
            isFinal: isFinal ?? result.isFinal
        )
    }
}

// MARK: - WhisperTranscriber (Stub — OpenAI API, user opt-in)

/// Whisper transcription backend using the OpenAI API.
/// Requires explicit user opt-in because audio data is sent to an external server.
///
/// - Important: This is a stub implementation. To enable, the user must provide
///   an API key in Settings and explicitly opt in to cloud transcription.
public final class WhisperTranscriber: Transcribing, @unchecked Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let apiKey: String
        public let model: String
        public let language: String?
        public let baseURL: URL

        public init(
            apiKey: String,
            model: String = "whisper-1",
            language: String? = "en",
            baseURL: URL = URL(string: "https://api.openai.com/v1")!
        ) {
            self.apiKey = apiKey
            self.model = model
            self.language = language
            self.baseURL = baseURL
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private let session: URLSession

    // MARK: - Init

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Transcribing

    public func requestAuthorization() async -> Bool {
        // Whisper only requires a valid API key; no OS-level permission needed.
        !configuration.apiKey.isEmpty
    }

    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        // Validate API key
        guard !configuration.apiKey.isEmpty else {
            throw TranscriptionError.authorizationDenied
        }

        // Build the multipart/form-data request
        let boundary = UUID().uuidString
        let url = configuration.baseURL.appendingPathComponent("audio/transcriptions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Read audio data
        let audioData = try Data(contentsOf: audioURL)

        // Build multipart body
        var body = Data()

        // model field
        body.appendMultipart(boundary: boundary, name: "model", value: configuration.model)

        // language field (optional)
        if let language = configuration.language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // response_format for verbose JSON (includes segments)
        body.appendMultipart(boundary: boundary, name: "response_format", value: "verbose_json")

        // timestamp granularities
        body.appendMultipart(boundary: boundary, name: "timestamp_granularities[]", value: "segment")

        // audio file
        body.appendMultipartFile(
            boundary: boundary,
            name: "file",
            filename: audioURL.lastPathComponent,
            mimeType: "audio/m4a",
            data: audioData
        )

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Execute request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranscriptionError.recognitionFailed("Whisper API returned status \(statusCode)")
        }

        // Parse verbose_json response
        return try Self.parseWhisperResponse(data)
    }

    public func transcribeStreaming(audioURL: URL) -> AsyncStream<TranscriptionResult> {
        // Whisper API does not support true streaming.
        // We emit a single final result.
        AsyncStream { continuation in
            Task {
                do {
                    let result = try await self.transcribe(audioURL: audioURL)
                    continuation.yield(result)
                } catch {
                    // Yield error as empty result
                    continuation.yield(TranscriptionResult(
                        fullText: "Whisper error: \(error.localizedDescription)",
                        confidence: 0,
                        segments: [],
                        duration: 0,
                        isFinal: true
                    ))
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Response Parsing

    private static func parseWhisperResponse(_ data: Data) throws -> TranscriptionResult {
        struct WhisperResponse: Decodable {
            let text: String
            let duration: Double?
            let segments: [WhisperSegment]?

            struct WhisperSegment: Decodable {
                let id: Int
                let text: String
                let start: Double
                let end: Double
                let avg_logprob: Double?
                let no_speech_prob: Double?
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(WhisperResponse.self, from: data)

        let segments: [TranscriptionResult.Segment] = (response.segments ?? []).map { seg in
            // Convert avg_logprob to a 0–1 confidence approximation
            let logprob = seg.avg_logprob ?? -1.0
            let confidence = min(max(exp(logprob), 0), 1)

            return TranscriptionResult.Segment(
                text: seg.text.trimmingCharacters(in: .whitespaces),
                timestamp: seg.start,
                duration: seg.end - seg.start,
                confidence: confidence
            )
        }

        let avgConfidence: Double
        if segments.isEmpty {
            avgConfidence = 0.5
        } else {
            avgConfidence = segments.reduce(0.0) { $0 + $1.confidence } / Double(segments.count)
        }

        return TranscriptionResult(
            fullText: response.text,
            confidence: avgConfidence,
            segments: segments,
            duration: response.duration ?? segments.last.map { $0.timestamp + $0.duration } ?? 0,
            isFinal: true
        )
    }
}

// MARK: - TranscriptionService (Convenience Facade)

/// Convenience facade that wraps any `Transcribing` backend.
/// Defaults to `AppleSpeechTranscriber` for on-device processing.
public actor TranscriptionService {

    // MARK: - Properties

    private let backend: any Transcribing

    // MARK: - Init

    /// Initialize with any `Transcribing` backend. Defaults to Apple on-device speech.
    public init(backend: any Transcribing = AppleSpeechTranscriber()) {
        self.backend = backend
    }

    /// Legacy init for backward compatibility.
    public init(configuration: AppleSpeechTranscriber.Configuration = .init()) {
        self.backend = AppleSpeechTranscriber(configuration: configuration)
    }

    // MARK: - Authorization

    /// Request speech recognition authorization from the active backend.
    public func requestAuthorization() async -> Bool {
        await backend.requestAuthorization()
    }

    /// Check current authorization status (Apple Speech only).
    public func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Transcription

    /// Transcribe an audio file using the configured backend.
    public func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await backend.transcribe(audioURL: audioURL)
    }

    /// Stream partial transcription results for live feedback.
    public func transcribeStreaming(audioURL: URL) -> AsyncStream<TranscriptionResult> {
        backend.transcribeStreaming(audioURL: audioURL)
    }

    /// Transcribe and update an AudioRecording model in place.
    public func transcribe(recording: AudioRecording, baseDirectory: URL) async throws {
        let audioURL = recording.resolvedURL(base: baseDirectory)
        let result = try await transcribe(audioURL: audioURL)
        recording.transcriptionText = result.fullText
        recording.transcriptionConfidence = result.confidence
    }
}

// MARK: - TranscriptionError

public enum TranscriptionError: Error, Sendable, LocalizedError {
    case recognizerUnavailable(Locale)
    case recognizerNotReady
    case recognitionFailed(String)
    case authorizationDenied

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable(let locale):
            return "Speech recognizer unavailable for locale: \(locale.identifier)"
        case .recognizerNotReady:
            return "Speech recognizer is not currently available."
        case .recognitionFailed(let reason):
            return "Speech recognition failed: \(reason)"
        case .authorizationDenied:
            return "Speech recognition authorization was denied."
        }
    }
}

// MARK: - Data Multipart Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        let field = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        append(field.data(using: .utf8)!)
    }

    mutating func appendMultipartFile(
        boundary: String,
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        var header = "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        header += "Content-Type: \(mimeType)\r\n\r\n"
        append(header.data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
