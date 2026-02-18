// CoppermindCore – AudioPipeline.swift
// Protocols and default pipeline for record → transcribe → categorise.

import Foundation

// MARK: - Protocols

/// Records audio from the microphone and returns an AudioRecording.
public protocol AudioRecorderProtocol: Sendable {
    func record() async throws -> AudioRecording
}

/// Transcribes an AudioRecording into text.
public protocol AudioTranscriber: Sendable {
    func transcribe(_ recording: AudioRecording) async throws -> String
}

// MARK: - Pipeline

/// Orchestrates the full voice-note capture flow.
public struct AudioPipeline: Sendable {
    private let recorder: AudioRecorderProtocol
    private let transcriber: AudioTranscriber
    private let engine: CategorizationEngine

    public init(
        recorder: AudioRecorderProtocol,
        transcriber: AudioTranscriber,
        engine: CategorizationEngine = CategorizationEngine()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.engine = engine
    }

    /// Record, transcribe, then auto-categorise into a new Note.
    public func capture() async throws -> (note: Note, recording: AudioRecording) {
        var recording = try await recorder.record()
        let text = try await transcriber.transcribe(recording)
        recording.transcription = text

        let (category, priority) = engine.categorize(text)
        let note = Note(
            text: text,
            category: category,
            priority: priority,
            audioRecordingID: recording.id
        )
        return (note, recording)
    }
}
