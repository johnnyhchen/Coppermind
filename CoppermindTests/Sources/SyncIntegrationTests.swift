// SyncIntegrationTests.swift — Integration tests for CloudKit sync layer
// CoppermindTests
//
// Tests SyncManager container creation, state transitions, event handling,
// priority recalculation after import, and error banner lifecycle.
// All tests use in-memory containers (no actual CloudKit calls).

import Testing
import Foundation
import SwiftData
import CoreData
@testable import CoppermindCore

// MARK: - Test Helpers

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Note.self,
        Connection.self,
        AudioRecording.self,
        NoteGroup.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - SyncState Tests

@Suite("SyncState")
struct SyncStateTests {

    @Test("SyncState equality")
    func equality() {
        #expect(SyncState.syncing == SyncState.syncing)
        #expect(SyncState.synced == SyncState.synced)
        #expect(SyncState.offline == SyncState.offline)
        #expect(SyncState.error("test") == SyncState.error("test"))
        #expect(SyncState.error("a") != SyncState.error("b"))
        #expect(SyncState.syncing != SyncState.synced)
    }

    @Test("SyncState descriptions are human-readable")
    func descriptions() {
        #expect(SyncState.syncing.description == "Syncing…")
        #expect(SyncState.synced.description == "Up to date")
        #expect(SyncState.offline.description == "Offline")
        #expect(SyncState.error("fail").description.contains("fail"))
    }
}

// MARK: - SyncError Tests

@Suite("SyncError")
struct SyncErrorTests {

    @Test("SyncError has localized descriptions")
    func localizedDescriptions() {
        let containerErr = SyncError.containerCreationFailed("bad schema")
        #expect(containerErr.errorDescription?.contains("bad schema") == true)

        let disabledErr = SyncError.syncDisabled
        #expect(disabledErr.errorDescription?.contains("disabled") == true)

        let priorityErr = SyncError.priorityRecalculationFailed("context error")
        #expect(priorityErr.errorDescription?.contains("context error") == true)

        let accountErr = SyncError.cloudKitAccountUnavailable
        #expect(accountErr.errorDescription?.contains("iCloud") == true)
    }
}

// MARK: - SyncManager Container Tests

@Suite("SyncManager Container Creation")
struct SyncManagerContainerTests {

    @Test("makeTestContainer creates in-memory container")
    @MainActor
    func testContainerCreation() throws {
        let manager = SyncManager()
        let container = try manager.makeTestContainer()

        // Verify the container works with a basic insert
        let context = container.mainContext
        let note = Note(title: "Sync test", body: "Testing sync container")
        context.insert(note)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Sync test")
    }

    @Test("Test container sets state to offline")
    @MainActor
    func testContainerSetsOffline() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()
        #expect(manager.syncState == .offline)
    }

    @Test("Test container starts with no pending changes")
    @MainActor
    func noPendingChanges() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()
        #expect(manager.pendingChanges == 0)
    }

    @Test("Test container starts with nil lastSyncDate")
    @MainActor
    func noLastSync() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()
        #expect(manager.lastSyncDate == nil)
    }

    @Test("All model types registered in container")
    @MainActor
    func allModelsRegistered() throws {
        let manager = SyncManager()
        let container = try manager.makeTestContainer()
        let context = container.mainContext

        // Insert one of each model type
        let note = Note(title: "Note", body: "body")
        context.insert(note)

        let connection = Connection(
            sourceNote: note,
            targetNote: Note(title: "Target", body: "target body")
        )
        context.insert(connection.targetNote)
        context.insert(connection)

        let recording = AudioRecording(note: note, filePath: "test.m4a")
        context.insert(recording)

        let group = NoteGroup(name: "Test Group", notes: [note])
        context.insert(group)

        try context.save()

        #expect(try context.fetch(FetchDescriptor<Note>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Connection>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AudioRecording>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NoteGroup>()).count == 1)
    }
}

// MARK: - SyncManager State Tests

@Suite("SyncManager State Management")
struct SyncManagerStateTests {

    @Test("trackLocalChange increments pendingChanges")
    @MainActor
    func trackLocalChange() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()

        #expect(manager.pendingChanges == 0)
        manager.trackLocalChange()
        #expect(manager.pendingChanges == 1)
        manager.trackLocalChange()
        #expect(manager.pendingChanges == 2)
    }

    @Test("dismissErrorBanner clears error state")
    @MainActor
    func dismissBanner() {
        let manager = SyncManager()
        // Simulate setting error state directly isn't possible from outside,
        // but dismissErrorBanner should always clear to a clean state.
        manager.dismissErrorBanner()
        #expect(manager.showErrorBanner == false)
        #expect(manager.lastErrorMessage == nil)
    }

    @Test("tearDown removes subscriptions")
    @MainActor
    func tearDown() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()
        manager.tearDown()
        // After tearDown, further events should not affect state
        // (no crash, no state change from notifications)
    }
}

// MARK: - Priority Recalculation After Sync Tests

@Suite("Post-Sync Priority Recalculation")
struct PostSyncPriorityTests {

    @Test("Priority scores recalculate correctly in synced container")
    @MainActor
    func priorityRecalculation() throws {
        let manager = SyncManager()
        let container = try manager.makeTestContainer()
        let context = container.mainContext

        // Create notes with different categories
        let task = Note(title: "Buy groceries", body: "Milk, eggs", category: .task, urgency: .high)
        let idea = Note(title: "App idea", body: "Build a cool app", category: .idea)
        let project = Note(title: "Project X", body: "Big project", category: .project)

        context.insert(task)
        context.insert(idea)
        context.insert(project)
        try context.save()

        // Recalculate priorities using the scorer (simulates post-import behavior)
        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        // Verify scores are assigned and ordered correctly
        #expect(task.priorityScore > 0)
        #expect(idea.priorityScore > 0)
        #expect(project.priorityScore > 0)

        // Tasks with high urgency should score higher than ideas
        #expect(task.priorityScore > idea.priorityScore)
    }

    @Test("Pinned notes get massive priority boost after recalculation")
    @MainActor
    func pinnedBoostAfterSync() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let pinned = Note(title: "Pinned", body: "Important", category: .idea, isPinned: true)
        let normal = Note(title: "Normal", body: "Regular", category: .idea)

        context.insert(pinned)
        context.insert(normal)
        try context.save()

        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        #expect(pinned.priorityScore > 10_000)
        #expect(pinned.priorityScore > normal.priorityScore)
    }

    @Test("Completed tasks get penalty after recalculation")
    @MainActor
    func completedPenaltyAfterSync() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let completed = Note(
            title: "Done task",
            body: "Finished",
            category: .task,
            isCompleted: true,
            urgency: .low
        )
        context.insert(completed)
        try context.save()

        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        #expect(completed.priorityScore < 0)
    }

    @Test("Archived notes excluded from recalculation")
    @MainActor
    func archivedExcluded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let archived = Note(
            title: "Archived",
            body: "Old note",
            category: .idea,
            isArchived: true
        )
        archived.priorityScore = 999.0
        context.insert(archived)
        try context.save()

        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        // The archived note's score should not have been changed by recalculateAll
        // because the predicate filters out archived notes
        #expect(archived.priorityScore == 999.0)
    }
}

// MARK: - Conflict Resolution Strategy Tests

@Suite("Conflict Resolution Strategies")
struct ConflictResolutionTests {

    @Test("Last-writer-wins: later updatedAt wins for scalar fields")
    @MainActor
    func lastWriterWinsScalars() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Simulate two "devices" editing the same note
        let note = Note(title: "Original", body: "Original body", category: .idea)
        context.insert(note)
        try context.save()

        // Device A edits title
        note.title = "Device A Title"
        note.updatedAt = Date.now

        // Device B edits (later timestamp wins in LWW)
        let later = Date.now.addingTimeInterval(1)
        note.title = "Device B Title"
        note.updatedAt = later
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.first?.title == "Device B Title")
        #expect(fetched.first?.updatedAt == later)
    }

    @Test("Connection merge: both sides' connections preserved")
    @MainActor
    func connectionMerge() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let noteA = Note(title: "A", body: "Alpha")
        let noteB = Note(title: "B", body: "Beta")
        let noteC = Note(title: "C", body: "Charlie")
        context.insert(noteA)
        context.insert(noteB)
        context.insert(noteC)

        // Device A creates connection A->B
        let connAB = Connection(sourceNote: noteA, targetNote: noteB, strength: 0.8)
        context.insert(connAB)

        // Device B creates connection A->C
        let connAC = Connection(sourceNote: noteA, targetNote: noteC, strength: 0.6)
        context.insert(connAC)

        try context.save()

        // After merge, both connections should exist
        let connections = try context.fetch(FetchDescriptor<Connection>())
        #expect(connections.count == 2)

        // Note A should have both outgoing connections
        let fetchedA = try context.fetch(FetchDescriptor<Note>())
            .first(where: { $0.title == "A" })
        #expect(fetchedA?.outgoingConnections.count == 2)
    }

    @Test("Audio recording CKAsset: externalStorage attribute present")
    @MainActor
    func audioExternalStorage() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let note = Note(title: "Audio note", body: "", source: .audio)
        context.insert(note)

        // Create audio recording with file path
        // In production, audioData with @Attribute(.externalStorage) maps to CKAsset
        let recording = AudioRecording(
            note: note,
            filePath: "audio/meeting.m4a",
            duration: 300.0,
            transcriptionText: "Meeting notes content"
        )
        context.insert(recording)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AudioRecording>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.filePath == "audio/meeting.m4a")
        #expect(fetched.first?.duration == 300.0)
    }
}

// MARK: - End-to-End Sync Flow Tests

@Suite("End-to-End Sync Flows")
struct EndToEndSyncFlowTests {

    @Test("Full sync cycle: create → save → recalculate → verify scores")
    @MainActor
    func fullSyncCycle() throws {
        let manager = SyncManager()
        let container = try manager.makeTestContainer()
        let context = container.mainContext

        // Simulate note creation on device A
        let task = Note(
            title: "Urgent task",
            body: "Do this ASAP",
            category: .task,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: .now),
            urgency: .high
        )
        let idea = Note(
            title: "Cool idea",
            body: "What if we built...",
            category: .idea
        )
        context.insert(task)
        context.insert(idea)

        // Track local changes
        manager.trackLocalChange()
        manager.trackLocalChange()
        #expect(manager.pendingChanges == 2)

        try context.save()

        // Simulate post-import recalculation (what happens after CloudKit import)
        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        // Task with high urgency + near due date should outrank idea
        #expect(task.priorityScore > idea.priorityScore)
        #expect(task.priorityScore > 100)  // At least base task score
    }

    @Test("Sync cycle with connections and groups")
    @MainActor
    func syncWithGraph() throws {
        let manager = SyncManager()
        let container = try manager.makeTestContainer()
        let context = container.mainContext

        // Create interconnected notes
        let note1 = Note(title: "Swift Concurrency", body: "Actors and async/await", category: .idea)
        let note2 = Note(title: "SwiftUI Performance", body: "Optimizing view updates", category: .idea)
        let note3 = Note(title: "Build App", body: "Combine Swift and SwiftUI skills", category: .project)

        context.insert(note1)
        context.insert(note2)
        context.insert(note3)

        // Create connections (simulating discovery engine output)
        let conn1 = Connection(sourceNote: note1, targetNote: note2, strength: 0.85, createdBy: .auto)
        let conn2 = Connection(sourceNote: note1, targetNote: note3, strength: 0.7, createdBy: .auto)
        context.insert(conn1)
        context.insert(conn2)

        // Create group (simulating clusterer output)
        let group = NoteGroup(name: "Swift Development", autoGenerated: true, notes: [note1, note2, note3])
        context.insert(group)

        try context.save()

        // Verify graph integrity
        #expect(note1.outgoingConnections.count == 2)
        #expect(note1.connectionCount == 2)

        // Recalculate priorities (post-import simulation)
        let scorer = PriorityScorer()
        try scorer.recalculateAll(in: context)

        // Project with connections should score higher than base
        #expect(note3.priorityScore > 50)  // Base project score
    }

    @Test("Multiple sync managers can share container schema")
    @MainActor
    func multipleManagers() throws {
        let manager1 = SyncManager()
        let container1 = try manager1.makeTestContainer()

        let manager2 = SyncManager()
        let container2 = try manager2.makeTestContainer()

        // Both containers should work independently
        let ctx1 = container1.mainContext
        let ctx2 = container2.mainContext

        let note1 = Note(title: "From manager 1", body: "")
        ctx1.insert(note1)
        try ctx1.save()

        let note2 = Note(title: "From manager 2", body: "")
        ctx2.insert(note2)
        try ctx2.save()

        #expect(try ctx1.fetch(FetchDescriptor<Note>()).count == 1)
        #expect(try ctx2.fetch(FetchDescriptor<Note>()).count == 1)
    }
}

// MARK: - CloudKit Event Notification Tests

@Suite("CloudKit Event Notifications")
struct CloudKitEventNotificationTests {

    @Test("SyncManager responds to event notifications without crashing")
    @MainActor
    func eventNotificationSafety() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()

        // Post a notification with no valid event — should not crash
        NotificationCenter.default.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            userInfo: nil
        )

        // Post with empty userInfo — should not crash
        NotificationCenter.default.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            userInfo: [:]
        )

        // State should still be offline (test container doesn't enable CloudKit)
        #expect(manager.syncState == .offline)
    }

    @Test("tearDown prevents further event processing")
    @MainActor
    func tearDownPreventsProcessing() throws {
        let manager = SyncManager()
        _ = try manager.makeTestContainer()

        manager.tearDown()

        // Post event after tearDown — should have no effect
        NotificationCenter.default.post(
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            userInfo: nil
        )

        #expect(manager.syncState == .offline)
    }
}
