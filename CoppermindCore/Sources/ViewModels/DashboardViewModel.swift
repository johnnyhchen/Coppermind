// DashboardViewModel.swift — Drives the home / dashboard overview UI
// CoppermindCore

import Foundation
import Observation
import SwiftData

/// ViewModel for the dashboard / home view.
/// Aggregates high-priority notes, recent activity, cluster summaries, and stats.
@Observable
@MainActor
public final class DashboardViewModel {

    // MARK: - Dashboard Sections

    /// Summary statistics for the dashboard header.
    public struct Stats: Sendable {
        public let totalNotes: Int
        public let totalTasks: Int
        public let completedTasks: Int
        public let overdueTasks: Int
        public let totalConnections: Int
        public let clusterCount: Int

        public var taskCompletionRate: Double {
            guard totalTasks > 0 else { return 0 }
            return Double(completedTasks) / Double(totalTasks)
        }
    }

    // MARK: - State

    public var stats: Stats = Stats(
        totalNotes: 0, totalTasks: 0, completedTasks: 0,
        overdueTasks: 0, totalConnections: 0, clusterCount: 0
    )

    /// Top-priority notes for the "Focus" section.
    public var focusNotes: [Note] = []

    /// Recently modified notes.
    public var recentNotes: [Note] = []

    /// Notes from audio capture that may need review.
    public var pendingAudioNotes: [Note] = []

    /// Cluster summaries for the "Connections" section.
    public var clusterSummaries: [ClusterSummary] = []

    public var isLoading: Bool = false
    public var errorMessage: String?

    /// A lightweight cluster summary for dashboard display.
    public struct ClusterSummary: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let noteCount: Int
        public let topNotes: [String] // Titles

        public init(id: UUID, name: String, noteCount: Int, topNotes: [String]) {
            self.id = id
            self.name = name
            self.noteCount = noteCount
            self.topNotes = topNotes
        }
    }

    // MARK: - Configuration

    /// Maximum notes to show in each dashboard section.
    public let maxFocusNotes: Int = 5
    public let maxRecentNotes: Int = 10

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let priorityScorer: PriorityScorer

    // MARK: - Init

    public init(modelContext: ModelContext, priorityScorer: PriorityScorer = PriorityScorer()) {
        self.modelContext = modelContext
        self.priorityScorer = priorityScorer
    }

    // MARK: - Data Loading

    /// Refresh all dashboard data.
    public func refresh() async {
        // TODO: Fetch all sections in parallel.

        isLoading = true
        errorMessage = nil

        do {
            async let fetchedFocus = loadFocusNotes()
            async let fetchedRecent = loadRecentNotes()
            async let fetchedAudio = loadPendingAudioNotes()
            async let fetchedStats = computeStats()
            async let fetchedClusters = loadClusterSummaries()

            focusNotes = try await fetchedFocus
            recentNotes = try await fetchedRecent
            pendingAudioNotes = try await fetchedAudio
            stats = try await fetchedStats
            clusterSummaries = try await fetchedClusters

        } catch {
            errorMessage = "Failed to load dashboard: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Section Loaders

    private func loadFocusNotes() throws -> [Note] {
        // TODO: Fetch non-archived notes sorted by priorityScore descending, take top N.
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.priorityScore, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        return Array(all.prefix(maxFocusNotes))
    }

    private func loadRecentNotes() throws -> [Note] {
        // TODO: Fetch notes sorted by updatedAt descending, take top N.
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        return Array(all.prefix(maxRecentNotes))
    }

    private func loadPendingAudioNotes() throws -> [Note] {
        // TODO: Fetch audio-source notes that may need transcription review.
        let audioSource = NoteSource.audio
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.source == audioSource && !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func computeStats() throws -> Stats {
        let allNotes = try modelContext.fetch(FetchDescriptor<Note>())
        let taskNotes = allNotes.filter { $0.category == .task }
        let allConnections = try modelContext.fetch(FetchDescriptor<Connection>())
        let allGroups = try modelContext.fetch(FetchDescriptor<NoteGroup>())

        return Stats(
            totalNotes: allNotes.count,
            totalTasks: taskNotes.count,
            completedTasks: taskNotes.filter { $0.isCompleted == true }.count,
            overdueTasks: taskNotes.filter(\.isOverdue).count,
            totalConnections: allConnections.count,
            clusterCount: allGroups.filter(\.autoGenerated).count
        )
    }

    private func loadClusterSummaries() throws -> [ClusterSummary] {
        // TODO: Fetch NoteGroups with origin == .automatic, map to ClusterSummary.
        let descriptor = FetchDescriptor<NoteGroup>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let groups = try modelContext.fetch(descriptor)

        return groups
            .filter(\.autoGenerated)
            .map { group in
                ClusterSummary(
                    id: group.id,
                    name: group.name,
                    noteCount: group.notes.count,
                    topNotes: group.notes.prefix(3).map(\.title)
                )
            }
    }
}
