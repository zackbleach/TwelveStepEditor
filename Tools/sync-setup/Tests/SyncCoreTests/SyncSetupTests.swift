import Foundation
import Testing
@testable import SyncCore

/// Runs every scenario against temporary folders and a throwaway preferences domain, so the real
/// 12 Step Editor settings are never touched. One shared domain (cleared before and after each
/// test), so the tests run one at a time.
@Suite(.serialized)
final class SyncSetupTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "syncsetup-\(UUID().uuidString)")
    let domain = "com.zackbleach.syncsetup.tests"
    var running = false
    lazy var setup = SyncSetup(environment: .init(
        prefsDomain: domain,
        iCloudRoot: root.appending(path: "iCloud"),
        backupRoot: root.appending(path: "Backups"),
        localFolder: root.appending(path: "Local"),
        isEditorRunning: { [unowned self] in running }))

    init() throws {
        CFPreferencesSetAppValue("PRESET_DIR" as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        try FileManager.default.createDirectory(at: root.appending(path: "iCloud"), withIntermediateDirectories: true)
        try writeFiles(in: root.appending(path: "Local"), contents: "local")
    }

    deinit {
        CFPreferencesSetAppValue("PRESET_DIR" as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
        try? FileManager.default.removeItem(at: root)
    }

    func writeFiles(in folder: URL, contents: String, only files: [String] = SyncSetup.presetFiles) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try Data("\(contents) \(file)".utf8).write(to: folder.appending(path: file)) }
    }

    func read(_ folder: URL, _ file: String) throws -> String {
        String(decoding: try Data(contentsOf: folder.appending(path: file)), as: UTF8.self)
    }

    @Test func enableBacksUpCopiesAndPointsTheEditorAtICloud() throws {
        #expect(setup.currentState() == .local(folder: root.appending(path: "Local")))
        let result = try setup.enable()
        #expect(result.copiedFiles)
        #expect(setup.currentState() == .synced(folder: setup.syncedFolder))
        #expect(try read(setup.syncedFolder, "12Step.json") == "local 12Step.json")
        #expect(try read(result.backup.appending(path: "presets"), "setlist.json") == "local setlist.json")
        #expect(try read(result.backup, "previous-PRESET_DIR.txt") == "\n")
        #expect(throws: SyncError.alreadyEnabled) { try self.setup.enable() }
    }

    @Test func disableBringsTheLatestFilesBack() throws {
        _ = try setup.enable()
        try writeFiles(in: setup.syncedFolder, contents: "edited on phone")
        let result = try setup.disable()
        guard case .local(let folder) = setup.currentState() else { Issue.record("still synced"); return }
        #expect(folder.standardizedFileURL.path == root.appending(path: "Local").standardizedFileURL.path)
        #expect(try read(root.appending(path: "Local"), "12Step.json") == "edited on phone 12Step.json")
        #expect(try read(result.backup.appending(path: "local-presets"), "12Step.json") == "local 12Step.json")
        // The iCloud copy stays.
        #expect(try read(setup.syncedFolder, "settings.json") == "edited on phone settings.json")
        #expect(throws: SyncError.notEnabled) { try self.setup.disable() }
    }

    @Test func refusesWhileTheEditorIsRunningAndChangesNothing() throws {
        running = true
        #expect(throws: SyncError.editorRunning) { try self.setup.enable() }
        #expect(setup.presetDirPreference() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Backups").path))
    }

    @Test func existingCloudFilesNeedConsent() throws {
        try writeFiles(in: setup.syncedFolder, contents: "other mac")
        #expect(setup.status().cloudContents == .complete)
        #expect(throws: SyncError.cloudAlreadyHasFiles) { try self.setup.enable() }
        let result = try setup.enable(useExistingCloudFiles: true)
        #expect(!result.copiedFiles)
        #expect(try read(setup.syncedFolder, "12Step.json") == "other mac 12Step.json")
    }

    @Test func partialCloudFolderAndMissingFilesAreRefused() throws {
        try writeFiles(in: setup.syncedFolder, contents: "x", only: ["12Step.json"])
        #expect(throws: SyncError.cloudHasSomeFiles) { try self.setup.enable() }
        try FileManager.default.removeItem(at: setup.syncedFolder)
        try FileManager.default.removeItem(at: root.appending(path: "Local/setlist.json"))
        #expect(throws: SyncError.missingEditorFiles(["setlist.json"], folder: root.appending(path: "Local"))) { try self.setup.enable() }
        try FileManager.default.removeItem(at: root.appending(path: "iCloud"))
        #expect(setup.status().iCloudAvailable == false)
    }
}
