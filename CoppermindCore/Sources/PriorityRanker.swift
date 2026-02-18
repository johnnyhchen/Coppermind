// CoppermindCore – PriorityRanker.swift
// Computes a composite priority score and produces a ranked ordering.

import Foundation

/// Calculates and sorts notes by composite priority.
public struct PriorityRanker: Sendable {

    public init() {}

    // MARK: - Scoring

    /// Compute composite priority for a single note.
    public func score(for note: Note, connectionCount: Int = 0) -> Double {
        var s = note.priority

        // Overdue tasks get a massive boost
        if note.category == .task, let deadline = note.deadline, deadline < Date() {
            s += 40
        }

        // Connection richness bonus
        let connections = max(connectionCount, note.connectionIDs.count)
        s += Double(connections) * 5

        // Category base bonuses
        switch note.category {
        case .task:    s += 10
        case .project: s += 5
        case .idea:    s += 2
        case .bucket:  s += 0
        }

        // Recency bonus (notes < 24 h old get up to +8)
        let age = Date().timeIntervalSince(note.createdAt)
        if age < 86_400 {
            s += 8 * (1.0 - age / 86_400)
        }

        return s
    }

    /// Rank notes from highest to lowest priority.
    public func ranked(_ notes: [Note]) -> [Note] {
        notes.sorted { score(for: $0) > score(for: $1) }
    }
}
