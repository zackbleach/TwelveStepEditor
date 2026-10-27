// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation

/// Moves the desktop 12 Step Editor's working folder to iCloud Drive and back. Nothing inside the
/// editor app is modified: it only changes the editor's `PRESET_DIR` preference and copies the four
/// preset files, always backing up first. Same steps as `Tools/mac-sync/*.command`.
public final class SyncSetup {
    public static let presetFiles = ["12Step.json", "setlist.json", "settings.json", "Blank.twelvesteppreset"]
    public static let editorBundleID = "KMI.12-Step-Editor"

    /// Everything that touches the outside world, so tests can use temporary folders and a
    /// throwaway preferences domain.
    public struct Environment {
        public var prefsDomain: String
        public var iCloudRoot: URL
        public var backupRoot: URL
        public var localFolder: URL
        public var isEditorRunning: () -> Bool
        public var now: () -> Date

        public init(prefsDomain: String, iCloudRoot: URL, backupRoot: URL, localFolder: URL,
                    isEditorRunning: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
            self.prefsDomain = prefsDomain
            self.iCloudRoot = iCloudRoot
            self.backupRoot = backupRoot
            self.localFolder = localFolder
            self.isEditorRunning = isEditorRunning
            self.now = now
        }

        /// The real locations on this Mac. For testing, the same environment variables as the old
        /// scripts override them: TWELVESTEP_PREFS_DOMAIN, TWELVESTEP_ICLOUD_DIR,
        /// TWELVESTEP_BACKUP_ROOT, TWELVESTEP_LOCAL_DIR and TWELVESTEP_SKIP_RUNNING_CHECK=1.
        public static func live(isEditorRunning: @escaping () -> Bool) -> Environment {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let overrides = ProcessInfo.processInfo.environment
            func folder(_ key: String, default path: String) -> URL {
                overrides[key].map { URL(filePath: $0, directoryHint: .isDirectory) } ?? home.appending(path: path)
            }
            let skipRunningCheck = overrides["TWELVESTEP_SKIP_RUNNING_CHECK"] == "1"
            return Environment(
                prefsDomain: overrides["TWELVESTEP_PREFS_DOMAIN"] ?? "com.keithmcmillen.12 Step Editor",
                iCloudRoot: folder("TWELVESTEP_ICLOUD_DIR", default: "Library/Mobile Documents/com~apple~CloudDocs"),
                backupRoot: folder("TWELVESTEP_BACKUP_ROOT", default: "Documents/12 Step Editor Backups"),
                localFolder: folder("TWELVESTEP_LOCAL_DIR", default: "Library/Application Support/KeithMcMillenInstruments/12 Step Editor"),
                isEditorRunning: skipRunningCheck ? { false } : isEditorRunning)
        }
    }

    public enum State: Equatable {
        /// The editor uses its own folder (or another non-iCloud folder).
        case local(folder: URL)
        /// The editor uses iCloud Drive/12 Step Editor.
        case synced(folder: URL)
    }

    /// What's in iCloud Drive/12 Step Editor before turning sync on.
    public enum CloudContents: Equatable {
        case empty
        /// A full set, perhaps from another Mac: sync can use it instead of copying.
        case complete
        case partial
    }

    public struct Status: Equatable {
        public var state: State
        public var editorRunning: Bool
        public var iCloudAvailable: Bool
        /// Preset files missing from the folder that would be copied from.
        public var missingFiles: [String]
        public var cloudContents: CloudContents
    }

    public struct Result: Equatable {
        public var backup: URL
        public var copiedFiles: Bool
    }

    public let environment: Environment
    public var syncedFolder: URL { environment.iCloudRoot.appending(path: "12 Step Editor", directoryHint: .isDirectory) }

    public init(environment: Environment) {
        self.environment = environment
    }

    // MARK: Status

    public func status() -> Status {
        let fileManager = FileManager.default
        let state = currentState()
        let source: URL = switch state {
        case .local(let folder): folder
        case .synced(let folder): folder
        }
        let present = Self.presetFiles.filter { fileManager.fileExists(atPath: syncedFolder.appending(path: $0).path) }
        return Status(
            state: state,
            editorRunning: environment.isEditorRunning(),
            iCloudAvailable: fileManager.fileExists(atPath: environment.iCloudRoot.path),
            missingFiles: Self.presetFiles.filter { !fileManager.fileExists(atPath: source.appending(path: $0).path) },
            cloudContents: present.isEmpty ? .empty : present.count == Self.presetFiles.count ? .complete : .partial)
    }

    public func currentState() -> State {
        guard let path = presetDirPreference(), !path.isEmpty else { return .local(folder: environment.localFolder) }
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        return folder.standardizedFileURL.path == syncedFolder.standardizedFileURL.path ? .synced(folder: folder) : .local(folder: folder)
    }

    // MARK: Turning sync on and off

    /// Backs up the editor's folder, copies the preset files to iCloud Drive (unless iCloud already
    /// has a complete set and `useExistingCloudFiles` is true), then points the editor there.
    public func enable(useExistingCloudFiles: Bool = false) throws -> Result {
        let status = status()
        guard case .local(let source) = status.state else { throw SyncError.alreadyEnabled }
        guard !status.editorRunning else { throw SyncError.editorRunning }
        guard status.iCloudAvailable else { throw SyncError.iCloudUnavailable }
        guard status.missingFiles.isEmpty else { throw SyncError.missingEditorFiles(status.missingFiles, folder: source) }
        let copy: Bool
        switch status.cloudContents {
        case .empty: copy = true
        case .complete:
            guard useExistingCloudFiles else { throw SyncError.cloudAlreadyHasFiles }
            copy = false
        case .partial: throw SyncError.cloudHasSomeFiles
        }

        let fileManager = FileManager.default
        let backup = environment.backupRoot.appending(path: stamp(), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: backup.appending(path: "presets"))
        try Data(((presetDirPreference() ?? "") + "\n").utf8).write(to: backup.appending(path: "previous-PRESET_DIR.txt"))

        if copy {
            try fileManager.createDirectory(at: syncedFolder, withIntermediateDirectories: true)
            for file in Self.presetFiles {
                try copyVerified(source.appending(path: file), to: syncedFolder.appending(path: file))
            }
        }
        try setPresetDirPreference(syncedFolder.path)
        return Result(backup: backup, copiedFiles: copy)
    }

    /// Backs up the editor's own folder, copies the latest preset files from iCloud Drive into it,
    /// then points the editor back at it. The iCloud copy is left in place.
    public func disable() throws -> Result {
        let status = status()
        guard case .synced(let synced) = status.state else { throw SyncError.notEnabled }
        guard !status.editorRunning else { throw SyncError.editorRunning }
        guard status.missingFiles.isEmpty else { throw SyncError.missingCloudFiles(status.missingFiles, folder: synced) }

        let fileManager = FileManager.default
        let local = environment.localFolder
        let backup = environment.backupRoot.appending(path: stamp() + "-before-disable", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: local, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        if let items = try? fileManager.contentsOfDirectory(atPath: local.path), !items.isEmpty {
            try fileManager.copyItem(at: local, to: backup.appending(path: "local-presets"))
        }
        for file in Self.presetFiles {
            try copyVerified(synced.appending(path: file), to: local.appending(path: file))
        }
        try setPresetDirPreference(local.path)
        return Result(backup: backup, copiedFiles: true)
    }

    // MARK: Helpers

    private func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: environment.now())
    }

    private func copyVerified(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: try temporaryCopy(of: source, near: destination))
        } else {
            try fileManager.copyItem(at: source, to: destination)
        }
        guard try Data(contentsOf: source) == Data(contentsOf: destination) else {
            throw SyncError.copyNotVerified(source.lastPathComponent)
        }
    }

    private func temporaryCopy(of source: URL, near destination: URL) throws -> URL {
        let temporary = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString)-\(destination.lastPathComponent)")
        try FileManager.default.copyItem(at: source, to: temporary)
        return temporary
    }

    func presetDirPreference() -> String? {
        let domain = environment.prefsDomain as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("PRESET_DIR" as CFString, domain) as? String
    }

    private func setPresetDirPreference(_ path: String) throws {
        let domain = environment.prefsDomain as CFString
        CFPreferencesSetAppValue("PRESET_DIR" as CFString, path as CFString, domain)
        guard CFPreferencesAppSynchronize(domain), presetDirPreference() == path else { throw SyncError.preferenceNotSaved }
    }
}

public enum SyncError: LocalizedError, Equatable {
    case alreadyEnabled
    case notEnabled
    case editorRunning
    case iCloudUnavailable
    case missingEditorFiles([String], folder: URL)
    case missingCloudFiles([String], folder: URL)
    case cloudAlreadyHasFiles
    case cloudHasSomeFiles
    case copyNotVerified(String)
    case preferenceNotSaved

    public var errorDescription: String? {
        switch self {
        case .alreadyEnabled: "iCloud sync is already on."
        case .notEnabled: "iCloud sync isn't on."
        case .editorRunning: "Quit the 12 Step Editor first (⌘Q)."
        case .iCloudUnavailable: "iCloud Drive isn't turned on. Turn it on in System Settings › Apple Account › iCloud."
        case .missingEditorFiles(let files, let folder):
            "The editor's folder (\(folder.path)) is missing \(files.joined(separator: ", ")). Open the 12 Step Editor once so it creates its files, then quit it and try again."
        case .missingCloudFiles(let files, _):
            "iCloud Drive › 12 Step Editor is missing \(files.joined(separator: ", ")). Wait for iCloud to finish downloading, then try again."
        case .cloudAlreadyHasFiles: "iCloud Drive › 12 Step Editor already has a full set of preset files."
        case .cloudHasSomeFiles: "iCloud Drive › 12 Step Editor has only some of the editor's files. Move that folder somewhere else, then try again."
        case .copyNotVerified(let file): "The copy of \(file) didn't match the original."
        case .preferenceNotSaved: "Couldn't update the 12 Step Editor's settings."
        }
    }
}
