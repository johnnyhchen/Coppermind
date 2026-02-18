// AudioCaptureViewModel.swift — Drives the audio recording and transcription UI
// CoppermindCore

import Foundation
import Observation
import SwiftData

/// ViewModel for the audio capture overlay / sheet.
/// Coordinates the full pipeline: record → live transcription → stop → editable text → confirm
/// → create Note + AudioRecording → auto-categorize.
///
/// Highlights low-confidence segments (<0.6) for user review.
@Observable
@MainActor
public final class AudioCaptureViewModel {

    // MARK: - State

    public enum CapturePhase: Equatable, Sendable {
        case idle
        case permissionRequired
        case readyToRecord
        case recording(duration: TimeInterval, level: Float)
        case processing
        case transcribed(text: String)
        case error(String)
    }

    /// Current phase of the capture flow.
    public var phase: CapturePhase = .idle

    /// Elapsed recording duration.
    public var recordingDuration: TimeInterval = 0

    /// Real-time audio input level (0.0–1.0).
    public var audioLevel: Float = 0

    /// The full transcribed text (editable by user before saving).
    public var transcribedText: String = ""

    /// User-provided title for the note (auto-generated if empty).
    public var noteTitle: String = ""

    /// Whether note creation is in progress.
    public var isCreatingNote: Bool = false

    /// Live partial transcription result (updated during recording).
    public var liveTranscription: TranscriptionResult = .empty

    /// Final transcription result with segment data.
    public var finalTranscription: TranscriptionResult?

    /// Segments flagged for review (confidence < 0.6).
    public var lowConfidenceSegments: [TranscriptionResult.Segment] {
        finalTranscription?.lowConfidenceSegments ?? liveTranscription.lowConfidenceSegments
    }

    /// Whether there are low-confidence segments requiring attention.
    public var hasLowConfidenceSegments: Bool {
        !lowConfidenceSegments.isEmpty
    }

    /// The suggested category from auto-categorization.
    public var suggestedCategory: NoteCategory?

    /// Category classification result for display.
    public var classificationResult: CategoryResult?

    // MARK: - Dependencies

    private let audioRecorder: AudioRecorder
    private let transcriptionService: TranscriptionService
    private let classifier: CategoryClassifier
    private let modelContext: ModelContext
    private var currentRecordingURL: URL?

    /// Base directory for audio file storage.
    private let audioStorageDirectory: URL

    /// Timer for updating recording state.
    private var durationTimer: Task<Void, Never>?

    /// Streaming transcription task.
    private var streamingTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Low confidence threshold for segment highlighting.
    public static let lowConfidenceThreshold: Double = 0.6

    /// Maximum recording duration (seconds).
    public static let maxRecordingDuration: TimeInterval = 600

    // MARK: - Init

    public init(
        audioRecorder: AudioRecorder,
        transcriptionService: TranscriptionService,
        modelContext: ModelContext,
        audioStorageDirectory: URL? = nil,
        classifier: CategoryClassifier = CategoryClassifier()
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.modelContext = modelContext
        self.audioStorageDirectory = audioStorageDirectory ?? AudioRecorder.defaultAudioStorageDirectory()
        self.classifier = classifier
    }

    // MARK: - Lifecycle

    /// Prepare the audio pipeline (permissions, engine).
    public func prepare() async {
        do {
            try await audioRecorder.prepare()

            let speechAuthorized = await transcriptionService.requestAuthorization()
            if !speechAuthorized {
                phase = .permissionRequired
                return
            }

            phase = .readyToRecord
        } catch {
            phase = .permissionRequired
        }
    }

    // MARK: - Recording

    /// Start a new audio recording with live transcription.
    public func startRecording() async {
        let fileName = "recording_\(UUID().uuidString).m4a"
        let fileURL = audioStorageDirectory.appendingPathComponent(fileName)
        currentRecordingURL = fileURL

        // Ensure storage directory exists
        try? FileManager.default.createDirectory(
            at: audioStorageDirectory,
            withIntermediateDirectories: true
        )

        do {
            await audioRecorder.setLevelCallback { [weak self] level in
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }

            try await audioRecorder.startRecording(to: fileURL)
            phase = .recording(duration: 0, level: 0)
            liveTranscription = .empty

            // Start duration tracking
            startDurationTracking()
        } catch {
            phase = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Stop recording and begin full transcription.
    public func stopRecording() async {
        // Cancel duration tracking
        durationTimer?.cancel()
        durationTimer = nil
        streamingTask?.cancel()
        streamingTask = nil

        do {
            let result = try await audioRecorder.stopRecording()
            recordingDuration = result.duration
            currentRecordingURL = result.url

            phase = .processing

            // Run full transcription on the completed file
            let transcription = try await transcriptionService.transcribe(audioURL: result.url)
            finalTranscription = transcription
            transcribedText = transcription.fullText

            // Auto-categorize the transcribed text
            await autoCategorize(text: transcription.fullText)

            phase = .transcribed(text: transcription.fullText)

        } catch {
            phase = .error("Recording/transcription failed: \(error.localizedDescription)")
        }
    }

    /// Cancel the current recording without saving.
    public func cancelRecording() async {
        durationTimer?.cancel()
        durationTimer = nil
        streamingTask?.cancel()
        streamingTask = nil

        do {
            _ = try await audioRecorder.stopRecording()
        } catch {
            // Ignore stop errors during cancellation
        }

        // Clean up temp file
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        reset()
    }

    // MARK: - Transcription Editing

    /// Check if a segment at the given index has low confidence.
    public func isLowConfidence(_ segment: TranscriptionResult.Segment) -> Bool {
        segment.confidence < Self.lowConfidenceThreshold
    }

    /// Get annotated text ranges for low-confidence segments.
    /// Returns tuples of (range in fullText, confidence).
    public var lowConfidenceRanges: [(text: String, confidence: Double)] {
        guard let transcription = finalTranscription else { return [] }
        return transcription.segments
            .filter { $0.confidence < Self.lowConfidenceThreshold }
            .map { ($0.text, $0.confidence) }
    }

    /// Replace the text of a segment (user correction).
    /// Updates the transcribedText to reflect the edit.
    public func correctSegment(at index: Int, with newText: String) {
        guard let transcription = finalTranscription,
              index < transcription.segments.count else { return }

        let segment = transcription.segments[index]
        transcribedText = transcribedText.replacingOccurrences(of: segment.text, with: newText)
    }

    // MARK: - Note Creation

    /// Create a note from the transcribed audio.
    ///
    /// - Returns: The created Note, or nil on failure.
    @discardableResult
    public func createNoteFromTranscription() async -> Note? {
        guard case .transcribed = phase else { return nil }

        isCreatingNote = true

        let note = Note(
            title: noteTitle.isEmpty ? generateTitle(from: transcribedText) : noteTitle,
            body: transcribedText,
            category: suggestedCategory ?? .idea,
            source: .audio
        )

        modelContext.insert(note)

        // Create AudioRecording attachment
        if let recordingURL = currentRecordingURL {
            let relativePath = recordingURL.lastPathComponent
            let avgConfidence = finalTranscription?.confidence
            let recording = AudioRecording(
                note: note,
                filePath: relativePath,
                duration: recordingDuration,
                transcriptionText: transcribedText,
                transcriptionConfidence: avgConfidence
            )
            modelContext.insert(recording)
        }

        // Auto-categorize if not already done
        if suggestedCategory == nil {
            await autoCategorize(text: transcribedText)
            note.category = suggestedCategory ?? .idea
        }

        do {
            try modelContext.save()
        } catch {
            phase = .error("Failed to save note: \(error.localizedDescription)")
            isCreatingNote = false
            return nil
        }

        isCreatingNote = false
        return note
    }

    /// Create a note and automatically apply categorization.
    ///
    /// - Returns: The created Note, or nil on failure.
    @discardableResult
    public func createAndCategorizeNote() async -> Note? {
        guard let note = await createNoteFromTranscription() else { return nil }

        // Run categorization and apply
        let result = await classifier.classifyAndApply(to: note)
        classificationResult = result
        suggestedCategory = result.category

        do {
            try modelContext.save()
        } catch {
            // Note was already created; classification can be retried later
        }

        return note
    }

    // MARK: - Reset

    /// Reset to idle state.
    public func reset() {
        phase = .idle
        recordingDuration = 0
        audioLevel = 0
        transcribedText = ""
        noteTitle = ""
        currentRecordingURL = nil
        isCreatingNote = false
        liveTranscription = .empty
        finalTranscription = nil
        suggestedCategory = nil
        classificationResult = nil
        durationTimer?.cancel()
        durationTimer = nil
        streamingTask?.cancel()
        streamingTask = nil
    }

    // MARK: - Private Helpers

    /// Start a repeating task to update the recording duration display.
    private func startDurationTracking() {
        durationTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let dur = self.audioRecorder.duration
                self.recordingDuration = dur
                self.phase = .recording(duration: dur, level: self.audioLevel)

                // Auto-stop at max duration
                if dur >= Self.maxRecordingDuration {
                    await self.stopRecording()
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Run auto-categorization on the transcribed text.
    private func autoCategorize(text: String) async {
        guard !text.isEmpty else { return }
        let result = await classifier.classify(text: text)
        suggestedCategory = result.category
        classificationResult = result
    }

    /// Generate a title from the first sentence of transcribed text.
    private func generateTitle(from text: String) -> String {
        let firstSentence = text
            .prefix(100)
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return firstSentence ?? "Audio Note"
    }
}
