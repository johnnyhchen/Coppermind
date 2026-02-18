// CoppermindCore – ConnectionEngine.swift
// Discovers semantic connections between notes via keyword overlap.

import Foundation

/// Discovers connections between notes based on shared significant keywords.
public struct ConnectionEngine: Sendable {

    /// Words too common to be meaningful.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be",
        "been", "being", "have", "has", "had", "do", "does",
        "did", "will", "would", "could", "should", "may",
        "might", "shall", "can", "need", "to", "of", "in",
        "for", "on", "with", "at", "by", "from", "as", "into",
        "about", "like", "through", "after", "over", "between",
        "out", "up", "down", "off", "then", "than", "too",
        "very", "just", "but", "and", "or", "nor", "not",
        "so", "if", "that", "this", "it", "its", "i", "my",
        "me", "we", "our", "you", "your", "he", "she",
        "they", "them", "their", "what", "which", "who",
        "when", "where", "how", "all", "each", "every",
        "both", "few", "more", "most", "some", "any", "no",
        "only", "own", "same", "such"
    ]

    /// Minimum keyword overlap to form a connection.
    public var minimumOverlap: Int

    public init(minimumOverlap: Int = 2) {
        self.minimumOverlap = minimumOverlap
    }

    // MARK: - Public API

    /// Extract significant keywords from text.
    public func keywords(from text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }
        return Set(words)
    }

    /// Return pairs of note IDs that share ≥ minimumOverlap keywords.
    public func discoverConnections(among notes: [Note]) -> [(UUID, UUID, Set<String>)] {
        var result: [(UUID, UUID, Set<String>)] = []
        let keywordSets = notes.map { (note: $0, kw: keywords(from: $0.text)) }

        for i in 0..<keywordSets.count {
            for j in (i + 1)..<keywordSets.count {
                let shared = keywordSets[i].kw.intersection(keywordSets[j].kw)
                if shared.count >= minimumOverlap {
                    result.append((keywordSets[i].note.id, keywordSets[j].note.id, shared))
                }
            }
        }
        return result
    }

    /// Mutates notes in-place to record discovered connections.
    public func linkConnections(_ notes: inout [Note]) {
        let connections = discoverConnections(among: notes)
        for (idA, idB, _) in connections {
            if let a = notes.firstIndex(where: { $0.id == idA }),
               let b = notes.firstIndex(where: { $0.id == idB }) {
                if !notes[a].connectionIDs.contains(idB) {
                    notes[a].connectionIDs.append(idB)
                }
                if !notes[b].connectionIDs.contains(idA) {
                    notes[b].connectionIDs.append(idA)
                }
            }
        }
    }
}
