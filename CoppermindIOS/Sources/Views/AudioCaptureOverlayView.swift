// AudioCaptureOverlayView.swift — iOS audio recording sheet
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

/// A sheet presented for audio recording with:
/// - Pulsing record button
/// - Live waveform visualization
/// - Live transcription display
/// - Stop → Edit → Confirm flow
/// - Category suggestion chip
struct AudioCaptureOverlayView: View {

    // MARK: - State

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: CapturePhase = .idle
    @State private var recordingDuration: TimeInterval = 0
    @State private var audioLevel: Float = 0
    @State private var transcribedText: String = ""
    @State private var noteTitle: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var suggestedCategory: NoteCategory = .idea
    @State private var selectedCategory: NoteCategory?
    @State private var waveformSamples: [Float] = []
    @State private var liveTranscription: String = ""
    @State private var pulseScale: CGFloat = 1.0

    /// Task for simulating recording state updates.
    @State private var durationTask: Task<Void, Never>?

    enum CapturePhase: Equatable {
        case idle
        case recording
        case processing
        case transcribed
        case error
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // MARK: Visualization
                audioVisualization

                // MARK: Duration / Status
                statusDisplay

                // MARK: Live Transcription (during recording)
                if phase == .recording && !liveTranscription.isEmpty {
                    liveTranscriptionBubble
                }

                // MARK: Transcription Preview (after stop)
                if phase == .transcribed {
                    transcriptionEditor
                }

                // MARK: Processing
                if phase == .processing {
                    processingIndicator
                }

                // MARK: Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // MARK: Category Suggestion Chip
                if phase == .transcribed {
                    categorySuggestionChips
                }

                Spacer()

                // MARK: Controls
                controlButtons
            }
            .padding()
            .navigationTitle("Audio Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopTimers()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .recording)
    }

    // MARK: - Audio Visualization

    private var audioVisualization: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .fill(.blue.opacity(0.07))
                .frame(width: 200, height: 200)
                .scaleEffect(phase == .recording ? pulseScale : 1.0)

            // Middle ring responds to audio level
            Circle()
                .fill(.blue.opacity(0.15))
                .frame(width: 140, height: 140)
                .scaleEffect(phase == .recording ? 1.0 + CGFloat(audioLevel) * 0.25 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: audioLevel)

            // Waveform bars (live during recording)
            if phase == .recording && !waveformSamples.isEmpty {
                waveformView
            }

            // Center icon
            Image(systemName: phaseIcon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(phaseColor)
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: phase == .recording
                )
        }
        .frame(height: 220)
        .onChange(of: phase) { _, newPhase in
            if newPhase == .recording {
                startPulseAnimation()
            }
        }
    }

    /// Live waveform bars rendered from sample data.
    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(Array(waveformSamples.suffix(30).enumerated()), id: \.offset) { _, sample in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.blue.opacity(0.6))
                    .frame(width: 3, height: max(4, CGFloat(sample) * 60))
                    .animation(.easeOut(duration: 0.08), value: sample)
            }
        }
        .frame(maxWidth: 120, maxHeight: 60)
        .offset(y: 85)
    }

    private var phaseIcon: String {
        switch phase {
        case .idle:        return "mic.circle"
        case .recording:   return "mic.fill"
        case .processing:  return "waveform.circle"
        case .transcribed: return "checkmark.circle"
        case .error:       return "exclamationmark.triangle"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .idle:        return .secondary
        case .recording:   return .red
        case .processing:  return .blue
        case .transcribed: return .green
        case .error:       return .red
        }
    }

    // MARK: - Status Display

    private var statusDisplay: some View {
        Group {
            switch phase {
            case .idle:
                Text("Tap to record")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .recording:
                Text(formatDuration(recordingDuration))
                    .font(.system(size: 44, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            case .processing:
                EmptyView()
            case .transcribed:
                EmptyView()
            case .error:
                EmptyView()
            }
        }
    }

    // MARK: - Live Transcription Bubble

    private var liveTranscriptionBubble: some View {
        Text(liveTranscription)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .lineLimit(3)
            .animation(.easeInOut, value: liveTranscription)
    }

    // MARK: - Transcription Editor

    private var transcriptionEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Note title (optional)", text: $noteTitle)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                TextEditor(text: $transcribedText)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
            }
            .frame(maxHeight: 160)
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("\(transcribedText.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(formatDuration(recordingDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Transcribing\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Category Suggestion Chips

    private var categorySuggestionChips: some View {
        VStack(spacing: 8) {
            Text("Category")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteCategory.allCases, id: \.self) { cat in
                        let isSelected = (selectedCategory ?? suggestedCategory) == cat
                        let isSuggested = cat == suggestedCategory && selectedCategory == nil

                        Button {
                            selectedCategory = cat
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.iconName)
                                    .font(.caption2)
                                Text(cat.displayName)
                                    .font(.caption.weight(.medium))
                                if isSuggested {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? cat.accentColor.opacity(0.2) : Color(.systemGray6))
                            .foregroundStyle(isSelected ? cat.accentColor : .secondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? cat.accentColor : .clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 32) {
            switch phase {
            case .idle:
                recordActionButton(icon: "mic.fill", color: .red, label: "Record") {
                    startRecording()
                }

            case .recording:
                recordActionButton(icon: "stop.fill", color: .red, label: "Stop") {
                    stopRecording()
                }

            case .processing:
                EmptyView()

            case .transcribed:
                recordActionButton(icon: "arrow.counterclockwise", color: .secondary, label: "Retry") {
                    reset()
                }
                recordActionButton(icon: "checkmark", color: .blue, label: "Save") {
                    saveNote()
                }
                .disabled(isSaving)

            case .error:
                recordActionButton(icon: "arrow.counterclockwise", color: .secondary, label: "Retry") {
                    reset()
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func recordActionButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(color))
                    .shadow(color: color.opacity(0.3), radius: 6, y: 3)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func startRecording() {
        phase = .recording
        errorMessage = nil
        recordingDuration = 0
        waveformSamples = []
        liveTranscription = ""

        // Simulate duration tracking + waveform
        durationTask = Task { @MainActor in
            while !Task.isCancelled {
                recordingDuration += 0.1
                audioLevel = Float.random(in: 0.1...0.8)
                waveformSamples.append(audioLevel)
                if waveformSamples.count > 60 {
                    waveformSamples.removeFirst()
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func stopRecording() {
        stopTimers()
        phase = .processing

        // Simulated transcription
        Task {
            try? await Task.sleep(for: .seconds(1))
            transcribedText = liveTranscription.isEmpty
                ? "Transcription will appear here after processing."
                : liveTranscription
            suggestedCategory = .idea
            phase = .transcribed
        }
    }

    private func saveNote() {
        isSaving = true

        let category = selectedCategory ?? suggestedCategory
        let note = Note(
            title: noteTitle.isEmpty ? "Audio Note" : noteTitle,
            body: transcribedText,
            category: category,
            source: .audio
        )
        modelContext.insert(note)

        isSaving = false
        dismiss()
    }

    private func reset() {
        stopTimers()
        phase = .idle
        recordingDuration = 0
        audioLevel = 0
        transcribedText = ""
        noteTitle = ""
        errorMessage = nil
        waveformSamples = []
        liveTranscription = ""
        selectedCategory = nil
    }

    private func stopTimers() {
        durationTask?.cancel()
        durationTask = nil
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
        }
    }

    // MARK: - Formatting

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let centiseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
