// IOSNoteListView.swift — iOS note list with search and swipe actions
// CoppermindIOS

import SwiftUI
import SwiftData
import CoppermindCore

/// Full note list for the iOS Notes tab with search, sort, and swipe actions.
struct IOSNoteListView: View {

    // MARK: - State

    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText: String = ""
    @State private var selectedSort: SortOption = .updated
    @State private var showArchived: Bool = false

    enum SortOption: String, CaseIterable {
        case updated = "Updated"
        case created = "Created"
        case priority = "Priority"
        case title = "Title"
    }

    // MARK: - Computed

    private var filteredNotes: [Note] {
        var notes = allNotes.filter { $0.isArchived == showArchived }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            notes = notes.filter {
                $0.title.lowercased().contains(query)
                || $0.body.lowercased().contains(query)
                || $0.category.displayName.lowercased().contains(query)
            }
        }

        // Pinned first, then sort
        let pinned = notes.filter(\.isPinned)
        var unpinned = notes.filter { !$0.isPinned }

        switch selectedSort {
        case .updated: unpinned.sort { $0.updatedAt > $1.updatedAt }
        case .created: unpinned.sort { $0.createdAt > $1.createdAt }
        case .priority: unpinned.sort { $0.priorityScore > $1.priorityScore }
        case .title: unpinned.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        return pinned + unpinned
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredNotes) { note in
                    NavigationLink(value: note) {
                        IOSNoteRow(note: note)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            modelContext.delete(note)
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
                }
            }
            .searchable(text: $searchText, prompt: "Search notes…")
            .navigationTitle("Notes")
            .navigationDestination(for: Note.self) { note in
                IOSNoteDetailView(note: note)
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $selectedSort) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue)
                            }
                        }

                        Divider()

                        Toggle("Show Archived", isOn: $showArchived)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Sort", selection: $selectedSort) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue)
                            }
                        }

                        Divider()

                        Toggle("Show Archived", isOn: $showArchived)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                #endif

                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button {
                        createNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            .overlay {
                if filteredNotes.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No Notes",
                            systemImage: "doc.text",
                            description: Text("Tap + to create your first note.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func createNote() {
        let note = Note(title: "", body: "", source: .typed)
        modelContext.insert(note)
        try? modelContext.save()
    }
}

// MARK: - Note Row

struct IOSNoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                        .foregroundStyle(.purple)
                }
            }

            Text(note.body.isEmpty ? "No content" : note.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text(note.category.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                Spacer()
                Text(note.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
