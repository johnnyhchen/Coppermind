// NoteListView.swift — macOS note list (middle column)
// CoppermindMac

import SwiftUI
import SwiftData
import CoppermindCore

// MARK: - Sort Order

enum NoteSortOrder: String, CaseIterable, Sendable {
    case priorityDesc = "Priority"
    case updatedNewest = "Recently Updated"
    case createdNewest = "Recently Created"
    case alphabetical = "Alphabetical"
}

// MARK: - Note List View

/// Displays a filterable, searchable list of notes in the middle column.
struct NoteListView: View {

    // MARK: - Properties

    let filter: NoteFilter
    @Binding var selectedNote: Note?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.priorityScore, order: .reverse) private var allNotes: [Note]

    @State private var searchText: String = ""
    @State private var sortOrder: NoteSortOrder = .priorityDesc

    // MARK: - Computed

    private var filteredNotes: [Note] {
        var notes = allNotes

        // Apply filter
        switch filter {
        case .all:
            notes = notes.filter { !$0.isArchived }
        case .today:
            let calendar = Calendar.current
            notes = notes.filter { calendar.isDateInToday($0.createdAt) && !$0.isArchived }
        case .highPriority:
            notes = notes.filter { $0.priorityScore >= 80 && !$0.isArchived }
        case .recent:
            let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)
            notes = notes.filter { $0.updatedAt >= threeDaysAgo && !$0.isArchived }
        case .category(let cat):
            notes = notes.filter { $0.category == cat && !$0.isArchived }
        case .pinned:
            notes = notes.filter { $0.isPinned && !$0.isArchived }
        case .archived:
            notes = notes.filter { $0.isArchived }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            notes = notes.filter {
                $0.title.lowercased().contains(query)
                || $0.body.lowercased().contains(query)
            }
        }

        // Apply sort
        switch sortOrder {
        case .priorityDesc:
            notes.sort { $0.priorityScore > $1.priorityScore }
        case .updatedNewest:
            notes.sort { $0.updatedAt > $1.updatedAt }
        case .createdNewest:
            notes.sort { $0.createdAt > $1.createdAt }
        case .alphabetical:
            notes.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        // Pinned notes always float to top (except in pinned-only filter)
        if filter != .pinned {
            let pinned = notes.filter(\.isPinned)
            let unpinned = notes.filter { !$0.isPinned }
            notes = pinned + unpinned
        }

        return notes
    }

    // MARK: - Body

    var body: some View {
        List(filteredNotes, selection: $selectedNote) { note in
            NoteRowView(note: note)
                .tag(note)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteNote(note)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        note.isArchived.toggle()
                        note.touch()
                    } label: {
                        Label(
                            note.isArchived ? "Unarchive" : "Archive",
                            systemImage: "archivebox"
                        )
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        note.isPinned.toggle()
                        note.touch()
                    } label: {
                        Label(
                            note.isPinned ? "Unpin" : "Pin",
                            systemImage: note.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    .tint(.yellow)
                }
                .contextMenu {
                    noteContextMenu(for: note)
                }
        }
        .searchable(text: $searchText, prompt: "Search notes…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Note")
            }

            ToolbarItem {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(NoteSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort Order")
            }
        }
        .overlay {
            if filteredNotes.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "doc.text", description: Text("Create a note to get started."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
            createNote()
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        Button {
            note.isPinned.toggle()
            note.touch()
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }

        Button {
            note.isArchived.toggle()
            note.touch()
        } label: {
            Label(note.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
        }

        Divider()

        Menu("Category") {
            ForEach(NoteCategory.allCases, id: \.self) { cat in
                Button {
                    note.category = cat
                    note.touch()
                } label: {
                    Label(cat.displayName, systemImage: cat.iconName)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            deleteNote(note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func createNote() {
        let note = Note(title: "", body: "", source: .typed)
        modelContext.insert(note)
        selectedNote = note
    }

    private func deleteNote(_ note: Note) {
        if selectedNote?.id == note.id {
            selectedNote = nil
        }
        modelContext.delete(note)
    }
}

// MARK: - Note Row

struct NoteRowView: View {
    let note: Note

    /// Priority dot color based on score ranges.
    private var priorityColor: Color {
        if note.priorityScore >= 100 { return .red }
        if note.priorityScore >= 60 { return .orange }
        if note.priorityScore >= 30 { return .yellow }
        return .gray
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Priority dot
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                // Title row
                HStack {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if note.source == .audio {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Body preview
                Text(note.body.isEmpty ? "No content" : note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Metadata row
                HStack(spacing: 8) {
                    // Category badge
                    Text(note.category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(note.category.accentColor.opacity(0.15))
                        .clipShape(Capsule())

                    Spacer()

                    // Connection count
                    if note.connectionCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                            Text("\(note.connectionCount)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }

                    // Date
                    Text(note.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
