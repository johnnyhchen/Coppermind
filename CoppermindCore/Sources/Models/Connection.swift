// Connection.swift — Semantic edge between two notes
// CoppermindCore

import Foundation
import SwiftData

// MARK: - ConnectionCreator

/// How a connection was established.
public enum ConnectionCreator: String, Codable, Sendable {
    /// Discovered by the embedding/clustering pipeline.
    case auto
    /// Created manually by the user.
    case manual
}

// MARK: - Connection

/// A weighted, typed edge connecting two notes.
/// Connections may be user-created or discovered automatically by the embedding pipeline.
@Model
public final class Connection: Sendable {

    // MARK: - Persisted Properties

    @Attribute(.unique)
    public var id: UUID

    /// The note this connection originates from.
    public var sourceNote: Note

    /// The note this connection points to.
    public var targetNote: Note

    /// Describes the nature of the relationship (e.g. "related", "follow-up", "contradicts").
    public var relationshipType: String

    /// Semantic similarity strength (0.0–1.0).
    public var strength: Double

    /// How the connection was created.
    public var createdBy: ConnectionCreator

    public var createdAt: Date

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        sourceNote: Note,
        targetNote: Note,
        relationshipType: String = "related",
        strength: Double = 0.5,
        createdBy: ConnectionCreator = .auto
    ) {
        self.id = id
        self.sourceNote = sourceNote
        self.targetNote = targetNote
        self.relationshipType = relationshipType
        self.strength = strength
        self.createdBy = createdBy
        self.createdAt = Date.now
    }

    // MARK: - Convenience

    /// Returns the other note in the connection given one endpoint.
    public func otherNote(from note: Note) -> Note {
        note.id == sourceNote.id ? targetNote : sourceNote
    }

    /// Whether the strength is within the valid 0–1 range.
    public var isValid: Bool {
        (0.0...1.0).contains(strength)
    }
}
