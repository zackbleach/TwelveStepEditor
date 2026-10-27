// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.

import Foundation
import Observation

/// Where the app's presets live: a folder on this device (seeded from the factory presets), or a
/// folder the user picked in Files (iCloud Drive, Dropbox, …), typically shared with the desktop editor.
@MainActor
@Observable
public final class PresetFolderStore {
    public enum Source: Equatable, Sendable {
        case onDevice
        case folder(URL)

        public var title: String {
            switch self {
            case .onDevice: "On this device"
            case .folder(let url): url.lastPathComponent
            }
        }
    }

    public private(set) var source: Source = .onDevice
    public private(set) var contents: PresetFolderContents?
    public private(set) var loadError: String?
    public private(set) var lastLoaded: Date?
    /// The exact bytes of each file as last read or written, to detect edits made elsewhere.
    private var loadedData: [String: Data] = [:]

    private let defaults: UserDefaults
    private let onDeviceFolder: URL
    static let bookmarkKey = "presetFolderBookmark"

    /// - Parameter onDeviceFolder: defaults to `Documents/12 Step Editor` (visible in the Files app).
    public init(defaults: UserDefaults = .standard, onDeviceFolder: URL? = nil) {
        self.defaults = defaults
        self.onDeviceFolder = onDeviceFolder ?? URL.documentsDirectory.appendingPathComponent("12 Step Editor", isDirectory: true)
        if let folder = Self.resolveBookmark(defaults.data(forKey: Self.bookmarkKey)) {
            source = .folder(folder)
        }
    }

    public var folderURL: URL {
        switch source {
        case .onDevice: onDeviceFolder
        case .folder(let url): url
        }
    }

    // MARK: Loading

    public func reload() {
        do {
            if source == .onDevice { try seedOnDeviceFolder() }
            let (contents, data) = try Self.readFolder(folderURL)
            self.contents = contents
            loadedData = data
            loadError = nil
            lastLoaded = Date()
        } catch {
            contents = nil
            loadedData = [:]
            loadError = error.localizedDescription
        }
    }

    /// Switches to a folder picked by the user and remembers it across launches.
    public func useFolder(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? folder.bookmarkData() {
            defaults.set(bookmark, forKey: Self.bookmarkKey)
        }
        source = .folder(folder)
        reload()
    }

    public func useOnDeviceFolder() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        source = .onDevice
        reload()
    }

    /// Copies any missing files from the factory presets; never overwrites.
    private func seedOnDeviceFolder() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: onDeviceFolder, withIntermediateDirectories: true)
        guard let factory = Bundle.module.url(forResource: "FactoryPresets", withExtension: nil) else { return }
        for file in PresetFolderContents.requiredFiles where !fileManager.fileExists(atPath: onDeviceFolder.appendingPathComponent(file).path) {
            try fileManager.copyItem(at: factory.appendingPathComponent(file), to: onDeviceFolder.appendingPathComponent(file))
        }
    }

    /// Replaces the on-device files with the factory presets. Not offered for shared folders.
    public func restoreFactoryPresets() throws {
        guard source == .onDevice else { throw PresetFolderError.readOnlySource }
        let factory = try PresetFolderContents.factory()
        try commit(factory, force: true)
    }

    // MARK: Saving

    /// Writes whichever of `12Step.json`, `setlist.json` and `settings.json` differ from what's
    /// loaded, formatted exactly as the desktop editor writes them. If any of those files changed
    /// on disk since loading, nothing is written and the latest files are reloaded.
    public func commit(_ newContents: PresetFolderContents, force: Bool = false) throws {
        guard let current = contents else { throw PresetFolderError.readOnlySource }
        var writes: [(file: String, data: Data)] = []
        if force || newContents.library != current.library {
            writes.append((PresetFolderContents.libraryFile, newContents.library.jsonData()))
        }
        if force || newContents.setlist != current.setlist {
            writes.append((PresetFolderContents.setlistFile, newContents.setlist.jsonData()))
        }
        if force || newContents.settings != current.settings {
            writes.append((PresetFolderContents.settingsFile, newContents.settings.jsonData()))
        }
        guard !writes.isEmpty else { return }

        do {
            try Self.write(writes, in: folderURL, expecting: force ? nil : loadedData)
        } catch let error as PresetFolderError {
            if case .changedOnDisk = error { reload() }
            throw error
        }
        var updated = newContents
        updated.blank = current.blank
        contents = updated
        for write in writes { loadedData[write.file] = write.data }
        lastLoaded = Date()
    }

    /// Convenience: saves one edited preset.
    public func save(_ preset: Preset) throws {
        guard var updated = contents, updated.library[key: preset.key] != nil else {
            throw PresetFolderError.invalid(file: PresetFolderContents.libraryFile, underlying: "no preset \(preset.key)")
        }
        updated.library[key: preset.key] = preset
        try commit(updated)
    }

    /// Applies a change to a copy of the contents and saves it.
    public func update(_ change: (inout PresetFolderContents) throws -> Void) throws {
        guard var updated = contents else { throw PresetFolderError.readOnlySource }
        try change(&updated)
        try commit(updated)
    }

    /// Like `update`, but the change shows immediately and the files are written in the
    /// background, one save after another. For quick, frequent edits such as reordering the
    /// setlist, where a coordinated write (especially to iCloud Drive) would make the UI stutter.
    /// If a save fails (for example because the file changed elsewhere), the latest files are
    /// reloaded and `onError` is called on the main actor.
    public func updateInBackground(_ change: (inout PresetFolderContents) throws -> Void,
                                   onError: @escaping @MainActor (Error) -> Void) throws {
        guard let current = contents else { throw PresetFolderError.readOnlySource }
        var updated = current
        try change(&updated)
        var writes: [(file: String, data: Data)] = []
        if updated.library != current.library { writes.append((PresetFolderContents.libraryFile, updated.library.jsonData())) }
        if updated.setlist != current.setlist { writes.append((PresetFolderContents.setlistFile, updated.setlist.jsonData())) }
        if updated.settings != current.settings { writes.append((PresetFolderContents.settingsFile, updated.settings.jsonData())) }
        guard !writes.isEmpty else { return }

        let expected = loadedData
        let folder = folderURL
        updated.blank = current.blank
        contents = updated
        for write in writes { loadedData[write.file] = write.data }
        lastLoaded = Date()

        let previous = pendingWrite
        pendingWrite = Task {
            await previous?.value
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.write(writes, in: folder, expecting: expected) }
            }.value
            if case .failure(let error) = result {
                reload()
                onError(error)
            }
        }
    }

    @ObservationIgnored
    /// The most recent background save, so saves happen in order.
    private var pendingWrite: Task<Void, Never>?

    /// Waits for background saves to finish (used before uploading and by tests).
    public func waitForPendingWrites() async {
        await pendingWrite?.value
    }

    nonisolated static func write(_ writes: [(file: String, data: Data)], in folder: URL, expecting expected: [String: Data]?) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        // Check every file first so a conflict writes nothing at all.
        if let expected {
            for write in writes {
                var current: Data?
                var readError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: folder.appendingPathComponent(write.file), options: [],
                                               error: &readError) { current = try? Data(contentsOf: $0) }
                if let readError { throw readError }
                guard current == expected[write.file] else { throw PresetFolderError.changedOnDisk(file: write.file) }
            }
        }
        for write in writes {
            var writeResult: Result<Void, Error> = .success(())
            var writeError: NSError?
            NSFileCoordinator().coordinate(writingItemAt: folder.appendingPathComponent(write.file), options: .forReplacing,
                                           error: &writeError) { url in
                writeResult = Result { try write.data.write(to: url, options: .atomic) }
            }
            if let writeError { throw writeError }
            try writeResult.get()
        }
    }

    // MARK: Helpers

    static func resolveBookmark(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    /// Reads all files inside one coordinated read of the folder, so an iCloud sync can't swap a
    /// file halfway through and the system downloads any files that are only in the cloud.
    static func readFolder(_ folder: URL) throws -> (PresetFolderContents, [String: Data]) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        var result: Result<(PresetFolderContents, [String: Data]), Error> =
            .failure(PresetFolderError.unreadable(file: folder.lastPathComponent, underlying: "not read"))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { coordinated in
            let missing = PresetFolderContents.missingFiles(in: coordinated)
            guard missing.isEmpty else {
                result = .failure(PresetFolderError.unreadable(file: missing.joined(separator: ", "),
                                                               underlying: "not in this folder. Pick the folder that contains the 12 Step Editor's files"))
                return
            }
            result = Result {
                var data: [String: Data] = [:]
                let contents = try PresetFolderContents.load(from: coordinated) { url in
                    let bytes = try Data(contentsOf: url)
                    data[url.lastPathComponent] = bytes
                    return bytes
                }
                return (contents, data)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}
