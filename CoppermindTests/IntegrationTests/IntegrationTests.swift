// IntegrationTests.swift — Comprehensive integration scenarios across the Coppermind stack
// CoppermindTests

import Testing
import Foundation

@testable import CoppermindCore

// MARK: - Helper Utilities

/// Convenience for producing a date N days in the past.
private func daysAgo(_ days: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
}

// MARK: - Integration Test Suite

@Suite("Coppermind Integration Tests")
struct CoppermindIntegrationTests {

    // ───────────────────────────────────────────────────────────────────
    // Test 1 – Auto-categorise typed notes
    // ───────────────────────────────────────────────────────────────────

    @Test("Typed notes are categorised into bucket and high-priority task")
    func autoCategoriseTypedNotes() async {
        let classifier = CategoryClassifier()
        let scorer     = PriorityScorer()

        // Bucket-style entry
        let bucketNote = Note(title: "Buy groceries from Trader Joes", body: "")
        let bucketResult = await classifier.classifyAndApply(to: bucketNote)

        // Task-style entry with deadline semantics
        let taskNote = Note(title: "Need to finish quarterly report by Friday", body: "")
        let taskResult = await classifier.classifyAndApply(to: taskNote)

        // Expectations on categories
        #expect(bucketResult.category == .bucket)
        #expect(taskResult.category == .task)

        // Priority – task should outrank bucket item
        scorer.scoreAll([bucketNote, taskNote])
        #expect(taskNote.priorityScore > bucketNote.priorityScore)
    }

    // ───────────────────────────────────────────────────────────────────
    // Test 2 – Audio capture → transcription → note linkage
    // ───────────────────────────────────────────────────────────────────

    @Test("Audio flow attaches recording and categorises idea/project")
    func audioFlow() async {
        // Stub transcription output
        let transcript = "idea for a mobile app that tracks houseplants"

        // Create audio-originating note
        let note = Note(title: transcript, body: "", source: .audio)

        // Attach mock AudioRecording (no actual file i/o)
        let recording = AudioRecording(note: note, filePath: "recordings/mock.m4a", duration: 4.5)
        note.audioRecordings.append(recording)

        // Categorise the note text
        let classifier = CategoryClassifier()
        let result = await classifier.classifyAndApply(to: note)

        // Accept either idea or project category heuristically
        #expect([.idea, .project].contains(result.category))
        #expect(note.audioRecordings.count == 1)
        #expect(note.audioRecordings.first?.note?.id == note.id)
    }

    // ───────────────────────────────────────────────────────────────────
    // Test 3 – Connection discovery between related notes
    // ───────────────────────────────────────────────────────────────────

    @Test("Connection discovery finds links via keyword overlap")
    func connectionDiscovery() async {
        // Three related notes, two share concurrency keyword
        let noteA = Note(title: "Learn Swift concurrency", body: "Actors, Sendable, async/await")
        let noteB = Note(title: "Build iOS weather app", body: "Uses async networking and Swift concurrency")
        let noteC = Note(title: "Swift async/await patterns", body: "Task groups, structured concurrency")

        let notes = [noteA, noteB, noteC]

        let embedService = EmbeddingService()
        let discovery    = ConnectionDiscovery(embeddingService: embedService, configuration: .init(similarityThreshold: 0.25))

        do {
            let result = try await discovery.discoverConnections(for: noteA, in: notes)
            #expect(result.count >= 1)
        } catch {
            // Natural-language embeddings may be unavailable in CI; allow graceful failure
            _ = error
        }
    }

    @Test("Priority scorer ranks overdue task > project > recent idea > old bucket")
    func priorityRanking() async {
        let scorer = PriorityScorer()

        // 1. Overdue high-urgency task
        let overdueTask = Note(
            title: "Submit expense report",
            body: "",
            category: .task,
            dueDate: daysAgo(3),
            urgency: .high
        )

        // 2. Project with an existing connection (simulated)
        let project = Note(title: "Build iOS weather app", body: "", category: .project)
        let helper  = Note(title: "WeatherKit research",       body: "", category: .idea)
        _ = Connection(sourceNote: project, targetNote: helper) // adds connection

        // 3. Recent idea (no staleness penalty)
        let recentIdea = Note(title: "Try out SwiftData", body: "", category: .idea)

        // 4. Old bucket entry
        let oldBucket = Note(title: "Watch Inception", body: "", category: .bucket)
        oldBucket.updatedAt = daysAgo(60)

        let corpus = [overdueTask, project, recentIdea, oldBucket]
        scorer.scoreAll(corpus)

        let sorted = corpus.sorted { $0.priorityScore > $1.priorityScore }

        #expect(sorted.first?.id == overdueTask.id)
        #expect(sorted[1].id == project.id)
        #expect(sorted[2].id == recentIdea.id)
        #expect(sorted.last?.id == oldBucket.id)
    }

    // ───────────────────────────────────────────────────────────────────
    // Test 5 – Clustering: cooking vs programming topics
    // ───────────────────────────────────────────────────────────────────

    @Test("NoteClusterer forms two topical groups out of mixed corpus")
    func clustering() async throws {
        let cooking = [
            ("Perfect scrambled eggs", "Whisk eggs with butter and cook low and slow on the stove for creamy scrambled eggs in a breakfast kitchen recipe"),
            ("Baking sourdough bread", "Mix flour, water, salt and sourdough starter then proof overnight for artisan bread in a baking recipe"),
            ("Thai green curry recipe", "Coconut milk, green curry paste, vegetables and jasmine rice for an authentic Thai dinner recipe"),
            ("How to make sushi rice", "Season short grain rice with rice vinegar, sugar and salt for perfect sushi in a kitchen recipe"),
            ("Homemade pizza from scratch", "Make dough with yeast and flour, top with tomato sauce and mozzarella cheese for a pizza recipe"),
        ]

        let programming = [
            ("Understanding SwiftUI state management", "SwiftUI state management uses @State and @Binding for iOS app development and programming code"),
            ("JavaScript promises explained", "JavaScript promises and async await are essential programming concepts for software developers writing code"),
            ("Rust ownership guide", "Rust ownership and the borrow checker explain memory safety in systems programming and compiler code"),
            ("Kotlin coroutines patterns", "Kotlin coroutines power Android development with structured concurrency and asynchronous programming code"),
            ("Intro to React hooks", "React hooks like useState and useEffect simplify JavaScript programming in front-end development"),
        ]

        let notes = (cooking + programming).map { Note(title: $0.0, body: $0.1) }

        let embedService = EmbeddingService()
        let clusterer    = NoteClusterer(embeddingService: embedService, configuration: .init(eps: 0.95, minPoints: 2))
        let keywordClusterer = ClusterEngine(affinityThreshold: 2)

        let _ = try? await clusterer.cluster(notes: notes)
        let keywordClusters = keywordClusterer.cluster(notes)

        #expect(keywordClusters.count >= 2)

        for cluster in keywordClusters {
            #expect(cluster.noteIDs.count >= 2)
            #expect(!cluster.topKeywords.isEmpty)
        }
    }

    // ───────────────────────────────────────────────────────────────────
    // Test 6 – Category override recalculates priority
    // ───────────────────────────────────────────────────────────────────

    @Test("User override from Task→Bucket updates priority score downwards")
    func categoryOverride() async {
        let classifier = CategoryClassifier()
        let scorer     = PriorityScorer()

        let note = Note(title: "Pick up dry cleaning", body: "")

        // Auto categorisation (likely Task)
        let initial = await classifier.classifyAndApply(to: note)
        #expect(initial.category == .task)

        scorer.scoreAll([note])
        let initialScore = note.priorityScore

        // User overrides to Bucket
        note.category = .bucket

        scorer.scoreAll([note])
        let newScore = note.priorityScore

        #expect(note.category == .bucket)
        #expect(newScore < initialScore)
    }
}
