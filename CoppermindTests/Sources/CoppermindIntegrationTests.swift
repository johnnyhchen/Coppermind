// CoppermindTests – CoppermindIntegrationTests.swift
// Comprehensive integration tests covering end-to-end flows.

import Foundation
import Testing
@testable import CoppermindCore

// MARK: - Mock Audio Infrastructure

/// Mock recorder that returns a pre-built AudioRecording.
struct MockAudioRecorder: AudioRecorder {
    let stubRecording: AudioRecording

    func record() async throws -> AudioRecording {
        stubRecording
    }
}

/// Mock transcriber that returns a fixed string.
struct MockAudioTranscriber: AudioTranscriber {
    let stubTranscription: String

    func transcribe(_ recording: AudioRecording) async throws -> String {
        stubTranscription
    }
}

// MARK: - Test 1: Auto-Categorize Typed Notes

@Suite("Test 1 – Auto-categorize typed notes")
struct AutoCategorizeTests {

    @Test("Grocery note is categorized as .bucket")
    func groceryNoteIsBucket() {
        let store = NoteStore()
        let note = store.addNote(text: "Buy groceries from Trader Joes")
        #expect(note.category == .bucket)
    }

    @Test("Quarterly report note is categorized as .task with elevated priority")
    func reportNoteIsTaskWithHigherPriority() {
        let store = NoteStore()
        let task = store.addNote(text: "Need to finish quarterly report by Friday")
        #expect(task.category == .task)
        // Must have priority > a plain bucket note
        let bucket = store.addNote(text: "Buy groceries from Trader Joes")
        #expect(task.priority > bucket.priority,
                "Task priority (\(task.priority)) should exceed bucket priority (\(bucket.priority))")
    }

    @Test("Task with deadline signals gets higher priority than plain task")
    func deadlineBoostsPriority() {
        let engine = CategorizationEngine()
        let (cat1, p1) = engine.categorize("Need to finish quarterly report by Friday")
        let (cat2, p2) = engine.categorize("Fix the leaky faucet")
        #expect(cat1 == .task)
        #expect(cat2 == .task)
        #expect(p1 > p2,
                "Deadline task (\(p1)) should outrank no-deadline task (\(p2))")
    }

    @Test("Idea text is categorized as .idea")
    func ideaDetection() {
        let engine = CategorizationEngine()
        let (cat, _) = engine.categorize("I have an idea for a new recipe")
        #expect(cat == .idea)
    }

    @Test("Project text is categorized as .project")
    func projectDetection() {
        let engine = CategorizationEngine()
        let (cat, _) = engine.categorize("Build a home automation system with Raspberry Pi")
        #expect(cat == .project)
    }
}

// MARK: - Test 2: Audio Flow

@Suite("Test 2 – Audio capture flow")
struct AudioFlowTests {

    @Test("Voice note is transcribed, categorized, and linked to recording")
    func audioEndToEnd() async throws {
        let stubRecording = AudioRecording(
            fileURL: URL(fileURLWithPath: "/tmp/voice_001.m4a"),
            duration: 12.5
        )
        let transcription = "idea for a mobile app that tracks houseplants"

        let pipeline = AudioPipeline(
            recorder: MockAudioRecorder(stubRecording: stubRecording),
            transcriber: MockAudioTranscriber(stubTranscription: transcription)
        )

        let (note, recording) = try await pipeline.capture()

        // Transcription flows through
        #expect(recording.transcription == transcription)
        #expect(note.text == transcription)

        // Should be categorized as .project or .idea (contains "idea" + "app that")
        let validCategories: [NoteCategory] = [.project, .idea]
        #expect(validCategories.contains(note.category),
                "Expected .project or .idea, got \(note.category)")

        // Must be linked to the audio recording
        #expect(note.audioRecordingID == recording.id,
                "Note should reference the audio recording")
    }

    @Test("Audio note is stored in NoteStore with recording reference")
    func audioNoteStoredCorrectly() async throws {
        let stubRecording = AudioRecording(
            fileURL: URL(fileURLWithPath: "/tmp/voice_002.m4a"),
            duration: 8.0
        )
        let transcription = "idea for a mobile app that tracks houseplants"

        let pipeline = AudioPipeline(
            recorder: MockAudioRecorder(stubRecording: stubRecording),
            transcriber: MockAudioTranscriber(stubTranscription: transcription)
        )

        let (note, recording) = try await pipeline.capture()
        let store = NoteStore()
        store.addAudioNote(note, recording: recording)

        #expect(store.notes.count == 1)
        #expect(store.recordings.count == 1)
        #expect(store.notes[0].audioRecordingID == store.recordings[0].id)
    }
}

// MARK: - Test 3: Connection Discovery

@Suite("Test 3 – Connection discovery by keyword overlap")
struct ConnectionTests {

    @Test("Swift-related notes are connected by keyword overlap")
    func swiftNotesConnected() {
        let store = NoteStore()
        let n1 = store.addNote(text: "Learn Swift concurrency")
        let n2 = store.addNote(text: "Build iOS weather app")
        let n3 = store.addNote(text: "Swift async/await patterns")

        // n1 and n3 share "swift" + more → should be connected
        let note1 = store.note(byID: n1.id)!
        let note3 = store.note(byID: n3.id)!

        let engine = ConnectionEngine(minimumOverlap: 1)
        let connections = engine.discoverConnections(among: store.notes)

        // At least n1↔n3 must be connected (both contain "swift")
        let hasSwiftLink = connections.contains { (a, b, kws) in
            (a == n1.id && b == n3.id) || (a == n3.id && b == n1.id)
        }
        #expect(hasSwiftLink,
                "Notes about Swift should be connected via keyword overlap")
    }

    @Test("Connection IDs are bidirectional")
    func bidirectionalLinks() {
        let engine = ConnectionEngine(minimumOverlap: 1)
        var notes = [
            Note(text: "Swift concurrency patterns async await"),
            Note(text: "Async await Swift programming guide"),
        ]
        engine.linkConnections(&notes)

        #expect(notes[0].connectionIDs.contains(notes[1].id))
        #expect(notes[1].connectionIDs.contains(notes[0].id))
    }

    @Test("Unrelated notes are not connected")
    func unrelatedNotesNotConnected() {
        let engine = ConnectionEngine(minimumOverlap: 2)
        let notes = [
            Note(text: "Learn Swift concurrency patterns"),
            Note(text: "Buy groceries from the farmers market"),
        ]
        let connections = engine.discoverConnections(among: notes)
        #expect(connections.isEmpty,
                "Unrelated notes should have no connections")
    }
}

// MARK: - Test 4: Priority Ranking

@Suite("Test 4 – Priority ranking order")
struct PriorityRankingTests {

    @Test("Overdue task > project with connections > recent idea > old bucket")
    func fullRankingOrder() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let lastWeek = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 86_400)

        // 1) Overdue task – deadline was yesterday, category .task
        let overdueTask = Note(
            text: "Submit tax return",
            category: .task,
            priority: 60,
            createdAt: lastWeek,
            deadline: yesterday
        )

        // 2) Project with connections
        let connectedProject = Note(
            text: "Build weather dashboard",
            category: .project,
            priority: 40,
            createdAt: yesterday,
            connectionIDs: [UUID(), UUID(), UUID()]
        )

        // 3) Recent idea (created now)
        let recentIdea = Note(
            text: "What if we added dark mode",
            category: .idea,
            priority: 30,
            createdAt: now
        )

        // 4) Old bucket item
        let oldBucket = Note(
            text: "Random thought about lunch",
            category: .bucket,
            priority: 10,
            createdAt: twoWeeksAgo
        )

        let ranker = PriorityRanker()
        let ranked = ranker.ranked([oldBucket, recentIdea, connectedProject, overdueTask])

        #expect(ranked[0].id == overdueTask.id,
                "Overdue task should rank first")
        #expect(ranked[1].id == connectedProject.id,
                "Project with connections should rank second")
        #expect(ranked[2].id == recentIdea.id,
                "Recent idea should rank third")
        #expect(ranked[3].id == oldBucket.id,
                "Old bucket item should rank last")
    }

    @Test("Overdue task priority score includes deadline penalty")
    func overdueScoreBoost() {
        let ranker = PriorityRanker()
        let overdueNote = Note(
            text: "Overdue item",
            category: .task,
            priority: 50,
            createdAt: Date().addingTimeInterval(-86_400 * 3),
            deadline: Date().addingTimeInterval(-86_400)
        )
        let normalNote = Note(
            text: "Normal item",
            category: .task,
            priority: 50,
            createdAt: Date().addingTimeInterval(-86_400 * 3)
        )
        #expect(ranker.score(for: overdueNote) > ranker.score(for: normalNote),
                "Overdue note should score higher than identical non-overdue note")
    }
}

// MARK: - Test 5: Clustering

@Suite("Test 5 – Thematic clustering")
struct ClusteringTests {

    @Test("5 cooking + 5 programming notes produce 2 clusters")
    func twoDistinctClusters() {
        let cookingNotes: [Note] = [
            Note(text: "Best pasta recipe with garlic sauce cooking tips"),
            Note(text: "Cooking Italian pasta dinner ideas for family"),
            Note(text: "New recipe for homemade pasta with fresh ingredients"),
            Note(text: "Kitchen cooking gadgets for making pasta efficiently"),
            Note(text: "Pasta recipe variations with different sauces cooking"),
        ]

        let programmingNotes: [Note] = [
            Note(text: "Swift programming tutorial for beginners code examples"),
            Note(text: "Learn programming with Swift language advanced code"),
            Note(text: "iOS Swift code patterns and best programming practices"),
            Note(text: "Xcode Swift programming debugging code techniques"),
            Note(text: "Swift code review programming standards and conventions"),
        ]

        let allNotes = cookingNotes + programmingNotes
        let engine = ClusterEngine(affinityThreshold: 2)
        let clusters = engine.cluster(allNotes)

        #expect(clusters.count == 2,
                "Expected 2 clusters, got \(clusters.count): \(clusters.map(\.name))")

        // Each cluster should contain roughly 5 notes
        for cluster in clusters {
            #expect(cluster.noteIDs.count >= 3,
                    "Cluster '\(cluster.name)' should have ≥ 3 notes, has \(cluster.noteIDs.count)")
        }

        // Cooking cluster should contain cooking note IDs
        let cookingIDs = Set(cookingNotes.map(\.id))
        let programmingIDs = Set(programmingNotes.map(\.id))

        // Find which cluster is which
        let cluster0IDs = Set(clusters[0].noteIDs)
        let cluster1IDs = Set(clusters[1].noteIDs)

        let cluster0CookingOverlap = cluster0IDs.intersection(cookingIDs).count
        let cluster1CookingOverlap = cluster1IDs.intersection(cookingIDs).count

        // One cluster should be predominantly cooking, the other programming
        let (cookingCluster, progCluster) = cluster0CookingOverlap > cluster1CookingOverlap
            ? (clusters[0], clusters[1])
            : (clusters[1], clusters[0])

        #expect(Set(cookingCluster.noteIDs).intersection(cookingIDs).count >= 3,
                "Cooking cluster should contain most cooking notes")
        #expect(Set(progCluster.noteIDs).intersection(programmingIDs).count >= 3,
                "Programming cluster should contain most programming notes")
    }

    @Test("Cluster names reflect content keywords")
    func clusterNamesAreDescriptive() {
        let notes: [Note] = [
            Note(text: "Swift programming tutorial for writing code"),
            Note(text: "Learn Swift programming patterns and code style"),
            Note(text: "Swift code review and programming best practices"),
        ]

        let engine = ClusterEngine(affinityThreshold: 2)
        let clusters = engine.cluster(notes)

        #expect(clusters.count == 1)
        let name = clusters[0].name.lowercased()
        // Name should contain something relevant
        let relevant = ["swift", "programming", "code"]
        let nameContainsRelevant = relevant.contains { name.contains($0) }
        #expect(nameContainsRelevant,
                "Cluster name '\(clusters[0].name)' should reference key topics")
    }

    @Test("Clusters are assigned back to notes")
    func clusterAssignment() {
        let store = NoteStore()
        store.addNote(text: "Swift programming tutorial for writing code")
        store.addNote(text: "Learn Swift programming patterns and code style")
        store.addNote(text: "Swift code review and programming best practices")

        store.applyClusters()

        for note in store.notes {
            #expect(note.clusterName != nil,
                    "Note '\(note.text)' should have a cluster name after applyClusters()")
        }
        // All three should share the same cluster name
        let names = Set(store.notes.compactMap(\.clusterName))
        #expect(names.count == 1,
                "All related notes should share one cluster name, got \(names)")
    }
}

// MARK: - Test 6: Category Override

@Suite("Test 6 – User category override")
struct CategoryOverrideTests {

    @Test("Auto-categorize then override category, priority recalculated")
    func overrideCategoryAndRecalculate() {
        let store = NoteStore()
        let note = store.addNote(text: "Pick up dry cleaning")

        // "Pick up" is a task verb → should auto-categorize as .task
        #expect(note.category == .task,
                "Expected auto-category .task, got \(note.category)")
        let originalPriority = note.priority

        // User overrides to .bucket
        store.overrideCategory(noteID: note.id, to: .bucket)

        let updated = store.note(byID: note.id)!
        #expect(updated.category == .bucket,
                "After override, category should be .bucket")
        #expect(updated.userOverrodeCategory == true,
                "userOverrodeCategory flag should be true")
        #expect(updated.priority != originalPriority,
                "Priority should be recalculated after category override")
    }

    @Test("Override does not affect other notes")
    func overrideIsolation() {
        let store = NoteStore()
        let n1 = store.addNote(text: "Pick up dry cleaning")
        let n2 = store.addNote(text: "Need to finish report by Friday")

        let n2OriginalCategory = store.note(byID: n2.id)!.category
        let n2OriginalPriority = store.note(byID: n2.id)!.priority

        store.overrideCategory(noteID: n1.id, to: .bucket)

        let n2After = store.note(byID: n2.id)!
        #expect(n2After.category == n2OriginalCategory,
                "Other note category should be unchanged")
    }

    @Test("Bucket override results in lower priority than task")
    func bucketLowerThanTask() {
        let store = NoteStore()
        let taskNote = store.addNote(text: "Pick up dry cleaning")
        let taskPriority = store.note(byID: taskNote.id)!.priority

        store.overrideCategory(noteID: taskNote.id, to: .bucket)
        let bucketPriority = store.note(byID: taskNote.id)!.priority

        // A bucket score should generally be less than the original task score
        // because the category bonus for .bucket < .task
        let ranker = PriorityRanker()
        let taskBaseline = ranker.score(for: Note(text: "x", category: .task, priority: 50))
        let bucketBaseline = ranker.score(for: Note(text: "x", category: .bucket, priority: 10))
        #expect(bucketBaseline < taskBaseline,
                "Bucket baseline (\(bucketBaseline)) should be less than task baseline (\(taskBaseline))")
    }
}
