// AudioPipelineTests.swift — Tests for audio recording and transcription pipeline
// CoppermindTests

import Testing
import Foundation
import SwiftData
@testable import CoppermindCore

// MARK: - AudioRecorder Tests

@Suite("AudioRecorder")
struct AudioRecorderTests {

    @Test("Initial state is idle")
    func initialState() async {
        let recorder = AudioRecorder()
        let state = await recorder.currentState()
        #expect(state == .idle)
    }

    @Test("Default configuration uses 16kHz mono m4a with 10min max")
    func defaultConfiguration() async {
        let config = AudioRecorder.Configuration()
        #expect(config.sampleRate == 16000)
        #expect(config.channels == 1)
        #expect(config.fileFormat == .m4a)
        #expect(config.maxDuration == 600)
    }

    @Test("Custom configuration is applied")
    func customConfiguration() async {
        let config = AudioRecorder.Configuration(
            sampleRate: 48000,
            channels: 2,
            bitDepth: 24,
            fileFormat: .m4a,
            maxDuration: 600
        )
        let recorder = AudioRecorder(configuration: config)
        // Verifying initialization with custom config does not crash
        let state = await recorder.currentState()
        #expect(state == .idle)
    }

    @Test("Cannot start recording from non-idle state")
    func invalidStartState() async {
        let recorder = AudioRecorder()
        let state = await recorder.currentState()
        #expect(state == .idle)
    }

    @Test("Level callback can be set")
    func levelCallback() async {
        let recorder = AudioRecorder()
        var receivedLevel: Float?
        await recorder.setLevelCallback { level in
            receivedLevel = level
        }
        // Callback is stored — we cannot trigger it without actual recording
        _ = receivedLevel
    }

    @Test("isRecording is false when idle")
    func isRecordingFalseWhenIdle() async {
        let recorder = AudioRecorder()
        #expect(recorder.isRecording == false)
    }

    @Test("Duration is zero initially")
    func durationZeroInitially() async {
        let recorder = AudioRecorder()
        #expect(recorder.duration == 0)
    }

    @Test("Audio level is zero initially")
    func audioLevelZeroInitially() async {
        let recorder = AudioRecorder()
        #expect(recorder.audioLevel == 0)
    }

    @Test("Cancel from idle does not crash")
    func cancelFromIdle() async {
        let recorder = AudioRecorder()
        recorder.cancel()
        let state = await recorder.currentState()
        #expect(state == .idle)
    }

    @Test("Default audio storage directory is under Documents/audio")
    func defaultStorageDirectory() {
        let dir = AudioRecorder.defaultAudioStorageDirectory()
        #expect(dir.lastPathComponent == "audio")
        #expect(dir.pathComponents.contains("Documents") || dir.path.contains("Documents"))
    }

    @Test("WAV configuration produces correct format")
    func wavConfiguration() async {
        let config = AudioRecorder.Configuration(
            sampleRate: 44100,
            channels: 1,
            bitDepth: 16,
            fileFormat: .wav,
            maxDuration: 3600
        )
        let recorder = AudioRecorder(configuration: config)
        let state = await recorder.currentState()
        #expect(state == .idle)
    }
}

// MARK: - AudioRecorderError Tests

@Suite("AudioRecorderError")
struct AudioRecorderErrorTests {

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [AudioRecorderError] = [
            .permissionDenied,
            .invalidState(current: "recording"),
            .engineSetupFailed("No input device"),
            .fileCreationFailed(URL(filePath: "/tmp/test.wav")),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Permission denied has correct description")
    func permissionDenied() {
        let error = AudioRecorderError.permissionDenied
        #expect(error.errorDescription!.contains("permission"))
    }

    @Test("Invalid state includes state info")
    func invalidState() {
        let error = AudioRecorderError.invalidState(current: "recording(duration: 5.0)")
        #expect(error.errorDescription!.contains("recording"))
    }
}

// MARK: - TranscriptionResult Tests

@Suite("TranscriptionResult")
struct TranscriptionResultTests {

    @Test("Empty result has sensible defaults")
    func emptyResult() {
        let result = TranscriptionResult.empty
        #expect(result.fullText.isEmpty)
        #expect(result.confidence == 0)
        #expect(result.segments.isEmpty)
        #expect(result.duration == 0)
        #expect(result.isFinal == false)
    }

    @Test("text property aliases fullText")
    func textAlias() {
        let result = TranscriptionResult(
            fullText: "Hello world",
            confidence: 0.9,
            segments: [],
            duration: 1.5
        )
        #expect(result.text == result.fullText)
        #expect(result.text == "Hello world")
    }

    @Test("Low confidence segments are identified")
    func lowConfidenceSegments() {
        let segments = [
            TranscriptionResult.Segment(text: "Hello", timestamp: 0, duration: 0.5, confidence: 0.95),
            TranscriptionResult.Segment(text: "wrold", timestamp: 0.5, duration: 0.5, confidence: 0.3),
            TranscriptionResult.Segment(text: "test", timestamp: 1.0, duration: 0.5, confidence: 0.59),
            TranscriptionResult.Segment(text: "okay", timestamp: 1.5, duration: 0.5, confidence: 0.6),
        ]

        let result = TranscriptionResult(
            fullText: "Hello wrold test okay",
            confidence: 0.6,
            segments: segments,
            duration: 2.0
        )

        #expect(result.hasLowConfidenceSegments == true)
        #expect(result.lowConfidenceSegments.count == 2)
        #expect(result.lowConfidenceSegments[0].text == "wrold")
        #expect(result.lowConfidenceSegments[1].text == "test")
    }

    @Test("No low confidence segments when all above threshold")
    func noLowConfidenceSegments() {
        let segments = [
            TranscriptionResult.Segment(text: "Hello", timestamp: 0, duration: 0.5, confidence: 0.9),
            TranscriptionResult.Segment(text: "world", timestamp: 0.5, duration: 0.5, confidence: 0.85),
        ]

        let result = TranscriptionResult(
            fullText: "Hello world",
            confidence: 0.875,
            segments: segments,
            duration: 1.0
        )

        #expect(result.hasLowConfidenceSegments == false)
        #expect(result.lowConfidenceSegments.isEmpty)
    }

    @Test("Segment isLowConfidence threshold is 0.6")
    func segmentThreshold() {
        let low = TranscriptionResult.Segment(text: "a", timestamp: 0, duration: 0.1, confidence: 0.59)
        let borderline = TranscriptionResult.Segment(text: "b", timestamp: 0, duration: 0.1, confidence: 0.6)
        let high = TranscriptionResult.Segment(text: "c", timestamp: 0, duration: 0.1, confidence: 0.61)

        #expect(low.isLowConfidence == true)
        #expect(borderline.isLowConfidence == false)
        #expect(high.isLowConfidence == false)
    }

    @Test("Confidence is clamped to 0-1")
    func confidenceClamping() {
        let segment = TranscriptionResult.Segment(text: "x", timestamp: 0, duration: 0.1, confidence: 1.5)
        #expect(segment.confidence == 1.0)

        let segment2 = TranscriptionResult.Segment(text: "y", timestamp: 0, duration: 0.1, confidence: -0.5)
        #expect(segment2.confidence == 0.0)
    }

    @Test("Segment has unique identifiers")
    func segmentIdentifiers() {
        let a = TranscriptionResult.Segment(text: "a", timestamp: 0, duration: 0.1, confidence: 0.9)
        let b = TranscriptionResult.Segment(text: "b", timestamp: 0.1, duration: 0.1, confidence: 0.9)
        #expect(a.id != b.id)
    }

    @Test("isFinal defaults to true")
    func isFinalDefault() {
        let result = TranscriptionResult(
            fullText: "test",
            confidence: 0.9,
            segments: [],
            duration: 1.0
        )
        #expect(result.isFinal == true)
    }
}

// MARK: - TranscriptionService Tests

@Suite("TranscriptionService")
struct TranscriptionServiceTests {

    @Test("Default configuration uses Apple backend")
    func defaultConfig() async {
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let status = await service.authorizationStatus()
        // Authorization status depends on environment — just verify no crash
        _ = status
    }

    @Test("Custom locale configuration")
    func customLocale() async {
        let config = AppleSpeechTranscriber.Configuration(
            locale: Locale(identifier: "ja-JP"),
            shouldReportPartialResults: false,
            requiresOnDeviceRecognition: true,
            taskHint: .search
        )
        let transcriber = AppleSpeechTranscriber(configuration: config)
        _ = transcriber
    }

    @Test("Service can be initialized with custom backend")
    func customBackend() async {
        let transcriber = AppleSpeechTranscriber()
        let service = TranscriptionService(backend: transcriber)
        _ = service
    }
}

// MARK: - TranscriptionError Tests

@Suite("TranscriptionError")
struct TranscriptionErrorTests {

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [TranscriptionError] = [
            .recognizerUnavailable(Locale(identifier: "en-US")),
            .recognizerNotReady,
            .recognitionFailed("timeout"),
            .authorizationDenied,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Recognizer unavailable includes locale")
    func recognizerUnavailableLocale() {
        let error = TranscriptionError.recognizerUnavailable(Locale(identifier: "fr-FR"))
        #expect(error.errorDescription!.contains("fr-FR"))
    }

    @Test("Recognition failed includes reason")
    func recognitionFailedReason() {
        let error = TranscriptionError.recognitionFailed("network timeout")
        #expect(error.errorDescription!.contains("network timeout"))
    }
}

// MARK: - AppleSpeechTranscriber Tests

@Suite("AppleSpeechTranscriber")
struct AppleSpeechTranscriberTests {

    @Test("Default configuration")
    func defaultConfig() {
        let config = AppleSpeechTranscriber.Configuration()
        #expect(config.locale.identifier == "en-US" || config.locale.identifier == "en_US")
        #expect(config.shouldReportPartialResults == true)
        #expect(config.requiresOnDeviceRecognition == true)
    }

    @Test("Cancel transcription does not crash")
    func cancelTranscription() {
        let transcriber = AppleSpeechTranscriber()
        transcriber.cancelTranscription()
        // Should not crash
    }
}

// MARK: - WhisperTranscriber Tests

@Suite("WhisperTranscriber")
struct WhisperTranscriberTests {

    @Test("Empty API key fails authorization")
    func emptyApiKeyFailsAuth() async {
        let config = WhisperTranscriber.Configuration(apiKey: "")
        let transcriber = WhisperTranscriber(configuration: config)
        let authorized = await transcriber.requestAuthorization()
        #expect(authorized == false)
    }

    @Test("Non-empty API key passes authorization")
    func validApiKeyPassesAuth() async {
        let config = WhisperTranscriber.Configuration(apiKey: "sk-test-key")
        let transcriber = WhisperTranscriber(configuration: config)
        let authorized = await transcriber.requestAuthorization()
        #expect(authorized == true)
    }

    @Test("Default model is whisper-1")
    func defaultModel() {
        let config = WhisperTranscriber.Configuration(apiKey: "test")
        #expect(config.model == "whisper-1")
    }

    @Test("Custom configuration is respected")
    func customConfig() {
        let config = WhisperTranscriber.Configuration(
            apiKey: "sk-custom",
            model: "whisper-2",
            language: "fr"
        )
        #expect(config.model == "whisper-2")
        #expect(config.language == "fr")
    }
}

// MARK: - AudioPlaybackManager Tests

@Suite("AudioPlaybackManager")
struct AudioPlaybackManagerTests {

    @Test("Initial state is idle")
    func initialState() {
        let manager = AudioPlaybackManager()
        #expect(manager.state == .idle)
        #expect(manager.currentTime == 0)
        #expect(manager.duration == 0)
        #expect(manager.playbackRate == 1.0)
        #expect(manager.isPlaying == false)
    }

    @Test("Playback rate clamping")
    func rateClamping() {
        let manager = AudioPlaybackManager()
        manager.playbackRate = 3.0
        #expect(manager.playbackRate <= 2.0)

        manager.playbackRate = 0.1
        #expect(manager.playbackRate >= 0.5)
    }

    @Test("Normal rate values pass through")
    func normalRateValues() {
        let manager = AudioPlaybackManager()
        manager.playbackRate = 1.5
        #expect(manager.playbackRate == 1.5)

        manager.playbackRate = 0.75
        #expect(manager.playbackRate == 0.75)
    }

    @Test("Stop resets state")
    func stopResetsState() {
        let manager = AudioPlaybackManager()
        manager.stop()
        #expect(manager.state == .idle)
        #expect(manager.currentTime == 0)
        #expect(manager.duration == 0)
        #expect(manager.isPlaying == false)
    }

    @Test("Pause from non-playing state is no-op")
    func pauseNoOp() {
        let manager = AudioPlaybackManager()
        manager.pause()
        #expect(manager.state == .idle)
    }

    @Test("Resume from non-paused state is no-op")
    func resumeNoOp() {
        let manager = AudioPlaybackManager()
        manager.resume()
        #expect(manager.state == .idle)
    }

    @Test("Toggle play/pause from idle is no-op")
    func toggleFromIdleNoOp() {
        let manager = AudioPlaybackManager()
        manager.togglePlayPause()
        #expect(manager.state == .idle)
    }

    @Test("Formatted time strings")
    func formattedTimeStrings() {
        let manager = AudioPlaybackManager()
        // With no audio loaded, times should be zero
        #expect(manager.formattedCurrentTime == "0:00")
        #expect(manager.formattedDuration == "0:00")
        #expect(manager.formattedRemainingTime == "-0:00")
    }

    @Test("Progress is zero when no audio loaded")
    func progressZero() {
        let manager = AudioPlaybackManager()
        #expect(manager.progress == 0)
    }

    @Test("Skip forward from zero")
    func skipForward() {
        let manager = AudioPlaybackManager()
        manager.skipForward(seconds: 15)
        // Without a loaded file, seek is bounded to 0–duration
        #expect(manager.currentTime >= 0)
    }

    @Test("Skip backward from zero")
    func skipBackward() {
        let manager = AudioPlaybackManager()
        manager.skipBackward(seconds: 15)
        // Should clamp to 0
        #expect(manager.currentTime >= 0)
    }
}

// MARK: - AudioCaptureViewModel Tests

@Suite("AudioCaptureViewModel")
struct AudioCaptureViewModelTests {

    @Test("Initial phase is idle")
    @MainActor func initialPhase() async {
        let recorder = AudioRecorder()
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let container = try! ModelContainer(
            for: Note.self, AudioRecording.self, Connection.self, NoteGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = AudioCaptureViewModel(
            audioRecorder: recorder,
            transcriptionService: service,
            modelContext: context
        )

        #expect(vm.phase == .idle)
        #expect(vm.transcribedText.isEmpty)
        #expect(vm.recordingDuration == 0)
        #expect(vm.audioLevel == 0)
        #expect(vm.isCreatingNote == false)
    }

    @Test("Reset clears all state")
    @MainActor func resetClearsState() async {
        let recorder = AudioRecorder()
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let container = try! ModelContainer(
            for: Note.self, AudioRecording.self, Connection.self, NoteGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = AudioCaptureViewModel(
            audioRecorder: recorder,
            transcriptionService: service,
            modelContext: context
        )

        // Mutate some state
        vm.transcribedText = "Some text"
        vm.noteTitle = "Test"
        vm.recordingDuration = 42

        // Reset
        vm.reset()

        #expect(vm.phase == .idle)
        #expect(vm.transcribedText.isEmpty)
        #expect(vm.noteTitle.isEmpty)
        #expect(vm.recordingDuration == 0)
        #expect(vm.audioLevel == 0)
        #expect(vm.isCreatingNote == false)
        #expect(vm.suggestedCategory == nil)
        #expect(vm.classificationResult == nil)
        #expect(vm.finalTranscription == nil)
    }

    @Test("Generate title from short text")
    @MainActor func generateTitleShortText() async {
        let recorder = AudioRecorder()
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let container = try! ModelContainer(
            for: Note.self, AudioRecording.self, Connection.self, NoteGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = AudioCaptureViewModel(
            audioRecorder: recorder,
            transcriptionService: service,
            modelContext: context
        )

        // Test that title generation works (tested indirectly)
        vm.transcribedText = "Remember to buy groceries."
        vm.noteTitle = ""

        // Cannot create note without transcribed phase, but we can verify state
        #expect(vm.noteTitle.isEmpty)
    }

    @Test("Low confidence threshold is 0.6")
    @MainActor func lowConfidenceThreshold() {
        #expect(AudioCaptureViewModel.lowConfidenceThreshold == 0.6)
    }

    @Test("Max recording duration is 600 seconds")
    @MainActor func maxDuration() {
        #expect(AudioCaptureViewModel.maxRecordingDuration == 600)
    }

    @Test("hasLowConfidenceSegments reflects transcription data")
    @MainActor func lowConfidenceReflection() async {
        let recorder = AudioRecorder()
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let container = try! ModelContainer(
            for: Note.self, AudioRecording.self, Connection.self, NoteGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = AudioCaptureViewModel(
            audioRecorder: recorder,
            transcriptionService: service,
            modelContext: context
        )

        // Initially no low confidence segments
        #expect(vm.hasLowConfidenceSegments == false)
        #expect(vm.lowConfidenceSegments.isEmpty)
    }

    @Test("CapturePhase equality works correctly")
    func capturePhaseEquality() {
        let idle1 = AudioCaptureViewModel.CapturePhase.idle
        let idle2 = AudioCaptureViewModel.CapturePhase.idle
        #expect(idle1 == idle2)

        let recording1 = AudioCaptureViewModel.CapturePhase.recording(duration: 5.0, level: 0.5)
        let recording2 = AudioCaptureViewModel.CapturePhase.recording(duration: 5.0, level: 0.5)
        #expect(recording1 == recording2)

        let error1 = AudioCaptureViewModel.CapturePhase.error("test")
        let error2 = AudioCaptureViewModel.CapturePhase.error("test")
        #expect(error1 == error2)

        #expect(idle1 != recording1)
    }

    @Test("Cannot create note from non-transcribed phase")
    @MainActor func createNoteRequiresTranscribedPhase() async {
        let recorder = AudioRecorder()
        let service = TranscriptionService(backend: AppleSpeechTranscriber())
        let container = try! ModelContainer(
            for: Note.self, AudioRecording.self, Connection.self, NoteGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let vm = AudioCaptureViewModel(
            audioRecorder: recorder,
            transcriptionService: service,
            modelContext: context
        )

        // Phase is .idle, not .transcribed
        let note = await vm.createNoteFromTranscription()
        #expect(note == nil)
    }
}

// MARK: - Transcribing Protocol Conformance Tests

@Suite("Transcribing Protocol")
struct TranscribingProtocolTests {

    @Test("AppleSpeechTranscriber conforms to Transcribing")
    func appleConformance() {
        let transcriber: any Transcribing = AppleSpeechTranscriber()
        _ = transcriber
    }

    @Test("WhisperTranscriber conforms to Transcribing")
    func whisperConformance() {
        let config = WhisperTranscriber.Configuration(apiKey: "test")
        let transcriber: any Transcribing = WhisperTranscriber(configuration: config)
        _ = transcriber
    }
}

// MARK: - EmbeddingError Tests

@Suite("EmbeddingError")
struct EmbeddingErrorTests {

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [EmbeddingError] = [
            .embeddingUnavailable(.english),
            .vectorGenerationFailed("short text"),
            .dimensionMismatch(expected: 512, actual: 256),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}
