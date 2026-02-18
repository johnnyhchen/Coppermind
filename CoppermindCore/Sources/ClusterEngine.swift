// CoppermindCore – ClusterEngine.swift
// Groups notes into thematic clusters using keyword frequency analysis.

import Foundation

/// Groups notes by keyword similarity and assigns human-readable names.
public struct ClusterEngine: Sendable {

    private let connectionEngine: ConnectionEngine
    /// Minimum number of shared keywords for two notes to be in the same cluster.
    public var affinityThreshold: Int

    public init(affinityThreshold: Int = 2, connectionEngine: ConnectionEngine = ConnectionEngine(minimumOverlap: 2)) {
        self.affinityThreshold = affinityThreshold
        self.connectionEngine = connectionEngine
    }

    // MARK: - Clustering

    /// Cluster notes and return groups with auto-generated names.
    public func cluster(_ notes: [Note]) -> [NoteCluster] {
        guard !notes.isEmpty else { return [] }

        let keywordSets = notes.map { (note: $0, kw: connectionEngine.keywords(from: $0.text)) }
        var visited = Set<UUID>()
        var clusters: [NoteCluster] = []

        for item in keywordSets {
            guard !visited.contains(item.note.id) else { continue }

            // BFS to find all connected notes
            var group: [(note: Note, kw: Set<String>)] = [item]
            var queue = [item]
            visited.insert(item.note.id)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                for candidate in keywordSets {
                    guard !visited.contains(candidate.note.id) else { continue }
                    let shared = current.kw.intersection(candidate.kw)
                    if shared.count >= affinityThreshold {
                        visited.insert(candidate.note.id)
                        group.append(candidate)
                        queue.append(candidate)
                    }
                }
            }

            if group.count >= 2 {
                let allKeywords = group.reduce(into: [String: Int]()) { counts, item in
                    for kw in item.kw { counts[kw, default: 0] += 1 }
                }
                let name = clusterName(from: allKeywords, count: group.count)
                let cluster = NoteCluster(
                    name: name,
                    noteIDs: group.map(\.note.id),
                    topKeywords: topKeywords(allKeywords)
                )
                clusters.append(cluster)
            }
        }
        return clusters
    }

    /// Assign cluster names back to notes.
    public func assignClusters(_ notes: inout [Note]) {
        let clusters = cluster(notes)
        for c in clusters {
            for id in c.noteIDs {
                if let idx = notes.firstIndex(where: { $0.id == id }) {
                    notes[idx].clusterName = c.name
                }
            }
        }
    }

    // MARK: - Naming helpers

    private func topKeywords(_ counts: [String: Int]) -> [String] {
        Array(counts.sorted { $0.value > $1.value }.prefix(5).map(\.key))
    }

    private func clusterName(from counts: [String: Int], count: Int) -> String {
        let top = topKeywords(counts)
        guard let first = top.first else { return "Unnamed Group" }
        let capitalized = first.prefix(1).uppercased() + first.dropFirst()
        if top.count >= 2 {
            let second = top[1].prefix(1).uppercased() + top[1].dropFirst()
            return "\(capitalized) & \(second)"
        }
        return capitalized
    }
}

/// A named group of related notes.
public struct NoteCluster: Sendable, Equatable {
    public let name: String
    public let noteIDs: [UUID]
    public let topKeywords: [String]

    public init(name: String, noteIDs: [UUID], topKeywords: [String]) {
        self.name = name
        self.noteIDs = noteIDs
        self.topKeywords = topKeywords
    }
}
