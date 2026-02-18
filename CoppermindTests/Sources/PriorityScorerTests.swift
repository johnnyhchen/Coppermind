// PriorityScorerTests.swift — Tests for priority scoring engine
// CoppermindTests

import Testing
import Foundation
@testable import CoppermindCore

@Suite("PriorityScorer")
struct PriorityScorerTests {

    let scorer = PriorityScorer()

    // MARK: - Base Scores

    @Test("Task base score is at least 100")
    func taskBaseScore() {
        let note = Note(title: "Task", body: "Do something", category: .task, urgency: .low)
        let score = scorer.score(for: note)
        // Base=100 + urgency(low=0) + dueDateProximity(0) + recency staleness(~0)
        #expect(score >= 95.0)  // Allow small staleness from test execution time
        #expect(score <= 120.0)
    }

    @Test("Project base score is around 50 + recency + connections")
    func projectBaseScore() {
        let note = Note(title: "My Project", body: "Build something", category: .project)
        let score = scorer.score(for: note)
        // Base=50 + recency(~20 for fresh note) + connections(0)
        #expect(score >= 50.0)
        #expect(score <= 75.0)
    }

    @Test("Idea base score is around 30 + recency + connections")
    func ideaBaseScore() {
        let note = Note(title: "Thought", body: "What if...", category: .idea)
        let score = scorer.score(for: note)
        // Base=30 + recency(~20 for fresh) + connections(0)
        #expect(score >= 30.0)
        #expect(score <= 55.0)
    }

    @Test("Bucket base score is around 20 + time_sensitivity + star")
    func bucketBaseScore() {
        let note = Note(title: "Buy thing", body: "From store", category: .bucket)
        let score = scorer.score(for: note)
        // Base=20 + time_sensitivity(0, no due date) + star(0)
        #expect(score >= 19.0)
        #expect(score <= 25.0)
    }

    @Test("Tasks rank above Projects rank above Ideas rank above Bucket")
    func categoryOrdering() {
        let task = Note(title: "T", body: "", category: .task, urgency: .medium)
        let project = Note(title: "P", body: "", category: .project)
        let idea = Note(title: "I", body: "", category: .idea)
        let bucket = Note(title: "B", body: "", category: .bucket)

        #expect(scorer.score(for: task) > scorer.score(for: project))
        #expect(scorer.score(for: project) > scorer.score(for: idea))
        #expect(scorer.score(for: idea) > scorer.score(for: bucket))
    }

    // MARK: - Task Urgency

    @Test("High urgency adds 50 points")
    func highUrgency() {
        let high = Note(title: "T", body: "", category: .task, urgency: .high)
        let low = Note(title: "T", body: "", category: .task, urgency: .low)
        let diff = scorer.score(for: high) - scorer.score(for: low)
        #expect(abs(diff - 50.0) < 1.0)
    }

    @Test("Medium urgency adds 25 points")
    func mediumUrgency() {
        let medium = Note(title: "T", body: "", category: .task, urgency: .medium)
        let low = Note(title: "T", body: "", category: .task, urgency: .low)
        let diff = scorer.score(for: medium) - scorer.score(for: low)
        #expect(abs(diff - 25.0) < 1.0)
    }

    // MARK: - Due Date Proximity

    @Test("Overdue task gets maximum due date proximity score")
    func overdueTaskMaxProximity() {
        let overdue = scorer.dueDateProximityScore(
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        )
        #expect(overdue == 50.0)
    }

    @Test("Due date far in future yields near-zero proximity")
    func farFutureDueDate() {
        let farAway = scorer.dueDateProximityScore(
            dueDate: Calendar.current.date(byAdding: .day, value: 60, to: .now)!
        )
        #expect(farAway < 1.0)
    }

    @Test("Due date tomorrow yields significant proximity")
    func dueTomorrow() {
        let tomorrow = scorer.dueDateProximityScore(
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        )
        #expect(tomorrow >= 20.0)
    }

    @Test("Overdue tasks outscore future tasks")
    func overdueVsFuture() {
        let overdue = Note(
            title: "Overdue",
            body: "",
            category: .task,
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            urgency: .medium
        )
        let future = Note(
            title: "Future",
            body: "",
            category: .task,
            dueDate: Calendar.current.date(byAdding: .day, value: 30, to: .now)!,
            urgency: .medium
        )
        #expect(scorer.score(for: overdue) > scorer.score(for: future))
    }

    // MARK: - Staleness

    @Test("Stale tasks lose points")
    func taskStaleness() {
        let fresh = Note(title: "T", body: "", category: .task, urgency: .medium)
        let stale = Note(title: "T", body: "", category: .task, urgency: .medium)
        stale.updatedAt = Calendar.current.date(byAdding: .day, value: -28, to: .now)!

        // 4 weeks * -5/week = -20 difference
        let diff = scorer.score(for: fresh) - scorer.score(for: stale)
        #expect(diff >= 15.0)
        #expect(diff <= 25.0)
    }

    // MARK: - Recency (Projects and Ideas)

    @Test("Fresh projects score higher than stale projects")
    func projectRecency() {
        let fresh = Note(title: "P", body: "", category: .project)
        let stale = Note(title: "P", body: "", category: .project)
        stale.updatedAt = Calendar.current.date(byAdding: .day, value: -60, to: .now)!

        #expect(scorer.score(for: fresh) > scorer.score(for: stale))
    }

    @Test("Fresh ideas score higher than stale ideas")
    func ideaRecency() {
        let fresh = Note(title: "I", body: "", category: .idea)
        let stale = Note(title: "I", body: "", category: .idea)
        stale.updatedAt = Calendar.current.date(byAdding: .day, value: -60, to: .now)!

        #expect(scorer.score(for: fresh) > scorer.score(for: stale))
    }

    // MARK: - Connections

    @Test("Connection score scales logarithmically")
    func connectionScoring() {
        let zero = scorer.connectionScore(count: 0, maxValue: 15)
        let one = scorer.connectionScore(count: 1, maxValue: 15)
        let ten = scorer.connectionScore(count: 10, maxValue: 15)
        let twenty = scorer.connectionScore(count: 20, maxValue: 15)

        #expect(zero == 0.0)
        #expect(one > 0.0)
        #expect(ten > one)
        #expect(twenty >= ten)
        #expect(twenty <= 15.0)
    }

    // MARK: - Bucket Scoring

    @Test("Starred bucket items get 25 point boost")
    func starredBucketBoost() {
        let starred = Note(title: "B", body: "", category: .bucket, isStarred: true)
        let unstarred = Note(title: "B", body: "", category: .bucket)

        let diff = scorer.score(for: starred) - scorer.score(for: unstarred)
        #expect(abs(diff - 25.0) < 1.0)
    }

    @Test("Bucket with near due date gets time sensitivity boost")
    func bucketTimeSensitivity() {
        let urgent = Note(
            title: "B", body: "", category: .bucket,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        )
        let noDate = Note(title: "B", body: "", category: .bucket)

        #expect(scorer.score(for: urgent) > scorer.score(for: noDate))
    }

    // MARK: - Global Modifiers

    @Test("Pinned notes get +10000 boost")
    func pinnedBoost() {
        let note = Note(title: "Pin", body: "", category: .idea, isPinned: true)
        let score = scorer.score(for: note)
        #expect(score > 10_000)
    }

    @Test("Completed tasks get -10000 penalty")
    func completedPenalty() {
        let note = Note(title: "Done", body: "", category: .task, isCompleted: true, urgency: .medium)
        let score = scorer.score(for: note)
        #expect(score < 0)
    }

    @Test("Archived notes get -10000 penalty")
    func archivedPenalty() {
        let note = Note(title: "Old", body: "", category: .idea, isArchived: true)
        let score = scorer.score(for: note)
        #expect(score < 0)
    }

    @Test("Pinned always outscores non-pinned")
    func pinnedAlwaysWins() {
        let pinned = Note(title: "P", body: "", category: .bucket, isPinned: true)
        let task = Note(title: "T", body: "", category: .task, urgency: .high)
        #expect(scorer.score(for: pinned) > scorer.score(for: task))
    }

    // MARK: - Batch Scoring

    @Test("scoreAll assigns scores to all notes")
    func batchScoring() {
        let notes = [
            Note(title: "Task", body: "", category: .task, urgency: .medium),
            Note(title: "Project", body: "", category: .project),
            Note(title: "Idea", body: "", category: .idea),
            Note(title: "Bucket", body: "", category: .bucket),
        ]

        scorer.scoreAll(notes)

        for note in notes {
            #expect(note.priorityScore != 0.0)
        }

        // Task should be highest
        #expect(notes[0].priorityScore > notes[1].priorityScore)
        // Project > Idea
        #expect(notes[1].priorityScore > notes[2].priorityScore)
        // Idea > Bucket
        #expect(notes[2].priorityScore > notes[3].priorityScore)
    }
}
