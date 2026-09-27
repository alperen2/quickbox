import AppKit
import Combine
import Foundation
import QuickboxCore

/// Optional cloud sync for the app. Owns sign-in, the outbox and the sync schedule, and
/// publishes status for Settings. While disconnected nothing is recorded and the app behaves
/// exactly as a local-folder app.
@MainActor
final class CloudSyncController: ObservableObject {
    @Published private(set) var isConnected: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var pendingChanges = 0
    @Published private(set) var statusMessage: String?

    /// Called on the main actor after cloud changes were written to the local folder.
    var onRemoteChanges: (() -> Void)?

    let outbox: SyncOutbox
    private let authenticator: CloudAuthenticator
    private let engine: SyncEngine
    private let stateStore: SyncStateStoring
    private var timer: Timer?
    private var pendingSync: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    static let syncInterval: TimeInterval = 60
    static let localChangeDelay: Duration = .seconds(2)

    init(storageResolver: StorageResolving, supportDirectory: URL = CloudSyncController.defaultSupportDirectory) {
        let authenticator = CloudAuthenticator()
        let stateStore = FileSyncStateStore(fileURL: supportDirectory.appendingPathComponent("cloud-sync-state.json"))
        let outbox = SyncOutbox(fileURL: supportDirectory.appendingPathComponent("cloud-sync-outbox.json"), isRecording: authenticator.isSignedIn)
        self.authenticator = authenticator
        self.stateStore = stateStore
        self.outbox = outbox
        self.engine = SyncEngine(
            api: HTTPCloudSyncAPI(authenticator: authenticator),
            mirror: LocalMirror(storageResolver: storageResolver),
            outbox: outbox,
            stateStore: stateStore
        )
        self.isConnected = authenticator.isSignedIn
        self.lastSyncedAt = stateStore.load().lastSyncedAt
        self.pendingChanges = outbox.count

        if isConnected {
            startSchedule()
        }
    }

    nonisolated static var defaultSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("quickbox", isDirectory: true)
    }

    /// Called by the storage decorators (from any thread) after quickbox changed a local file.
    nonisolated func localFilesChanged() {
        Task { @MainActor in
            self.engine.noteLocalWrites()
            self.pendingChanges = self.outbox.count
            self.scheduleSync(after: Self.localChangeDelay)
        }
    }

    func connect() async {
        statusMessage = nil
        do {
            try await authenticator.signIn()
            outbox.setRecording(true)
            isConnected = true
            startSchedule()
            await syncNow()
        } catch CloudAuthError.cancelled {
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Stops syncing and forgets the cloud session. Local files stay as they are.
    func disconnect() {
        stopSchedule()
        authenticator.signOut()
        outbox.setRecording(false)
        outbox.removeAll()
        stateStore.clear()
        isConnected = false
        lastSyncedAt = nil
        pendingChanges = 0
        statusMessage = nil
    }

    func syncNow() async {
        guard isConnected, !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            pendingChanges = outbox.count
        }

        do {
            let report = try await engine.sync()
            lastSyncedAt = stateStore.load().lastSyncedAt ?? lastSyncedAt
            statusMessage = Self.message(for: report)
            if !report.changedPaths.isEmpty {
                onRemoteChanges?()
            }
        } catch CloudAuthError.signedOut {
            disconnect()
            statusMessage = CloudAuthError.signedOut.errorDescription
        } catch {
            // Offline or a server hiccup: changes stay queued and the next pass retries.
            statusMessage = "Sync paused: \(error.localizedDescription)"
        }
    }

    private func scheduleSync(after delay: Duration) {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func startSchedule() {
        stopSchedule()
        timer = Timer.scheduledTimer(withTimeInterval: Self.syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.syncNow() }
        }
        scheduleSync(after: .zero)
    }

    private func stopSchedule() {
        timer?.invalidate()
        timer = nil
        pendingSync?.cancel()
        pendingSync = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private static func message(for report: SyncReport) -> String? {
        var parts: [String] = []
        if !report.conflictCopies.isEmpty {
            parts.append("Kept \(report.conflictCopies.count) locally edited file(s) in \(LocalMirror.conflictsFolder).")
        }
        if report.rejectedOps > 0 {
            parts.append("\(report.rejectedOps) change(s) could not be applied in the cloud (the task may have been removed elsewhere).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
