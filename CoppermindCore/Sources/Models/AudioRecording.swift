// AudioRecording.swift — Audio capture metadata and transcription
// CoppermindCore

import Foundation
import SwiftData

/// Metadata for an audio recording attached to a note, including transcription state.
@Model
public final class AudioRecording: Sendable {

    // MARK: - Persisted Properties

    @Attribute(.unique)
    public var id: UUID

    /// The note this recording is attached to.
    public var note: Note

    /// Relative file path within the app's audio storage directory.
    public var filePath: String

    /// Duration in seconds.
    public var duration: TimeInterval

    /// The transcribed text, if available.
    public var transcriptionText: String?

    /// Confidence score for the transcription (0.0–1.0).
    public var transcriptionConfidence: Double?

    /// Whether the transcription has been manually edited by the user.
    public var isEdited: Bool

    public var createdAt: Date

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        note: Note,
        filePath: String,
        duration: TimeInterval = 0,
        transcriptionText: String? = nil,
        transcriptionConfidence: Double? = nil,
        isEdited: Bool = false
    ) {
        self.id = id
        self.note = note
        self.filePath = filePath
        self.duration = duration
        self.transcriptionText = transcriptionText
        self.transcriptionConfidence = transcriptionConfidence
        self.isEdited = isEdited
        self.createdAt = Date.now
    }

    // MARK: - Convenience

    /// Whether a usable transcription exists.
    public var hasTranscription: Bool {
        transcriptionText != nil
    }

    /// The audio file URL resolved against a base directory.
    public func resolvedURL(base: URL) -> URL {
        base.appendingPathComponent(filePath)
    }
}
