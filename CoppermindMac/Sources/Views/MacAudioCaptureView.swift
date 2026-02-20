// MacAudioCaptureView.swift — macOS audio capture sheet
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

struct MacAudioCaptureView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AudioCaptureViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    captureContent(viewModel)
                } else {
                    ProgressView("Preparing…")
                }
            }
            .padding()
            .navigationTitle("Audio Capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelAndDismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .onAppear { setupViewModel() }
        .onDisappear {
            Task { await viewModel?.cancelRecording() }
        }
    }

    private func setupViewModel() {
        guard viewModel == nil else { return }
        let vm = AudioCaptureViewModel(
            audioRecorder: AudioRecorder(),
            transcriptionService: TranscriptionService(backend: AppleSpeechTranscriber()),
            modelContext: modelContext
        )
        viewModel = vm
        Task { await vm.prepare() }
    }

    private func cancelAndDismiss() {
        Task {
            if let viewModel {
                await viewModel.cancelRecording()
            }
            dismiss()
        }
    }

    @ViewBuilder
    private func captureContent(_ viewModel: AudioCaptureViewModel) -> some View {
        switch viewModel.phase {
        case .idle:
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing audio capture…")
                    .foregroundStyle(.secondary)
            }
        case .permissionRequired:
            VStack(spacing: 12) {
                Image(systemName: "mic.slash")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Microphone or Speech permission required.")
                    .font(.headline)
                Text("Enable permissions in System Settings to record audio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await viewModel.prepare() }
                }
            }
        case .readyToRecord:
            VStack(spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.purple)
                Text("Ready to record")
                    .font(.title3.bold())
                Button {
                    Task { await viewModel.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: 340)
        case .recording(let duration, let level):
            VStack(spacing: 16) {
                Text("Recording")
                    .font(.title2.bold())
                Text(formattedDuration(duration))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Input Level")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(max(0, min(level, 1))))
                        .tint(.red)
                }

                Button {
                    Task { await viewModel.stopRecording() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .frame(maxWidth: 340)
        case .processing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Transcribing…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        case .transcribed:
            transcribedView(viewModel)
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                Text("Something went wrong")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    viewModel.reset()
                    Task { await viewModel.prepare() }
                }
            }
        }
    }

    private func transcribedView(_ viewModel: AudioCaptureViewModel) -> some View {
        @Bindable var viewModel = viewModel

        return VStack(alignment: .leading, spacing: 12) {
            Text("Review transcription")
                .font(.headline)

            TextField("Title", text: $viewModel.noteTitle)
                .textFieldStyle(.roundedBorder)

            if let classification = viewModel.classificationResult {
                categoryChip(category: classification.category, confidence: classification.confidence)
            } else if let category = viewModel.suggestedCategory {
                categoryChip(category: category, confidence: nil)
            }

            TextEditor(text: $viewModel.transcribedText)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                )

            HStack {
                Button("Discard") {
                    Task {
                        await viewModel.cancelRecording()
                        dismiss()
                    }
                }

                Spacer()

                Button {
                    Task {
                        if await viewModel.createNoteFromTranscription() != nil {
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isCreatingNote {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isCreatingNote)
            }
        }
    }

    private func categoryChip(category: NoteCategory, confidence: Double?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.iconName)
            Text(category.displayName)
                .font(.caption)
            if let confidence {
                Text("(\(Int(confidence * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.accentColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
