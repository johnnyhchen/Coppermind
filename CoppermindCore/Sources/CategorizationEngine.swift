// CoppermindCore – CategorizationEngine.swift
// Rule-based auto-categorisation of raw text into NoteCategory.

import Foundation

/// Analyses note text and assigns a category + base priority.
public struct CategorizationEngine: Sendable {

    public init() {}

    // MARK: - Public API

    /// Analyse text and return the best-fit category with an initial priority.
    public func categorize(_ text: String) -> (category: NoteCategory, priority: Double) {
        let lower = text.lowercased()

        let bucketMatch = matchesBucket(lower)
        let taskMatch = matchesTask(lower)

        if bucketMatch && !taskMatch {
            return (.bucket, 10)
        }
        if taskMatch && !bucketMatch {
            let priority = taskPriority(lower)
            return (.task, priority)
        }
        if bucketMatch && taskMatch {
            let priority = taskPriority(lower)
            return priority >= 70 ? (.task, priority) : (.bucket, 10)
        }
        if matchesProject(lower) {
            return (.project, 40)
        }
        if matchesIdea(lower) {
            return (.idea, 30)
        }
        return (.bucket, 10)
    }

    // MARK: - Task detection

    private static let taskVerbs: [String] = [
        "need to", "must", "have to", "should",
        "finish", "complete", "submit", "deliver",
        "pick up", "schedule", "call",
        "fix", "resolve", "review", "send",
        "prepare", "clean", "organize"
    ]

    private static let bucketVerbs: [String] = [
        "buy", "order", "visit", "read", "watch",
        "listen to", "check out", "look into", "bookmark"
    ]

    private static let deadlineSignals: [String] = [
        "by friday", "by monday", "by tuesday", "by wednesday",
        "by thursday", "by saturday", "by sunday",
        "by tomorrow", "by end of", "due", "deadline",
        "asap", "urgent", "today", "tonight", "this week",
        "this morning", "this afternoon", "this evening",
        "quarterly", "monthly", "weekly"
    ]

    private func matchesTask(_ text: String) -> Bool {
        let hasVerb = Self.taskVerbs.contains { text.contains($0) }
        let hasDeadline = Self.deadlineSignals.contains { text.contains($0) }
        return hasVerb || hasDeadline
    }

    private func matchesBucket(_ text: String) -> Bool {
        Self.bucketVerbs.contains { text.contains($0) }
    }

    private func taskPriority(_ text: String) -> Double {
        var p: Double = 50
        if Self.deadlineSignals.contains(where: { text.contains($0) }) {
            p += 15
        }
        if text.contains("urgent") || text.contains("asap") {
            p += 10
        }
        if text.contains("quarterly") || text.contains("report") {
            p += 5
        }
        return min(p, 100)
    }

    // MARK: - Project detection

    private static let projectSignals: [String] = [
        "build", "develop", "create", "design",
        "launch", "implement", "architect", "plan",
        "roadmap", "milestone", "phase", "app that"
    ]

    private func matchesProject(_ text: String) -> Bool {
        Self.projectSignals.contains { text.contains($0) }
    }

    // MARK: - Idea detection

    private static let ideaSignals: [String] = [
        "idea", "what if", "maybe", "could",
        "concept", "brainstorm", "imagine",
        "inspiration", "thought about", "wonder"
    ]

    private func matchesIdea(_ text: String) -> Bool {
        Self.ideaSignals.contains { text.contains($0) }
    }
}
