// PriorityScorer.swift — Category-aware priority scoring engine
// CoppermindCore
//
// Scoring formula per category:
//   Task    = 100 + urgency(high=50, med=25, low=0) + due_date_proximity(0–50 exp) + staleness(-5/week)
//   Project = 50  + recency(0–20) + connections(0–15)
//   Idea    = 30  + recency(0–20) + connections(0–10)
//   Bucket  = 20  + time_sensitivity(0–30) + star(0–25)
//
// Global modifiers:
//   Pinned       → +10 000
//   Completed    → −10 000
//   Archived     → −10 000

import Foundation
import SwiftData

// MARK: - PriorityScorer

/// Computes a numeric priority score for any Note based on its category and attributes.
/// Higher scores float to the top of the home feed.
public struct PriorityScorer: Sendable {

    // MARK: - Constants

    private enum K {
        // Base scores per category
        static let taskBase:    Double = 100
        static let projectBase: Double = 50
        static let ideaBase:    Double = 30
        static let bucketBase:  Double = 20

        // Global modifiers
        static let pinBoost:          Double = 10_000
        static let completionPenalty: Double = -10_000
        static let archivedPenalty:   Double = -10_000

        // Task signals
        static let urgencyHigh:   Double = 50
        static let urgencyMedium: Double = 25
        static let urgencyLow:    Double = 0
        static let maxDueDateProximity: Double = 50
        static let stalenessPerWeek:    Double = -5

        // Project signals
        static let projectMaxRecency:     Double = 20
        static let projectMaxConnections: Double = 15

        // Idea signals
        static let ideaMaxRecency:     Double = 20
        static let ideaMaxConnections: Double = 10

        // Bucket signals
        static let bucketMaxTimeSensitivity: Double = 30
        static let bucketStarBoost:          Double = 25

        // Temporal constants
        static let recencyHalfLifeDays: Double = 14.0
        static let dueDateDecayDays:    Double = 30.0
        static let secondsPerDay:       Double = 86_400.0
        static let secondsPerWeek:      Double = 604_800.0
    }

    // MARK: - Init

    public init() {}

    // MARK: - Single-Note Scoring

    /// Compute the priority score for a single note.
    public func score(for note: Note) -> Double {
        var total: Double

        switch note.category {
        case .task:
            total = scoreTask(note)
        case .project:
            total = scoreProject(note)
        case .idea:
            total = scoreIdea(note)
        case .bucket:
            total = scoreBucket(note)
        }

        // Global modifiers
        if note.isPinned {
            total += K.pinBoost
        }
        if note.isCompleted == true {
            total += K.completionPenalty
        }
        if note.isArchived {
            total += K.archivedPenalty
        }

        return total
    }

    // MARK: - Batch Scoring

    /// Recompute priority scores for all non-archived notes in the given context.
    public func recalculateAll(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { !$0.isArchived }
        )
        let notes = try context.fetch(descriptor)
        for note in notes {
            note.priorityScore = score(for: note)
        }
        try context.save()
    }

    /// Score an in-memory array of notes (no persistence).
    public func scoreAll(_ notes: [Note]) {
        for note in notes {
            note.priorityScore = score(for: note)
        }
    }

    // MARK: - Category Scoring Functions

    /// Task = 100 + urgency + due_date_proximity + staleness
    private func scoreTask(_ note: Note) -> Double {
        var s = K.taskBase

        // Urgency component
        s += urgencyScore(note.urgency)

        // Due date proximity (0–50, exponential increase as due date approaches)
        s += dueDateProximityScore(dueDate: note.dueDate)

        // Staleness penalty: −5 per week since last update
        s += stalenessScore(updatedAt: note.updatedAt)

        return s
    }

    /// Project = 50 + recency(0–20) + connections(0–15)
    private func scoreProject(_ note: Note) -> Double {
        var s = K.projectBase
        s += recencyScore(updatedAt: note.updatedAt, maxValue: K.projectMaxRecency)
        s += connectionScore(count: note.connectionCount, maxValue: K.projectMaxConnections)
        return s
    }

    /// Idea = 30 + recency(0–20) + connections(0–10)
    private func scoreIdea(_ note: Note) -> Double {
        var s = K.ideaBase
        s += recencyScore(updatedAt: note.updatedAt, maxValue: K.ideaMaxRecency)
        s += connectionScore(count: note.connectionCount, maxValue: K.ideaMaxConnections)
        return s
    }

    /// Bucket = 20 + time_sensitivity(0–30) + star(0–25)
    private func scoreBucket(_ note: Note) -> Double {
        var s = K.bucketBase
        s += timeSensitivityScore(dueDate: note.dueDate, maxValue: K.bucketMaxTimeSensitivity)
        if note.isStarred {
            s += K.bucketStarBoost
        }
        return s
    }

    // MARK: - Signal Functions

    /// Maps Urgency enum to score component.
    private func urgencyScore(_ urgency: Urgency?) -> Double {
        switch urgency {
        case .high:   return K.urgencyHigh
        case .medium: return K.urgencyMedium
        case .low:    return K.urgencyLow
        case .none:   return K.urgencyLow
        }
    }

    /// Exponential increase as due date approaches or is past.
    /// Returns 0–50. Overdue items get the maximum boost.
    func dueDateProximityScore(dueDate: Date?) -> Double {
        guard let dueDate else { return 0 }

        let daysUntilDue = dueDate.timeIntervalSince(Date.now) / K.secondsPerDay

        if daysUntilDue <= 0 {
            // Overdue → maximum proximity score
            return K.maxDueDateProximity
        }

        if daysUntilDue > K.dueDateDecayDays {
            // Far away → negligible
            return 0
        }

        // Exponential curve: score = maxValue * exp(-daysUntilDue / τ)
        // τ chosen so that at 7 days out ≈ half the max score
        let tau = 7.0 / log(2.0)  // ≈ 10.1
        let raw = K.maxDueDateProximity * exp(-daysUntilDue / tau)
        return min(max(raw, 0), K.maxDueDateProximity)
    }

    /// Staleness penalty: −5 per week since last update.
    func stalenessScore(updatedAt: Date) -> Double {
        let weeksSinceUpdate = Date.now.timeIntervalSince(updatedAt) / K.secondsPerWeek
        return K.stalenessPerWeek * weeksSinceUpdate
    }

    /// Recency boost: exponential decay from `maxValue` down to 0.
    /// Half-life is `recencyHalfLifeDays`.
    func recencyScore(updatedAt: Date, maxValue: Double) -> Double {
        let daysSince = Date.now.timeIntervalSince(updatedAt) / K.secondsPerDay
        let lambda = log(2.0) / K.recencyHalfLifeDays
        return maxValue * exp(-lambda * daysSince)
    }

    /// Connection score: logarithmic scaling of connection count.
    func connectionScore(count: Int, maxValue: Double) -> Double {
        guard count > 0 else { return 0 }
        // log(1+count) / log(1+20) gives ~1.0 at 20 connections
        let normalized = log(1.0 + Double(count)) / log(1.0 + 20.0)
        return min(normalized, 1.0) * maxValue
    }

    /// Time sensitivity for bucket items: same exponential as due date proximity
    /// but with a different max value.
    private func timeSensitivityScore(dueDate: Date?, maxValue: Double) -> Double {
        guard let dueDate else { return 0 }
        let daysUntilDue = dueDate.timeIntervalSince(Date.now) / K.secondsPerDay

        if daysUntilDue <= 0 { return maxValue }
        if daysUntilDue > K.dueDateDecayDays { return 0 }

        let tau = 7.0 / log(2.0)
        return min(maxValue * exp(-daysUntilDue / tau), maxValue)
    }
}
