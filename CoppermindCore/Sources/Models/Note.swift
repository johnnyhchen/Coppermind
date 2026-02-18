// Note.swift — Primary note model with SwiftData persistence
// CoppermindCore

import Foundation
import SwiftData
import SwiftUI

// MARK: - NoteCategory

/// The high-level category for a note.
public enum NoteCategory: String, Codable, Sendable, CaseIterable {
    case idea
    case task
    case project
    case bucket

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .idea:    return "Idea"
        case .task:    return "Task"
        case .project: return "Project"
        case .bucket:  return "Bucket"
        }
    }

    /// SF Symbol icon name for this category.
    public var iconName: String {
        switch self {
        case .idea:    return "lightbulb"
        case .task:    return "checkmark.circle"
        case .project: return "folder"
        case .bucket:  return "tray"
        }
    }

    /// Accent color for this category.
    public var accentColor: Color {
        switch self {
        case .idea:    return .yellow
        case .task:    return .blue
        case .project: return .purple
        case .bucket:  return .green
        }
    }
}

// MARK: - NoteSource

/// Describes how a note was created.
public enum NoteSource: String, Codable, Sendable, CaseIterable {
    case typed
    case audio
}

// MARK: - Urgency

/// Urgency level for task-type notes.
public enum Urgency: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var sortOrder: Int {
        switch self {
        case .low:    return 0
        case .medium: return 1
        case .high:   return 2
        }
    }

    public static func < (lhs: Urgency, rhs: Urgency) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - BucketType

/// Sub-type for bucket-category notes.
public enum BucketType: String, Codable, Sendable, CaseIterable {
    case buy
    case read
    case visit
    case watch
    case listen
    case other
}

// MARK: - Note

/// The primary unit of captured thought in Coppermind.
/// Supports rich text, categorization, priority scoring, and relational connections.
/// Task and bucket semantics are expressed as optional properties on the unified Note model.
@Model
public final class Note: Sendable {

    // MARK: - Core Properties

    @Attribute(.unique)
    public var id: UUID

    public var title: String
    public var body: String
    public var category: NoteCategory
    public var createdAt: Date
    public var updatedAt: Date
    public var source: NoteSource

    /// Computed priority score (0.0–1.0) from PriorityScorer.
    public var priorityScore: Double

    /// Whether the note has been archived.
    public var isArchived: Bool

    /// Whether the note is pinned to the top of the feed.
    public var isPinned: Bool

    /// Number of times the user has viewed this note.
    public var viewCount: Int

    /// Whether the user has starred this bucket item.
    public var isStarred: Bool

    // MARK: - Task Fields (optional — only relevant when category == .task)

    /// Due date for a task-type note.
    public var dueDate: Date?

    /// Whether this task has been completed.
    public var isCompleted: Bool?

    /// Timestamp when the task was marked complete.
    public var completedAt: Date?

    /// Urgency tier for a task-type note.
    public var urgency: Urgency?

    // MARK: - Bucket Fields (optional — only relevant when category == .bucket)

    /// URL associated with a bucket-type note.
    public var url: String?

    /// Sub-type of the bucket item.
    public var bucketType: BucketType?

    /// Estimated price in the user's local currency.
    public var estimatedPrice: Double?

    /// Location description for a bucket-type note.
    public var location: String?

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \Connection.sourceNote)
    public var outgoingConnections: [Connection]

    @Relationship(deleteRule: .cascade, inverse: \Connection.targetNote)
    public var incomingConnections: [Connection]

    @Relationship(deleteRule: .cascade, inverse: \AudioRecording.note)
    public var audioRecordings: [AudioRecording]

    @Relationship(inverse: \NoteGroup.notes)
    public var groups: [NoteGroup]

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        title: String = "",
        body: String = "",
        category: NoteCategory = .idea,
        source: NoteSource = .typed,
        priorityScore: Double = 0.0,
        isArchived: Bool = false,
        isPinned: Bool = false,
        viewCount: Int = 0,
        isStarred: Bool = false,
        dueDate: Date? = nil,
        isCompleted: Bool? = nil,
        completedAt: Date? = nil,
        urgency: Urgency? = nil,
        url: String? = nil,
        bucketType: BucketType? = nil,
        estimatedPrice: Double? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.createdAt = Date.now
        self.updatedAt = Date.now
        self.source = source
        self.priorityScore = priorityScore
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.viewCount = viewCount
        self.isStarred = isStarred
        // Task fields
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.urgency = urgency
        // Bucket fields
        self.url = url
        self.bucketType = bucketType
        self.estimatedPrice = estimatedPrice
        self.location = location
        // Relationships
        self.outgoingConnections = []
        self.incomingConnections = []
        self.audioRecordings = []
        self.groups = []
    }

    // MARK: - Computed Properties

    /// Age of the note since creation.
    public var age: TimeInterval {
        Date.now.timeIntervalSince(createdAt)
    }

    /// Whether the note is stale (older than 2 weeks without updates).
    public var isStale: Bool {
        let twoWeeks: TimeInterval = 14 * 24 * 60 * 60
        return Date.now.timeIntervalSince(updatedAt) > twoWeeks
    }

    /// Total number of connections (incoming + outgoing).
    public var connectionCount: Int {
        outgoingConnections.count + incomingConnections.count
    }

    /// Whether this note functions as a task (category is .task or task fields are populated).
    public var isTask: Bool {
        category == .task
    }

    /// All connections (incoming + outgoing) for this note.
    public var allConnections: [Connection] {
        outgoingConnections + incomingConnections
    }

    // MARK: - Actions

    /// Marks the note as updated (bumps `updatedAt`).
    public func touch() {
        updatedAt = Date.now
    }

    /// Mark a task-type note as completed.
    public func completeTask() {
        guard isTask else { return }
        isCompleted = true
        completedAt = Date.now
        touch()
    }

    /// Reopen a completed task-type note.
    public func reopenTask() {
        guard isTask else { return }
        isCompleted = false
        completedAt = nil
        touch()
    }

    /// Whether a task-type note is overdue.
    public var isOverdue: Bool {
        guard isTask, let dueDate, isCompleted != true else { return false }
        return dueDate < Date.now
    }
}
