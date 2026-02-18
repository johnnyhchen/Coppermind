// ModelTests.swift — Tests for SwiftData model definitions
// CoppermindTests

import Testing
import Foundation
import SwiftData
@testable import CoppermindCore

// MARK: - Test Helpers

private func makeContainer() throws -> ModelContainer {
    let schema = Schema([
        Note.self,
        Connection.self,
        AudioRecording.self,
        NoteGroup.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - NoteCategory Tests

@Suite("NoteCategory Enum")
struct NoteCategoryTests {

    @Test("All categories have display names")
    func displayNames() {
        #expect(NoteCategory.idea.displayName == "Idea")
        #expect(NoteCategory.task.displayName == "Task")
        #expect(NoteCategory.project.displayName == "Project")
        #expect(NoteCategory.bucket.displayName == "Bucket")
    }

    @Test("All categories have SF Symbol icons")
    func iconNames() {
        #expect(NoteCategory.idea.iconName == "lightbulb")
        #expect(NoteCategory.task.iconName == "checkmark.circle")
        #expect(NoteCategory.project.iconName == "folder")
        #expect(NoteCategory.bucket.iconName == "tray")
    }

    @Test("NoteCategory is Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for category in NoteCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(NoteCategory.self, from: data)
            #expect(decoded == category)
        }
    }
}

// MARK: - NoteSource Tests

@Suite("NoteSource Enum")
struct NoteSourceTests {

    @Test("NoteSource Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source in NoteSource.allCases {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(NoteSource.self, from: data)
            #expect(decoded == source)
        }
    }

    @Test("NoteSource has typed and audio cases")
    func cases() {
        let all = NoteSource.allCases
        #expect(all.contains(.typed))
        #expect(all.contains(.audio))
        #expect(all.count == 2)
    }
}

// MARK: - Note Tests

@Suite("Note Model")
struct NoteTests {

    @Test("Note initializes with defaults")
    func noteDefaults() {
        let note = Note(title: "Test", body: "Body")
        #expect(note.title == "Test")
        #expect(note.body == "Body")
        #expect(note.category == .idea)
        #expect(note.priorityScore == 0.0)
        #expect(note.isArchived == false)
        #expect(note.source == .typed)
        // Task fields nil by default
        #expect(note.dueDate == nil)
        #expect(note.isCompleted == nil)
        #expect(note.completedAt == nil)
        #expect(note.urgency == nil)
        // Bucket fields nil by default
        #expect(note.url == nil)
        #expect(note.bucketType == nil)
        #expect(note.estimatedPrice == nil)
        #expect(note.location == nil)
    }

    @Test("Note touch updates timestamp")
    func noteTouch() async throws {
        let note = Note(title: "Test", body: "Body")
        let before = note.updatedAt
        try await Task.sleep(for: .milliseconds(10))
        note.touch()
        #expect(note.updatedAt > before)
    }

    @Test("Note age is positive")
    func noteAge() async throws {
        let note = Note(title: "Test", body: "Body")
        try await Task.sleep(for: .milliseconds(5))
        #expect(note.age > 0)
    }

    @Test("Note isStale after 2 weeks")
    func noteIsStale() {
        let note = Note(title: "Test", body: "Body")
        // Fresh note should not be stale
        #expect(!note.isStale)

        // Simulate an old updatedAt
        let threeWeeksAgo = Calendar.current.date(byAdding: .day, value: -21, to: .now)!
        note.updatedAt = threeWeeksAgo
        #expect(note.isStale)
    }

    @Test("Note connectionCount starts at zero")
    func connectionCountDefault() {
        let note = Note(title: "Test", body: "Body")
        #expect(note.connectionCount == 0)
    }

    @Test("Note isTask computed property")
    func isTaskComputed() {
        let idea = Note(title: "Idea", body: "", category: .idea)
        #expect(!idea.isTask)

        let task = Note(title: "Task", body: "", category: .task)
        #expect(task.isTask)
    }

    @Test("Note persists via SwiftData")
    func notePersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(title: "Persist", body: "Test Body", category: .project)
        context.insert(note)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Note>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persist")
        #expect(fetched.first?.category == .project)
    }

    @Test("Task note completion lifecycle")
    func taskCompletionLifecycle() {
        let note = Note(
            title: "Buy groceries",
            body: "Milk, eggs, bread",
            category: .task,
            urgency: .high
        )

        #expect(note.isTask)
        #expect(note.isCompleted != true)
        #expect(note.completedAt == nil)

        note.completeTask()
        #expect(note.isCompleted == true)
        #expect(note.completedAt != nil)

        note.reopenTask()
        #expect(note.isCompleted == false)
        #expect(note.completedAt == nil)
    }

    @Test("Task note overdue detection")
    func taskOverdue() {
        let pastDate = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let overdueNote = Note(
            title: "Overdue",
            body: "",
            category: .task,
            dueDate: pastDate
        )
        #expect(overdueNote.isOverdue)

        let futureDate = Calendar.current.date(byAdding: .day, value: 2, to: .now)!
        let futureNote = Note(
            title: "Future",
            body: "",
            category: .task,
            dueDate: futureDate
        )
        #expect(!futureNote.isOverdue)

        // Completed tasks are never overdue
        let completedNote = Note(
            title: "Done",
            body: "",
            category: .task,
            dueDate: pastDate,
            isCompleted: true
        )
        #expect(!completedNote.isOverdue)
    }

    @Test("Non-task completeTask is no-op")
    func completeNonTask() {
        let note = Note(title: "Idea", body: "", category: .idea)
        note.completeTask()
        #expect(note.isCompleted == nil)
    }

    @Test("Bucket note fields")
    func bucketNote() {
        let note = Note(
            title: "Visit Tokyo Tower",
            body: "",
            category: .bucket,
            url: "https://www.tokyotower.co.jp",
            bucketType: .visit,
            estimatedPrice: 1200.0,
            location: "Tokyo, Japan"
        )
        #expect(note.category == .bucket)
        #expect(note.url == "https://www.tokyotower.co.jp")
        #expect(note.bucketType == .visit)
        #expect(note.estimatedPrice == 1200.0)
        #expect(note.location == "Tokyo, Japan")
    }

    @Test("Audio source note")
    func audioSourceNote() {
        let note = Note(title: "Voice memo", body: "", source: .audio)
        #expect(note.source == .audio)
    }
}

// MARK: - Urgency Tests

@Suite("Urgency Enum")
struct UrgencyTests {

    @Test("Urgency ordering")
    func ordering() {
        #expect(Urgency.low < Urgency.medium)
        #expect(Urgency.medium < Urgency.high)
    }

    @Test("Urgency Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for urgency in Urgency.allCases {
            let data = try encoder.encode(urgency)
            let decoded = try decoder.decode(Urgency.self, from: data)
            #expect(decoded == urgency)
        }
    }
}

// MARK: - BucketType Tests

@Suite("BucketType Enum")
struct BucketTypeTests {

    @Test("BucketType has all expected cases")
    func allCases() {
        let cases = BucketType.allCases
        #expect(cases.count == 6)
        #expect(cases.contains(.buy))
        #expect(cases.contains(.read))
        #expect(cases.contains(.visit))
        #expect(cases.contains(.watch))
        #expect(cases.contains(.listen))
        #expect(cases.contains(.other))
    }

    @Test("BucketType Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for bt in BucketType.allCases {
            let data = try encoder.encode(bt)
            let decoded = try decoder.decode(BucketType.self, from: data)
            #expect(decoded == bt)
        }
    }
}

// MARK: - Connection Tests

@Suite("Connection Model")
struct ConnectionTests {

    @Test("Connection links two notes with strength")
    func connectionLinking() {
        let noteA = Note(title: "A", body: "")
        let noteB = Note(title: "B", body: "")
        let connection = Connection(
            sourceNote: noteA,
            targetNote: noteB,
            relationshipType: "follow-up",
            strength: 0.8,
            createdBy: .auto
        )

        #expect(connection.strength == 0.8)
        #expect(connection.createdBy == .auto)
        #expect(connection.relationshipType == "follow-up")
        #expect(connection.isValid)
    }

    @Test("Connection defaults")
    func connectionDefaults() {
        let noteA = Note(title: "A", body: "")
        let noteB = Note(title: "B", body: "")
        let connection = Connection(sourceNote: noteA, targetNote: noteB)

        #expect(connection.relationshipType == "related")
        #expect(connection.strength == 0.5)
        #expect(connection.createdBy == .auto)
    }

    @Test("Connection otherNote returns correct note")
    func otherNote() {
        let noteA = Note(title: "A", body: "")
        let noteB = Note(title: "B", body: "")
        let connection = Connection(sourceNote: noteA, targetNote: noteB)

        #expect(connection.otherNote(from: noteA).title == "B")
        #expect(connection.otherNote(from: noteB).title == "A")
    }

    @Test("Connection isValid rejects out-of-range strength")
    func invalidStrength() {
        let noteA = Note(title: "A", body: "")
        let noteB = Note(title: "B", body: "")
        let connection = Connection(sourceNote: noteA, targetNote: noteB, strength: 1.5)
        #expect(!connection.isValid)

        let negative = Connection(sourceNote: noteA, targetNote: noteB, strength: -0.1)
        #expect(!negative.isValid)
    }

    @Test("Connection manual creator")
    func manualCreator() {
        let noteA = Note(title: "A", body: "")
        let noteB = Note(title: "B", body: "")
        let connection = Connection(sourceNote: noteA, targetNote: noteB, createdBy: .manual)
        #expect(connection.createdBy == .manual)
    }

    @Test("Connection persists via SwiftData")
    func connectionPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let noteA = Note(title: "Source", body: "")
        let noteB = Note(title: "Target", body: "")
        context.insert(noteA)
        context.insert(noteB)

        let connection = Connection(
            sourceNote: noteA,
            targetNote: noteB,
            relationshipType: "contradicts",
            strength: 0.9,
            createdBy: .manual
        )
        context.insert(connection)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Connection>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.relationshipType == "contradicts")
        #expect(fetched.first?.strength == 0.9)
    }
}

// MARK: - AudioRecording Tests

@Suite("AudioRecording Model")
struct AudioRecordingTests {

    @Test("AudioRecording defaults")
    func defaults() {
        let note = Note(title: "Audio", body: "")
        let recording = AudioRecording(note: note, filePath: "recordings/test.m4a")

        #expect(recording.filePath == "recordings/test.m4a")
        #expect(recording.duration == 0)
        #expect(recording.transcriptionText == nil)
        #expect(recording.transcriptionConfidence == nil)
        #expect(recording.isEdited == false)
        #expect(!recording.hasTranscription)
    }

    @Test("AudioRecording URL resolution")
    func urlResolution() {
        let note = Note(title: "Audio", body: "")
        let recording = AudioRecording(note: note, filePath: "recordings/test.wav")
        let base = URL(filePath: "/Users/test/Documents")
        let resolved = recording.resolvedURL(base: base)
        #expect(resolved.path().contains("recordings/test.wav"))
    }

    @Test("AudioRecording transcription state")
    func transcriptionState() {
        let note = Note(title: "Audio", body: "")
        let recording = AudioRecording(note: note, filePath: "test.wav")
        #expect(!recording.hasTranscription)

        recording.transcriptionText = "Hello world"
        recording.transcriptionConfidence = 0.95
        #expect(recording.hasTranscription)
    }

    @Test("AudioRecording isEdited flag")
    func editedFlag() {
        let note = Note(title: "Audio", body: "")
        let recording = AudioRecording(
            note: note,
            filePath: "test.wav",
            transcriptionText: "Original text",
            isEdited: false
        )
        #expect(!recording.isEdited)

        recording.transcriptionText = "Corrected text"
        recording.isEdited = true
        #expect(recording.isEdited)
        #expect(recording.transcriptionText == "Corrected text")
    }

    @Test("AudioRecording persists via SwiftData")
    func audioPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(title: "Audio note", body: "", source: .audio)
        context.insert(note)

        let recording = AudioRecording(
            note: note,
            filePath: "audio/memo.m4a",
            duration: 45.5,
            transcriptionText: "Meeting notes",
            transcriptionConfidence: 0.92
        )
        context.insert(recording)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AudioRecording>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.duration == 45.5)
        #expect(fetched.first?.transcriptionText == "Meeting notes")
    }
}

// MARK: - NoteGroup Tests

@Suite("NoteGroup Model")
struct NoteGroupTests {

    @Test("NoteGroup defaults")
    func defaults() {
        let group = NoteGroup(name: "Test Group")
        #expect(group.name == "Test Group")
        #expect(group.autoGenerated == false)
        #expect(group.embeddingCentroid == nil)
        #expect(group.notes.isEmpty)
    }

    @Test("NoteGroup autoGenerated flag")
    func autoGenerated() {
        let group = NoteGroup(name: "Cluster 1", autoGenerated: true)
        #expect(group.autoGenerated)
    }

    @Test("NoteGroup centroid round-trip")
    func centroidRoundTrip() {
        let group = NoteGroup(name: "Test Cluster")
        let original: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        group.setCentroidEmbedding(original)

        let decoded = group.centroidEmbedding()
        #expect(decoded != nil)
        #expect(decoded?.count == original.count)

        if let decoded {
            for (a, b) in zip(original, decoded) {
                #expect(abs(a - b) < 0.0001)
            }
        }
    }

    @Test("NoteGroup touch updates timestamp")
    func groupTouch() async throws {
        let group = NoteGroup(name: "Group")
        let before = group.updatedAt
        try await Task.sleep(for: .milliseconds(10))
        group.touch()
        #expect(group.updatedAt > before)
    }

    @Test("NoteGroup persists via SwiftData")
    func groupPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(title: "Grouped note", body: "")
        context.insert(note)

        let group = NoteGroup(name: "ML Cluster", autoGenerated: true, notes: [note])
        context.insert(group)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<NoteGroup>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "ML Cluster")
        #expect(fetched.first?.autoGenerated == true)
        #expect(fetched.first?.notes.count == 1)
    }
}

// MARK: - ConnectionCreator Tests

@Suite("ConnectionCreator Enum")
struct ConnectionCreatorTests {

    @Test("ConnectionCreator Codable round-trip")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let auto = try decoder.decode(ConnectionCreator.self, from: encoder.encode(ConnectionCreator.auto))
        #expect(auto == .auto)
        let manual = try decoder.decode(ConnectionCreator.self, from: encoder.encode(ConnectionCreator.manual))
        #expect(manual == .manual)
    }
}

// MARK: - Integration Tests

@Suite("Model Integration")
struct ModelIntegrationTests {

    @Test("Full graph: Note with connections, recordings, and groups")
    func fullGraph() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create notes
        let ideaNote = Note(title: "App Idea", body: "Build a note-taking app", category: .idea)
        let taskNote = Note(
            title: "Set up project",
            body: "Initialize Swift package",
            category: .task,
            dueDate: Calendar.current.date(byAdding: .day, value: 7, to: .now),
            urgency: .medium
        )
        let bucketNote = Note(
            title: "Read SwiftData docs",
            body: "",
            category: .bucket,
            url: "https://developer.apple.com/documentation/swiftdata",
            bucketType: .read
        )

        context.insert(ideaNote)
        context.insert(taskNote)
        context.insert(bucketNote)

        // Create connection
        let connection = Connection(
            sourceNote: ideaNote,
            targetNote: taskNote,
            relationshipType: "spawned",
            strength: 0.75,
            createdBy: .auto
        )
        context.insert(connection)

        // Create audio recording
        let recording = AudioRecording(
            note: ideaNote,
            filePath: "audio/brainstorm.m4a",
            duration: 120.0,
            transcriptionText: "I want to build a second brain app"
        )
        context.insert(recording)

        // Create group
        let group = NoteGroup(name: "App Project", autoGenerated: true, notes: [ideaNote, taskNote])
        context.insert(group)

        try context.save()

        // Verify counts
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 3)

        let connections = try context.fetch(FetchDescriptor<Connection>())
        #expect(connections.count == 1)

        let recordings = try context.fetch(FetchDescriptor<AudioRecording>())
        #expect(recordings.count == 1)

        let groups = try context.fetch(FetchDescriptor<NoteGroup>())
        #expect(groups.count == 1)
        #expect(groups.first?.notes.count == 2)
    }
}
