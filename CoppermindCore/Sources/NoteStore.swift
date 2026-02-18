// CoppermindCore – NoteStore.swift
// In-memory note repository with auto-categorisation, connection, and clustering.

import Foundation

/// Central façade: stores notes and orchestrates engines.
public final class NoteStore: @unchecked Sendable {
    public private(set) var notes: [Note] = []
    public private(set) var recordings: [AudioRecording] = []

    private let categorizationEngine = CategorizationEngine()
    private let connectionEngine = ConnectionEngine(minimumOverlap: 2)
    private let clusterEngine = ClusterEngine()
    private let priorityRanker = PriorityRanker()

    public init() {}

    // MARK: - Typed note entry

    /// Add a typed note: auto-categorise, compute priority, discover connections.
    @discardableResult
    public func addNote(text: String, createdAt: Date = Date(), deadline: Date? = nil) -> Note {
        let (category, priority) = categorizationEngine.categorize(text)
        var note = Note(
            text: text,
            category: category,
            priority: priority,
            createdAt: createdAt,
            deadline: deadline
        )
        notes.append(note)
        refreshConnections()
        // re-fetch note after connections update
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            note = notes[idx]
        }
        return note
    }

    // MARK: - Audio note entry

    /// Add a note that came through the audio pipeline.
    @discardableResult
    public func addAudioNote(_ note: Note, recording: AudioRecording) -> Note {
        var n = note
        notes.append(n)
        recordings.append(recording)
        refreshConnections()
        if let idx = notes.firstIndex(where: { $0.id == n.id }) {
            n = notes[idx]
        }
        return n
    }

    // MARK: - Category override

    /// Let the user override the auto-assigned category.
    public func overrideCategory(noteID: UUID, to newCategory: NoteCategory) {
        guard let idx = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[idx].category = newCategory
        notes[idx].userOverrodeCategory = true
        // Recalculate priority from the new category baseline
        let (_, basePriority) = categorizationEngine.categorize(notes[idx].text)
        notes[idx].priority = basePriority
        // Adjust for category change
        notes[idx].priority = priorityRanker.score(for: notes[idx])
    }

    // MARK: - Queries

    /// Notes ranked by priority (highest first).
    public func rankedNotes() -> [Note] {
        priorityRanker.ranked(notes)
    }

    /// Cluster notes into thematic groups.
    public func clusters() -> [NoteCluster] {
        clusterEngine.cluster(notes)
    }

    /// Assign cluster names to all notes.
    public func applyClusters() {
        clusterEngine.assignClusters(&notes)
    }

    /// Retrieve a note by ID.
    public func note(byID id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    // MARK: - Internals

    private func refreshConnections() {
        connectionEngine.linkConnections(&notes)
    }
}
