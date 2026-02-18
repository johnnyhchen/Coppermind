// SyncManager.swift — CloudKit sync orchestrator via SwiftData + NSPersistentCloudKitContainer
// CoppermindCore
//
// Architecture:
//   SwiftData ModelContainer configured with .private CloudKit database.
//   All @Model types (Note, Connection, AudioRecording, NoteGroup) auto-sync.
//   Conflict resolution:
//     • Scalars → last-writer-wins (NSMergePolicy default)
//     • Connections → merge (union of both sides)
//     • Audio → CKAsset via @Attribute(.externalStorage)
//   Subscribes to NSPersistentCloudKitContainer.eventChangedNotification
//   to track sync lifecycle and trigger post-import priority recalculation.

import Foundation
import SwiftData
import CoreData
import Combine
#if canImport(Observation)
import Observation
#endif

// MARK: - SyncState

/// Observable sync status for UI binding.
public enum SyncState: Sendable, Equatable, CustomStringConvertible {
    case syncing
    case synced
    case error(String)
    case offline

    public var description: String {
        switch self {
        case .syncing:          return "Syncing…"
        case .synced:           return "Up to date"
        case .error(let msg):   return "Sync error: \(msg)"
        case .offline:          return "Offline"
        }
    }
}

// MARK: - SyncError

public enum SyncError: Error, Sendable, LocalizedError {
    case containerCreationFailed(String)
    case syncDisabled
    case priorityRecalculationFailed(String)
    case cloudKitAccountUnavailable

    public var errorDescription: String? {
        switch self {
        case .containerCreationFailed(let reason):
            return "Failed to create CloudKit container: \(reason)"
        case .syncDisabled:
            return "CloudKit sync is disabled."
        case .priorityRecalculationFailed(let reason):
            return "Priority recalculation failed: \(reason)"
        case .cloudKitAccountUnavailable:
            return "iCloud account not available."
        }
    }
}

// MARK: - SyncManager

/// Manages CloudKit synchronization for the Coppermind SwiftData store.
///
/// Uses SwiftData's built-in CloudKit integration via `ModelConfiguration(cloudKitDatabase:)`.
/// All `@Model` types auto-sync to the private CloudKit database (`iCloud.com.coppermind.notes`).
///
/// ## Usage
/// ```swift
/// let syncManager = SyncManager()
/// let container = try syncManager.makeCloudKitContainer()
/// // Inject container into SwiftUI via .modelContainer(container)
/// // Observe syncManager.syncState for UI status
/// ```
@Observable
@MainActor
public final class SyncManager: Sendable {

    // MARK: - Constants

    private static let containerIdentifier = "iCloud.com.coppermind.notes"
    private static let storeName = "Coppermind"

    // MARK: - Observable State

    /// Current sync lifecycle state. Bind to this in SwiftUI for status indicators.
    public private(set) var syncState: SyncState = .offline

    /// Timestamp of the last successful sync completion.
    public private(set) var lastSyncDate: Date?

    /// Number of local changes pending upload to CloudKit.
    public private(set) var pendingChanges: Int = 0

    /// Most recent error message for banner display.
    public private(set) var lastErrorMessage: String?

    /// Whether the error banner should be shown.
    public private(set) var showErrorBanner: Bool = false

    // MARK: - Private State

    /// Combine subscriptions for event notifications.
    private var cancellables = Set<AnyCancellable>()

    /// Cached reference to the priority scorer for post-import recalculation.
    nonisolated private let scorer = PriorityScorer()

    /// Whether CloudKit sync is enabled in this configuration.
    private var isCloudKitEnabled: Bool = true

    // MARK: - Init

    public init() {}

    // MARK: - Container Factory

    /// Creates a SwiftData `ModelContainer` configured for CloudKit private database sync.
    ///
    /// The container uses `NSPersistentCloudKitContainer` under the hood via SwiftData's
    /// `cloudKitDatabase: .private(containerIdentifier)` configuration.
    ///
    /// All `@Model` types (Note, Connection, AudioRecording, NoteGroup) are registered
    /// and will auto-sync when the user is signed into iCloud.
    ///
    /// - Parameter inMemory: If `true`, uses in-memory store (for testing). Disables CloudKit.
    /// - Returns: A fully configured `ModelContainer`.
    public func makeCloudKitContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            Note.self,
            Connection.self,
            AudioRecording.self,
            NoteGroup.self,
        ])

        let configuration: ModelConfiguration

        if inMemory {
            // In-memory configuration for tests — no CloudKit
            configuration = ModelConfiguration(
                Self.storeName,
                schema: schema,
                isStoredInMemoryOnly: true
            )
            isCloudKitEnabled = false
        } else {
            // Production configuration with CloudKit private database
            configuration = ModelConfiguration(
                Self.storeName,
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(Self.containerIdentifier)
            )
            isCloudKitEnabled = true
        }

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            throw SyncError.containerCreationFailed(error.localizedDescription)
        }

        if isCloudKitEnabled {
            subscribeToCloudKitEvents(container: container)
            syncState = .syncing
        } else {
            syncState = .offline
        }

        return container
    }

    // MARK: - In-Memory Container (Testing)

    /// Creates an in-memory container with no CloudKit sync, suitable for unit tests.
    public func makeTestContainer() throws -> ModelContainer {
        return try makeCloudKitContainer(inMemory: true)
    }

    // MARK: - CloudKit Event Subscription

    /// Subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` to monitor
    /// setup, import, and export events from the CloudKit sync engine.
    ///
    /// On import completion → triggers priority recalculation for all active notes.
    /// On error → sets the error banner for UI display.
    private func subscribeToCloudKitEvents(container: ModelContainer) {
        // NSPersistentCloudKitContainer.eventChangedNotification fires for each sync phase.
        // The userInfo contains an NSPersistentCloudKitContainer.Event describing what happened.
        NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            self.handleCloudKitEvent(notification, container: container)
        }
        .store(in: &cancellables)
    }

    /// Processes a single CloudKit sync event notification.
    private func handleCloudKitEvent(_ notification: Notification, container: ModelContainer) {
        guard let event = notification.userInfo?[
            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        // Update sync state based on event type and completion
        if event.endDate == nil {
            // Event is still in progress
            syncState = .syncing
            return
        }

        // Event has completed
        if let error = event.error {
            // Sync error occurred
            let message = error.localizedDescription
            syncState = .error(message)
            lastErrorMessage = message
            showErrorBanner = true

            // Auto-dismiss banner after 8 seconds
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                self.showErrorBanner = false
            }
            return
        }

        // Successful completion
        switch event.type {
        case .import:
            // Remote changes imported — recalculate priorities
            syncState = .synced
            lastSyncDate = Date.now
            recalculatePrioritiesAfterImport(container: container)

        case .export:
            // Local changes pushed to CloudKit
            syncState = .synced
            lastSyncDate = Date.now
            pendingChanges = 0

        case .setup:
            // Initial CloudKit schema setup complete
            syncState = .synced
            lastSyncDate = Date.now

        @unknown default:
            syncState = .synced
        }
    }

    // MARK: - Post-Import Priority Recalculation

    /// After CloudKit imports new/updated notes, recalculate priority scores
    /// so the home feed reflects the latest state from all devices.
    private func recalculatePrioritiesAfterImport(container: ModelContainer) {
        Task { @MainActor in
            let context = container.mainContext
            do {
                try scorer.recalculateAll(in: context)
            } catch {
                let message = "Priority recalculation after sync failed: \(error.localizedDescription)"
                lastErrorMessage = message
                showErrorBanner = true
            }
        }
    }

    // MARK: - Error Banner Dismissal

    /// Manually dismiss the error banner.
    public func dismissErrorBanner() {
        showErrorBanner = false
        lastErrorMessage = nil
    }

    // MARK: - Pending Changes Tracking

    /// Increment the pending changes counter when a local edit occurs.
    /// Call this from view models after inserting/updating/deleting model objects.
    public func trackLocalChange() {
        pendingChanges += 1
        if isCloudKitEnabled {
            syncState = .syncing
        }
    }

    // MARK: - Cleanup

    /// Remove all Combine subscriptions. Call on app termination if needed.
    public func tearDown() {
        cancellables.removeAll()
    }
}
