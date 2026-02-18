// ConnectionDiscovery.swift — Discovers semantic connections between notes
// CoppermindCore

import Foundation
import SwiftData

/// Orchestrates the discovery of connections between notes using
/// semantic similarity, keyword overlap (Jaccard), and temporal proximity.
///
/// Includes a 2-second debounce to avoid redundant work after rapid edits.
public actor ConnectionDiscovery {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Minimum combined score to create a connection.
        public let similarityThreshold: Double
        /// Maximum number of connections per note.
        public let maxConnectionsPerNote: Int
        /// Whether to create connections as suggested (vs. automatic).
        public let suggestOnly: Bool
        /// Temporal proximity window in seconds (default 30 min = 1800 s).
        public let temporalWindowSeconds: TimeInterval
        /// Score contribution when two notes are within the temporal window.
        public let temporalProximityBonus: Double
        /// Debounce interval in seconds after note creation/edit.
        public let debounceInterval: TimeInterval

        public init(
            similarityThreshold: Double = 0.5,
            maxConnectionsPerNote: Int = 10,
            suggestOnly: Bool = false,
            temporalWindowSeconds: TimeInterval = 30 * 60,
            temporalProximityBonus: Double = 0.2,
            debounceInterval: TimeInterval = 2.0
        ) {
            self.similarityThreshold = similarityThreshold
            self.maxConnectionsPerNote = maxConnectionsPerNote
            self.suggestOnly = suggestOnly
            self.temporalWindowSeconds = temporalWindowSeconds
            self.temporalProximityBonus = temporalProximityBonus
            self.debounceInterval = debounceInterval
        }
    }

    // MARK: - Dependencies

    private let embeddingService: EmbeddingService
    private let configuration: Configuration

    /// Tracks the last time a discovery was requested (for debouncing).
    private var lastDiscoveryRequestTime: Date?
    /// Pending debounce task — cancelled if a new request arrives.
    private var pendingDebounceID: UUID?

    // MARK: - Init

    public init(
        embeddingService: EmbeddingService,
        configuration: Configuration = Configuration()
    ) {
        self.embeddingService = embeddingService
        self.configuration = configuration
    }

    // MARK: - Discovery

    /// Discover new connections for a single note against a corpus.
    ///
    /// Scoring combines three signals:
    /// 1. **Semantic similarity** (cosine of embeddings) — must exceed threshold alone.
    /// 2. **Keyword overlap** (Jaccard index of lowercased word sets).
    /// 3. **Temporal proximity** — bonus when notes were created within 30 minutes.
    ///
    /// Connections are deduplicated: if a pair already exists the strength is updated
    /// to the maximum of old and new values.
    ///
    /// - Parameters:
    ///   - note: The note to find connections for.
    ///   - corpus: All notes to compare against.
    ///   - existingConnections: Already-established connections to detect duplicates.
    /// - Returns: Newly discovered connections (not yet persisted).
    public func discoverConnections(
        for note: Note,
        in corpus: [Note],
        existingConnections: [Connection] = []
    ) async throws -> [Connection] {
        let noteText = noteTextContent(note)
        let noteEmbedding = try await embeddingService.embed(noteText)
        let noteTokens = tokenize(noteText)

        // Build set of note-IDs already connected to `note` for dedup.
        let existingPairIDs: Set<UUID> = Set(
            existingConnections.flatMap { conn -> [UUID] in
                if conn.sourceNote.id == note.id { return [conn.targetNote.id] }
                if conn.targetNote.id == note.id { return [conn.sourceNote.id] }
                return []
            }
        )

        // Map existing connections by target for strength-update dedup
        var existingByTarget: [UUID: Connection] = [:]
        for conn in existingConnections {
            if conn.sourceNote.id == note.id {
                existingByTarget[conn.targetNote.id] = conn
            } else if conn.targetNote.id == note.id {
                existingByTarget[conn.sourceNote.id] = conn
            }
        }

        var candidates: [(note: Note, score: Double)] = []

        for candidate in corpus {
            guard candidate.id != note.id else { continue }

            let candidateText = noteTextContent(candidate)
            let candidateEmbedding = try await embeddingService.embed(candidateText)

            // -- Signal 1: Semantic similarity --
            let semantic = await embeddingService.similarity(noteEmbedding, candidateEmbedding)

            // Gate: semantic similarity alone must exceed threshold
            guard semantic >= configuration.similarityThreshold else { continue }

            // -- Signal 2: Keyword overlap (Jaccard) --
            let candidateTokens = tokenize(candidateText)
            let jaccard = jaccardIndex(noteTokens, candidateTokens)

            // -- Signal 3: Temporal proximity --
            let timeDelta = abs(note.createdAt.timeIntervalSince(candidate.createdAt))
            let temporalScore: Double = timeDelta <= configuration.temporalWindowSeconds
                ? configuration.temporalProximityBonus
                : 0.0

            // Combined score: weighted blend, clamped to [0, 1]
            let combined = min(semantic * 0.6 + jaccard * 0.2 + temporalScore, 1.0)

            // -- Dedup: update existing connection strength if this score is higher --
            if let existing = existingByTarget[candidate.id] {
                if combined > existing.strength {
                    existing.strength = combined
                }
                continue  // don't create a duplicate
            }

            candidates.append((note: candidate, score: combined))
        }

        candidates.sort { $0.score > $1.score }
        let topCandidates = candidates.prefix(configuration.maxConnectionsPerNote)

        return topCandidates.map { candidate in
            Connection(
                sourceNote: note,
                targetNote: candidate.note,
                strength: candidate.score,
                createdBy: .auto
            )
        }
    }

    /// Run full discovery across all notes, returning all new connections.
    public func discoverAll(
        notes: [Note],
        existingConnections: [Connection] = []
    ) async throws -> [Connection] {
        var allNewConnections: [Connection] = []

        for note in notes {
            let newConnections = try await discoverConnections(
                for: note,
                in: notes,
                existingConnections: existingConnections + allNewConnections
            )
            allNewConnections.append(contentsOf: newConnections)
        }

        return allNewConnections
    }

    // MARK: - Debounced Discovery

    /// Request connection discovery with a 2-second debounce.
    ///
    /// If called again within `debounceInterval` the previous pending request is
    /// logically cancelled (via UUID mismatch). Only the last request fires.
    ///
    /// - Parameters:
    ///   - note: The note to discover connections for.
    ///   - corpus: All notes to compare against.
    ///   - existingConnections: Already-established connections.
    ///   - handler: Callback with discovered connections (called on completion).
    /// - Returns: The discovered connections after the debounce fires, or an empty
    ///   array if the request was superseded.
    public func discoverConnectionsDebounced(
        for note: Note,
        in corpus: [Note],
        existingConnections: [Connection] = []
    ) async throws -> [Connection] {
        let requestID = UUID()
        pendingDebounceID = requestID
        lastDiscoveryRequestTime = Date()

        // Wait for the debounce interval
        try await Task.sleep(for: .seconds(configuration.debounceInterval))

        // If another request arrived while we were sleeping, bail out.
        guard pendingDebounceID == requestID else {
            return []
        }

        return try await discoverConnections(
            for: note,
            in: corpus,
            existingConnections: existingConnections
        )
    }

    // MARK: - Text & Token Helpers

    /// Combine note title and body for embedding / token extraction.
    private func noteTextContent(_ note: Note) -> String {
        [note.title, note.body].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Tokenize text into a set of lowercased words for Jaccard computation.
    private func tokenize(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    /// Jaccard index: |A intersection B| / |A union B|.
    func jaccardIndex(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }
}
