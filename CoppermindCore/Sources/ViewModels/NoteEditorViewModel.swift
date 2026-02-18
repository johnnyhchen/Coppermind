// NoteEditorViewModel.swift — Drives the note editing UI
// CoppermindCore

import Foundation
import Observation
import SwiftData

/// ViewModel for the note detail / editor view.
/// Handles text editing, categorization triggers, and auto-save.
@Observable
@MainActor
public final class NoteEditorViewModel {

    // MARK: - State

    public var note: Note
    public var title: String {
        didSet { markDirty() }
    }
    public var body: String {
        didSet { markDirty() }
    }

    public var isDirty: Bool = false
    public var isSaving: Bool = false
    public var isClassifying: Bool = false
    public var classificationResult: CategoryResult?
    public var errorMessage: String?

    /// Time since last edit — drives auto-save.
    public var lastEditTime: Date?

    /// Auto-save debounce interval in seconds.
    public let autoSaveInterval: TimeInterval = 2.0

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let classifier: CategoryClassifier
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Init

    public init(note: Note, modelContext: ModelContext, classifier: CategoryClassifier = CategoryClassifier()) {
        self.note = note
        self.title = note.title
        self.body = note.body
        self.modelContext = modelContext
        self.classifier = classifier
    }

    // MARK: - Editing

    private func markDirty() {
        isDirty = true
        lastEditTime = Date.now
        scheduleAutoSave()
    }

    // MARK: - Persistence

    /// Save the current edits to the model.
    public func save() async {
        isSaving = true
        errorMessage = nil

        note.title = title
        note.body = body
        note.touch()

        do {
            try modelContext.save()
            isDirty = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Discard unsaved edits and revert to persisted state.
    public func revert() {
        title = note.title
        body = note.body
        isDirty = false
        autoSaveTask?.cancel()
    }

    // MARK: - Auto-Save

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(autoSaveInterval))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    // MARK: - Classification

    /// Trigger re-classification of the note.
    public func classify() async {
        isClassifying = true
        errorMessage = nil

        let text = [title, body].filter { !$0.isEmpty }.joined(separator: ". ")
        let result = await classifier.classify(text: text)
        classificationResult = result
        note.category = result.category

        isClassifying = false
    }

    /// Apply a user override for the category.
    public func overrideCategory(_ category: NoteCategory) {
        let result = classifier.userOverride(category: category)
        classificationResult = result
        note.category = result.category
        markDirty()
    }

    // MARK: - Connections

    /// The note's connections for display.
    public var connections: [Connection] {
        note.allConnections
    }

    /// Number of connections.
    public var connectionCount: Int {
        note.allConnections.count
    }

    // MARK: - Cleanup

    deinit {
        autoSaveTask?.cancel()
    }
}
