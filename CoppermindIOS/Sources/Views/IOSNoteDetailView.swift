// IOSNoteDetailView.swift — Mobile-optimized note editor / detail screen
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

/// Full-screen, mobile-optimized note editor for iOS.
///
/// Features:
/// - Toolbar: category picker, priority, share, delete
/// - Inline audio player for attached recordings
/// - Horizontally-scrolling connection cards
/// - Transcription editing with low-confidence highlighting
/// - Dynamic Type + dark mode support
struct IOSNoteDetailView: View {

    // MARK: - Properties

    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showDeleteConfirmation: Bool = false
    @State private var showCategoryPicker: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var editingTranscription: AudioRecording?
    @State private var transcriptionDraft: String = ""
    @FocusState private var isBodyFocused: Bool

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: Title
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.title2.bold())
                    .onChange(of: note.title) { _, _ in note.touch() }

                // MARK: Metadata Bar
                metadataSection

                Divider()

                // MARK: Body Editor
                TextField("Start writing\u{2026}", text: $note.body, axis: .vertical)
                    .font(.body)
                    .lineLimit(nil)
                    .focused($isBodyFocused)
                    .onChange(of: note.body) { _, _ in note.touch() }

                // MARK: Task Fields
                if note.isTask {
                    taskFieldsSection
                }

                // MARK: Bucket Fields
                if note.category == .bucket {
                    bucketFieldsSection
                }

                Divider()

                // MARK: Audio Recordings
                if !note.audioRecordings.isEmpty {
                    audioSection
                }

                // MARK: Connections (horizontal scroll)
                if !note.allConnections.isEmpty {
                    connectionsSection
                }
            }
            .padding()
        }
        .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Leading: category button
            ToolbarItem(placement: .topBarLeading) {
                categoryButton
            }

            // Trailing: priority, share, more
            ToolbarItemGroup(placement: .topBarTrailing) {
                toolbarItems
            }

            // Keyboard done
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isBodyFocused = false }
            }
        }
        .confirmationDialog("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(note)
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showCategoryPicker) {
            categoryPickerSheet
        }
        .sheet(item: $editingTranscription) { recording in
            transcriptionEditor(for: recording)
        }
    }

    // MARK: - Category Button

    private var categoryButton: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: note.category.iconName)
                Text(note.category.displayName)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(note.category.accentColor.opacity(0.15))
            .foregroundStyle(note.category.accentColor)
            .clipShape(Capsule())
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label(note.source.rawValue.capitalized, systemImage: note.source == .audio ? "waveform" : "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(note.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Priority bar
            HStack(spacing: 8) {
                Text("Priority")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: min(note.priorityScore / 200.0, 1.0))
                    .tint(priorityColor)
                Text("\(Int(note.priorityScore))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var priorityColor: Color {
        if note.priorityScore > 150 { return .red }
        if note.priorityScore > 50 { return .orange }
        return .green
    }

    // MARK: - Task Fields

    private var taskFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Details")
                .font(.headline)

            // Urgency picker
            HStack {
                Text("Urgency")
                    .font(.subheadline)
                Spacer()
                Picker("Urgency", selection: Binding(
                    get: { note.urgency ?? .medium },
                    set: { note.urgency = $0; note.touch() }
                )) {
                    ForEach(Urgency.allCases, id: \.self) { u in
                        Text(u.rawValue.capitalized).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            // Due date
            HStack {
                Text("Due Date")
                    .font(.subheadline)
                Spacer()
                if let due = note.dueDate {
                    DatePicker("", selection: Binding(
                        get: { due },
                        set: { note.dueDate = $0; note.touch() }
                    ), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    Button {
                        note.dueDate = nil; note.touch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Set Due Date") {
                        note.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)
                        note.touch()
                    }
                    .font(.subheadline)
                }
            }

            // Completed toggle
            Toggle("Completed", isOn: Binding(
                get: { note.isCompleted ?? false },
                set: {
                    if $0 { note.completeTask() } else { note.reopenTask() }
                }
            ))
            .font(.subheadline)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bucket Fields

    private var bucketFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bucket Details")
                .font(.headline)

            // Bucket type picker
            Picker("Type", selection: Binding(
                get: { note.bucketType ?? .other },
                set: { note.bucketType = $0; note.touch() }
            )) {
                ForEach(BucketType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized).tag(type)
                }
            }

            // URL
            TextField("URL", text: Binding(
                get: { note.url ?? "" },
                set: { note.url = $0.isEmpty ? nil : $0; note.touch() }
            ))
            .font(.subheadline)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif

            HStack {
                // Estimated price
                TextField("Price", value: Binding(
                    get: { note.estimatedPrice },
                    set: { note.estimatedPrice = $0; note.touch() }
                ), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif

                // Location
                TextField("Location", text: Binding(
                    get: { note.location ?? "" },
                    set: { note.location = $0.isEmpty ? nil : $0; note.touch() }
                ))
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)
            }

            // Star toggle
            Toggle(isOn: Binding(
                get: { note.isStarred },
                set: { note.isStarred = $0; note.touch() }
            )) {
                Label("Starred", systemImage: note.isStarred ? "star.fill" : "star")
            }
            .font(.subheadline)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Audio (\(note.audioRecordings.count))")
                .font(.headline)

            ForEach(note.audioRecordings) { recording in
                AudioPlayerCard(recording: recording) {
                    editingTranscription = recording
                    transcriptionDraft = recording.transcriptionText ?? ""
                }
            }
        }
    }

    // MARK: - Connections (Horizontal Scroll)

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connections (\(note.allConnections.count))")
                    .font(.headline)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(note.allConnections) { connection in
                        ConnectionCard(connection: connection, currentNote: note)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Toolbar Items

    @ViewBuilder
    private var toolbarItems: some View {
        // Pin
        Button {
            note.isPinned.toggle()
            note.touch()
        } label: {
            Image(systemName: note.isPinned ? "pin.slash.fill" : "pin")
        }
        .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")

        // Share
        ShareLink(item: shareText) {
            Image(systemName: "square.and.arrow.up")
        }

        // More menu: archive, delete
        Menu {
            Button {
                note.isArchived.toggle()
                note.touch()
            } label: {
                Label(
                    note.isArchived ? "Unarchive" : "Archive",
                    systemImage: note.isArchived ? "tray.and.arrow.down" : "archivebox"
                )
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var shareText: String {
        var parts: [String] = []
        if !note.title.isEmpty { parts.append(note.title) }
        if !note.body.isEmpty { parts.append(note.body) }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Category Picker Sheet

    private var categoryPickerSheet: some View {
        NavigationStack {
            List(NoteCategory.allCases, id: \.self) { cat in
                Button {
                    note.category = cat
                    note.touch()
                    showCategoryPicker = false
                } label: {
                    HStack {
                        Image(systemName: cat.iconName)
                            .foregroundStyle(cat.accentColor)
                            .frame(width: 28)
                        Text(cat.displayName)
                        Spacer()
                        if note.category == cat {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showCategoryPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Transcription Editor Sheet

    private func transcriptionEditor(for recording: AudioRecording) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Edit Transcription")
                    .font(.headline)

                TextEditor(text: $transcriptionDraft)
                    .font(.body)
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 200)

                if let conf = recording.transcriptionConfidence {
                    HStack {
                        Text("Confidence: \(Int(conf * 100))%")
                            .font(.caption)
                            .foregroundStyle(conf < 0.6 ? .red : .secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingTranscription = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        recording.transcriptionText = transcriptionDraft
                        recording.isEdited = true
                        editingTranscription = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    let recording: AudioRecording
    let onEditTranscription: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Compact header
            HStack(spacing: 10) {
                // Play button placeholder
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.filePath)
                        .font(.caption)
                        .lineLimit(1)
                    Text(formatDuration(recording.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Transcription status
                if recording.hasTranscription {
                    HStack(spacing: 4) {
                        Image(systemName: recording.isEdited ? "pencil.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(recording.isEdited ? .blue : .green)
                            .font(.caption)
                        Button("Edit") {
                            onEditTranscription()
                        }
                        .font(.caption)
                    }
                }

                // Expand toggle
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Expanded: transcription text
            if isExpanded, let text = recording.transcriptionText, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    let connection: Connection
    let currentNote: Note

    private var otherNote: Note {
        connection.otherNote(from: currentNote)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Other note title
            Text(otherNote.title.isEmpty ? "Untitled" : otherNote.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            // Category + strength
            HStack(spacing: 6) {
                Image(systemName: otherNote.category.iconName)
                    .font(.caption2)
                    .foregroundStyle(otherNote.category.accentColor)
                Text(otherNote.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(connection.strength * 100))%")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.blue)
            }

            // Relationship type
            Text(connection.relationshipType)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .frame(width: 180)
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connected to \(otherNote.title), \(Int(connection.strength * 100)) percent match")
    }
}
