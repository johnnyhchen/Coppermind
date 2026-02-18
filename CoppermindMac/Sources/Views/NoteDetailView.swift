// NoteDetailView.swift — macOS note editor / detail pane
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

/// Full note editor displayed in the detail column.
/// Supports title/body editing, category badge, audio player, connections panel, metadata footer.
struct NoteDetailView: View {

    // MARK: - Properties

    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext

    @State private var showConnections: Bool = false
    @State private var showAudioPlayer: Bool = false
    @State private var isClassifying: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Title
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.title)
                    .textFieldStyle(.plain)
                    .onChange(of: note.title) { _, _ in
                        note.touch()
                    }

                // MARK: Category Badge
                categoryBadge

                Divider()

                // MARK: Body Editor
                TextEditor(text: $note.body)
                    .font(.body)
                    .frame(minHeight: 300)
                    .scrollContentBackground(.hidden)
                    .onChange(of: note.body) { _, _ in
                        note.touch()
                    }

                // MARK: Audio Player
                if !note.audioRecordings.isEmpty {
                    audioSection
                }

                Divider()

                // MARK: Connections Panel
                if showConnections {
                    ConnectionsPanelView(note: note)
                }

                // MARK: Metadata Footer
                metadataFooter
            }
            .padding()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
        .navigationSubtitle(note.category.displayName)
    }

    // MARK: - Category Badge

    private var categoryBadge: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(NoteCategory.allCases, id: \.self) { cat in
                    Button {
                        note.category = cat
                        note.touch()
                    } label: {
                        Label(cat.displayName, systemImage: cat.iconName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: note.category.iconName)
                    Text(note.category.displayName)
                }
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(note.category.accentColor.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if note.source == .audio {
                Label("Audio", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.blue)
                Text("Audio Recordings")
                    .font(.headline)
            }

            ForEach(note.audioRecordings) { recording in
                AudioRecordingRow(recording: recording)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    // MARK: - Metadata Footer

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack(spacing: 16) {
                Label(note.source.rawValue.capitalized, systemImage: note.source == .audio ? "waveform" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Priority: \(Int(note.priorityScore))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Views: \(note.viewCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Connections: \(note.connectionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Created \(note.createdAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Updated \(note.updatedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            note.isPinned.toggle()
            note.touch()
        } label: {
            Image(systemName: note.isPinned ? "pin.slash" : "pin")
        }
        .help(note.isPinned ? "Unpin" : "Pin")

        Button {
            showConnections.toggle()
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
        }
        .help("Toggle Connections")

        Button {
            Task {
                isClassifying = true
                let classifier = CategoryClassifier()
                await classifier.classifyAndApply(to: note)
                isClassifying = false
            }
        } label: {
            if isClassifying {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "tag")
            }
        }
        .help("Auto-Classify")
        .disabled(isClassifying)
    }
}

// MARK: - Audio Recording Row

struct AudioRecordingRow: View {
    let recording: AudioRecording

    private var formattedDuration: String {
        let totalSeconds = Int(recording.duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.filePath)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if recording.hasTranscription {
                        Label("Transcribed", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    if let confidence = recording.transcriptionConfidence {
                        Text("\(Int(confidence * 100))% confidence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Text(recording.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
