// NoteListViewModel.swift — Drives the note list / inbox UI
// CoppermindCore

import Foundation
import Observation
import SwiftData

/// ViewModel for the note list / inbox view.
/// Manages filtering, sorting, search, and batch operations.
@Observable
@MainActor
public final class NoteListViewModel {

    // MARK: - Sort & Filter

    public enum SortOrder: String, CaseIterable, Sendable {
        case updatedNewest = "Recently Updated"
        case createdNewest = "Recently Created"
        case priority = "Priority"
        case alphabetical = "Alphabetical"
    }

    public enum Filter: Equatable, Sendable {
        case all
        case category(NoteCategory)
        case pinned
        case archived
        case source(NoteSource)
    }

    // MARK: - State

    public var notes: [Note] = []
    public var searchText: String = ""
    public var sortOrder: SortOrder = .updatedNewest
    public var activeFilter: Filter = .all
    public var isLoading: Bool = false
    public var errorMessage: String?

    /// Available categories derived from all notes.
    public var availableCategories: [NoteCategory] {
        Array(Set(notes.map(\.category))).sorted { $0.rawValue < $1.rawValue }
    }

    /// Filtered and sorted notes for display.
    public var displayedNotes: [Note] {
        var result = notes

        // Apply filter
        switch activeFilter {
        case .all:
            result = result.filter { !$0.isArchived }
        case .category(let cat):
            result = result.filter { $0.category == cat }
        case .pinned:
            result = result.filter { $0.isPinned }
        case .archived:
            result = result.filter { $0.isArchived }
        case .source(let source):
            result = result.filter { $0.source == source }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query)
                || $0.body.lowercased().contains(query)
            }
        }

        // Apply sort
        switch sortOrder {
        case .updatedNewest:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .createdNewest:
            result.sort { $0.createdAt > $1.createdAt }
        case .priority:
            result.sort { $0.priorityScore > $1.priorityScore }
        case .alphabetical:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        // Pinned notes always float to top (except in pinned-only filter)
        if activeFilter != .pinned {
            let pinned = result.filter(\.isPinned)
            let unpinned = result.filter { !$0.isPinned }
            result = pinned + unpinned
        }

        return result
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let priorityScorer: PriorityScorer

    // MARK: - Init

    public init(modelContext: ModelContext, priorityScorer: PriorityScorer = PriorityScorer()) {
        self.modelContext = modelContext
        self.priorityScorer = priorityScorer
    }

    // MARK: - Data Loading

    /// Fetch all notes from the model context.
    public func loadNotes() async {
        isLoading = true
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            notes = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - CRUD Operations

    /// Create a new note.
    public func createNote(title: String = "", body: String = "", source: NoteSource = .typed) -> Note {
        let note = Note(title: title, body: body, source: source)
        modelContext.insert(note)
        notes.append(note)
        return note
    }

    /// Delete a note.
    public func deleteNote(_ note: Note) {
        modelContext.delete(note)
        notes.removeAll { $0.id == note.id }
    }

    /// Delete notes at index set offsets (for List onDelete).
    public func deleteNotes(at offsets: IndexSet) {
        let displayed = displayedNotes
        for index in offsets {
            let note = displayed[index]
            deleteNote(note)
        }
    }

    /// Toggle pin state.
    public func togglePin(_ note: Note) {
        note.isPinned.toggle()
        note.touch()
    }

    /// Archive a note.
    public func archiveNote(_ note: Note) {
        note.isArchived = true
        note.touch()
    }

    /// Unarchive a note.
    public func unarchiveNote(_ note: Note) {
        note.isArchived = false
        note.touch()
    }

    // MARK: - Batch Operations

    /// Re-score priorities for all loaded notes.
    public func rescorePriorities() {
        priorityScorer.scoreAll(notes)
    }
}
