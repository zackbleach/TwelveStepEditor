import AppKit
import Observation
import SyncCore

@MainActor
@Observable
final class SyncModel {
    private let setup = SyncSetup(environment: .live(isEditorRunning: { SyncModel.editorApp != nil }))
    private(set) var status: SyncSetup.Status
    private(set) var lastResult: Outcome?
    var error: String?
    /// Turn on even though iCloud Drive already has a complete set (perhaps from another Mac).
    var useExistingCloudFiles = false
    private var observers: [NSObjectProtocol] = []

    enum Outcome: Equatable {
        case enabled(SyncSetup.Result)
        case disabled(SyncSetup.Result)
    }

    init() {
        status = setup.status()
        // Keep the checklist live as the editor quits or launches.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    var syncedFolder: URL { setup.syncedFolder }
    var backupRoot: URL { setup.environment.backupRoot }
    var isSynced: Bool { if case .synced = status.state { true } else { false } }

    var canEnable: Bool {
        !isSynced && !status.editorRunning && status.iCloudAvailable && status.missingFiles.isEmpty
            && (status.cloudContents == .empty || (status.cloudContents == .complete && useExistingCloudFiles))
    }

    func refresh() {
        status = setup.status()
    }

    func enable() {
        perform { .enabled(try setup.enable(useExistingCloudFiles: useExistingCloudFiles)) }
    }

    func disable() {
        perform { .disabled(try setup.disable()) }
    }

    func quitEditor() {
        Self.editorApp?.terminate()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func perform(_ action: () throws -> Outcome) {
        do {
            lastResult = try action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    nonisolated private static var editorApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == SyncSetup.editorBundleID || $0.executableURL?.path.contains("12 Step Editor.app/") == true
        }
    }
}
